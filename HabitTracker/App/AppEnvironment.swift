import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    enum Phase {
        case launching
        case onboarding
        case authentication
        case ready
    }

    @Published var phase: Phase = .launching
    @Published var currentUser: AppUser?
    @Published var habits: [Habit] = []
    @Published var completions: [HabitCompletion] = []
    @Published var errorMessage: String?
    @Published var isBusy = false

    let authService: SupabaseAuthService
    let habitRepository: HabitRepository
    let checkInRepository: CheckInRepository
    let reminderService: ReminderService
    let purchaseService: PurchaseService
    let widgetSyncService: WidgetSyncService
    let analyticsService: AnalyticsService

    private let defaults: UserDefaults
    private let onboardingKey = "hasCompletedOnboarding"

    // All properties are initialized on the main actor due to the enclosing class annotation.
    init(
        authService: SupabaseAuthService,
        purchaseService: PurchaseService,
        reminderService: ReminderService,
        widgetSyncService: WidgetSyncService,
        analyticsService: AnalyticsService,
        defaults: UserDefaults,
        habitRepository: HabitRepository? = nil,
        checkInRepository: CheckInRepository? = nil
    ) {
        self.authService = authService
        self.purchaseService = purchaseService
        self.reminderService = reminderService
        self.widgetSyncService = widgetSyncService
        self.analyticsService = analyticsService
        self.defaults = defaults

        let localStore = LocalStore()
        let remote = SupabaseHabitRemoteDataSource()
        if let habitRepository { self.habitRepository = habitRepository } else { self.habitRepository = DefaultHabitRepository(localStore: localStore, remote: remote, authService: authService) }
        if let checkInRepository { self.checkInRepository = checkInRepository } else { self.checkInRepository = DefaultCheckInRepository(localStore: localStore, remote: remote, authService: authService) }
    }

    convenience init() {
        self.init(
            authService: SupabaseAuthService(),
            purchaseService: PurchaseService(),
            reminderService: DefaultReminderService(),
            widgetSyncService: WidgetSyncService(),
            analyticsService: AnalyticsService(),
            defaults: .standard
        )
    }

    func bootstrap() async {
        await MainActor.run { self.isBusy = true }

        do {
            let user = try await self.authService.restoreSession()
            await MainActor.run { self.currentUser = user }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }

        await self.refreshLocalState()
        if self.currentUser != nil {
            try? await self.syncAll()
        }
        await self.determinePhase()
        await MainActor.run { self.isBusy = false }
    }

    func completeOnboarding() {
        self.defaults.set(true, forKey: self.onboardingKey)
        self.analyticsService.track(.completedOnboarding)
        Task { await self.determinePhase() }
    }

    func signIn(email: String, password: String) async {
        await self.runBusyTask {
            let user = try await self.authService.signIn(email: email, password: password)
            await MainActor.run { self.currentUser = user }
            self.analyticsService.track(.signedIn)
            try await self.syncAll()
            await self.determinePhase()
        }
    }

    func signUp(email: String, password: String) async {
        await self.runBusyTask {
            let user = try await self.authService.signUp(email: email, password: password)
            await MainActor.run { self.currentUser = user }
            self.analyticsService.track(.createdAccount)
            try await self.syncAll()
            await self.determinePhase()
        }
    }

    func signOut() async {
        await self.runBusyTask {
            try await self.authService.signOut()
            await MainActor.run {
                self.currentUser = nil
                self.habits = []
                self.completions = []
            }
            await self.determinePhase()
        }
    }

    func purchaseUnlock() async {
        await self.determinePhase()
    }

    func restorePurchases() async {
        await self.determinePhase()
    }

    func createOrUpdateHabit(_ habit: Habit) async {
        await self.runBusyTask {
            try await self.habitRepository.saveHabit(habit)
            let fetchedHabits = try await self.habitRepository.fetchHabits()
            await MainActor.run { self.habits = fetchedHabits }
            try await self.reminderService.rescheduleNotifications(for: fetchedHabits)
            await self.widgetSyncService.publish(habits: fetchedHabits, completions: self.completions)
            self.analyticsService.track(.createdHabit)
        }
    }

    func archiveHabit(_ habit: Habit) async {
        await self.runBusyTask {
            try await self.habitRepository.archiveHabit(habit)
            let fetchedHabits = try await self.habitRepository.fetchHabits()
            await MainActor.run { self.habits = fetchedHabits }
            try await self.reminderService.rescheduleNotifications(for: fetchedHabits)
            await self.widgetSyncService.publish(habits: fetchedHabits, completions: self.completions)
        }
    }

    func recordCompletion(for habit: Habit, count: Int, note: String = "", date: Date = .now) async {
        guard let user = self.currentUser else { return }

        await self.runBusyTask {
            let startOfDay = Calendar.current.startOfDay(for: date)
            let existing = await self.completions.first {
                $0.habitId == habit.id && Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
            }
            let completion = HabitCompletion(
                id: existing?.id ?? UUID(),
                habitId: habit.id,
                userId: user.id,
                date: startOfDay,
                count: count,
                note: note,
                createdAt: existing?.createdAt ?? .now
            )
            try await self.checkInRepository.recordCompletion(completion)
            let fetchedCompletions = try await self.checkInRepository.fetchCompletions()
            let currentHabits: [Habit] = await MainActor.run {
                self.completions = fetchedCompletions
                return self.habits
            }
            self.widgetSyncService.publish(habits: currentHabits, completions: fetchedCompletions)
            self.analyticsService.track(.completedHabit)
        }
    }

    @MainActor
    func todayHabits(for date: Date = .now) -> [HabitWithProgress] {
        let todayCompletions = self.completions
        return self.habits
            .filter { $0.isDue(on: date) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { habit in
                HabitWithProgress(
                    habit: habit,
                    completion: todayCompletions.first {
                        $0.habitId == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date)
                    }
                )
            }
    }

    @MainActor
    func completionHistory(for habit: Habit) -> [HabitCompletion] {
        self.completions
            .filter { $0.habitId == habit.id }
            .sorted { $0.date > $1.date }
    }

    private func syncAll() async throws {
        async let syncedHabits = self.habitRepository.sync()
        async let syncedCompletions = self.checkInRepository.sync()
        let habits = try await syncedHabits
        let completions = try await syncedCompletions
        await MainActor.run {
            self.habits = habits
            self.completions = completions
        }
        self.widgetSyncService.publish(habits: habits, completions: completions)
    }

    private func refreshLocalState() async {
        do {
            let fetchedHabits = try await self.habitRepository.fetchHabits()
            let fetchedCompletions = try await self.checkInRepository.fetchCompletions()
            await MainActor.run {
                self.habits = fetchedHabits
                self.completions = fetchedCompletions
            }
            self.widgetSyncService.publish(habits: fetchedHabits, completions: fetchedCompletions)
        } catch {
            await MainActor.run {
                self.habits = []
                self.completions = []
            }
        }
    }

    private func determinePhase() async {
        let didCompleteOnboarding = self.defaults.bool(forKey: self.onboardingKey)
        if !didCompleteOnboarding {
            await MainActor.run { self.phase = .onboarding }
        } else if self.currentUser == nil {
            await MainActor.run { self.phase = .authentication }
        } else {
            await MainActor.run { self.phase = .ready }
        }
    }

    private func runBusyTask(_ operation: @escaping @Sendable () async throws -> Void) async {
        await MainActor.run {
            self.errorMessage = nil
            self.isBusy = true
        }
        defer {
            Task { @MainActor in
                self.isBusy = false
            }
        }

        do {
            try await operation()
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
}
