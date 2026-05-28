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
    let widgetSyncService: WidgetSyncService
    let analyticsService: AnalyticsService

    private let defaults: UserDefaults
    private let onboardingKey = "hasCompletedOnboarding"

    // All properties are initialized on the main actor due to the enclosing class annotation.
    init(
        authService: SupabaseAuthService,
        reminderService: ReminderService,
        widgetSyncService: WidgetSyncService,
        analyticsService: AnalyticsService,
        defaults: UserDefaults,
        habitRepository: HabitRepository? = nil,
        checkInRepository: CheckInRepository? = nil
    ) {
        self.authService = authService
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
        await self.syncReminders()
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
            await self.syncReminders()
            await self.determinePhase()
        }
    }

    func signUp(email: String, password: String) async {
        await self.runBusyTask {
            let user = try await self.authService.signUp(email: email, password: password)
            await MainActor.run { self.currentUser = user }
            self.analyticsService.track(.createdAccount)
            try await self.syncAll()
            await self.syncReminders()
            await self.determinePhase()
        }
    }

    func signOut() async {
        await self.runBusyTask {
            try await self.authService.signOut()
            await self.reminderService.clearAllNotifications()
            await MainActor.run {
                self.currentUser = nil
                self.habits = []
                self.completions = []
            }
            await self.determinePhase()
        }
    }

    func createOrUpdateHabit(_ habit: Habit) async -> Bool {
        let previousHabits = self.habits
        let updatedHabits = self.upsertHabit(habit, in: previousHabits)

        self.habits = updatedHabits

        let habitCopy = habit
        let updatedHabitsCopy = updatedHabits
        return await self.runBusyTask { [habitCopy, updatedHabitsCopy] in
            try await self.habitRepository.saveHabit(habitCopy)
            try await self.reminderService.rescheduleNotifications(for: updatedHabitsCopy)
            await self.widgetSyncService.publish(habits: updatedHabitsCopy, completions: self.completions)
            self.analyticsService.track(.createdHabit)
            return true
        } ?? { [previousHabits] in
            self.habits = previousHabits
            return false
        }()
    }

    func enableReminderPermissions() async {
        await self.runBusyTask {
            let isAuthorized = try await self.reminderService.requestAuthorization()
            guard isAuthorized else {
                throw AppError.configuration("Notifications are disabled for HabitClaw. Enable them in iPhone Settings to receive reminders.")
            }
            await self.syncReminders()
        }
    }

    func archiveHabit(_ habit: Habit) async {
        let previousHabits = self.habits
        var archivedHabit = habit
        archivedHabit.archivedAt = .now
        let updatedHabits = self.upsertHabit(archivedHabit, in: previousHabits)

        self.habits = updatedHabits

        let updatedHabitsCopy = updatedHabits
        let archivedHabitCopy = archivedHabit
        await self.runBusyTask { [updatedHabitsCopy, archivedHabitCopy] in
            try await self.habitRepository.archiveHabit(archivedHabitCopy)
            try await self.reminderService.rescheduleNotifications(for: updatedHabitsCopy)
            await self.widgetSyncService.publish(habits: updatedHabitsCopy, completions: self.completions)
        } ?? { [previousHabits] in
            self.habits = previousHabits
        }()
    }

    func restoreHabit(_ habit: Habit) async {
        let previousHabits = self.habits
        var restoredHabit = habit
        restoredHabit.archivedAt = nil
        let updatedHabits = self.upsertHabit(restoredHabit, in: previousHabits)

        self.habits = updatedHabits

        let updatedHabitsCopy = updatedHabits
        let restoredHabitCopy = restoredHabit
        await self.runBusyTask { [restoredHabitCopy, updatedHabitsCopy] in
            try await self.habitRepository.saveHabit(restoredHabitCopy)
            try await self.reminderService.rescheduleNotifications(for: updatedHabitsCopy)
            await self.widgetSyncService.publish(habits: updatedHabitsCopy, completions: self.completions)
        } ?? { [previousHabits] in
            self.habits = previousHabits
        }()
    }

    func recordCompletion(for habit: Habit, count: Int, note: String = "", date: Date = .now) async {
        guard let user = self.currentUser else { return }

        let startOfDay = Calendar.current.startOfDay(for: date)
        let existing = self.completion(for: habit, on: startOfDay)
        let completion = HabitCompletion(
            id: existing?.id ?? UUID(),
            habitId: habit.id,
            userId: user.id,
            date: startOfDay,
            count: count,
            note: note,
            createdAt: existing?.createdAt ?? .now
        )
        let previousCompletions = self.completions
        let optimisticCompletions = upsertCompletion(completion, in: previousCompletions)

        self.completions = optimisticCompletions
        self.widgetSyncService.publish(habits: self.habits, completions: optimisticCompletions)

        await self.runBusyTask {
            try await self.checkInRepository.recordCompletion(completion)
            self.analyticsService.track(.completedHabit)
        } ?? { [previousCompletions] in
            self.completions = previousCompletions
            self.widgetSyncService.publish(habits: self.habits, completions: previousCompletions)
        }()
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
                    completion: latestCompletion(for: habit.id, on: date, from: todayCompletions)
                )
            }
    }

    @MainActor
    func completionHistory(for habit: Habit) -> [HabitCompletion] {
        deduplicatedCompletions(for: habit.id, from: self.completions)
    }

    @MainActor
    func completion(for habit: Habit, on date: Date) -> HabitCompletion? {
        latestCompletion(for: habit.id, on: date, from: self.completions)
    }

    private func syncAll() async throws {
        async let syncedHabits = self.habitRepository.sync()
        async let syncedCompletions = self.checkInRepository.sync()
        let habits = try await syncedHabits
        let completions = try await syncedCompletions
        await MainActor.run {
            self.habits = habits
            self.completions = self.normalizedCompletions(completions)
        }
        self.widgetSyncService.publish(habits: habits, completions: self.normalizedCompletions(completions))
    }

    private func refreshLocalState() async {
        do {
            let fetchedHabits = try await self.habitRepository.fetchHabits()
            let fetchedCompletions = try await self.checkInRepository.fetchCompletions()
            await MainActor.run {
                self.habits = fetchedHabits
                self.completions = self.normalizedCompletions(fetchedCompletions)
            }
            self.widgetSyncService.publish(habits: fetchedHabits, completions: self.normalizedCompletions(fetchedCompletions))
        } catch {
            await MainActor.run {
                self.habits = []
                self.completions = []
            }
        }
    }

    private func syncReminders() async {
        try? await self.reminderService.rescheduleNotifications(for: self.habits)
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

    private func upsertHabit(_ habit: Habit, in habits: [Habit]) -> [Habit] {
        var updatedHabits = habits
        if let index = updatedHabits.firstIndex(where: { $0.id == habit.id }) {
            updatedHabits[index] = habit
        } else {
            updatedHabits.append(habit)
        }
        return updatedHabits.sorted { $0.createdAt < $1.createdAt }
    }

    private func upsertCompletion(_ completion: HabitCompletion, in completions: [HabitCompletion]) -> [HabitCompletion] {
        var updated = normalizedCompletions(completions).filter {
            !($0.habitId == completion.habitId && Calendar.current.isDate($0.date, inSameDayAs: completion.date))
        }
        updated.append(completion)
        return normalizedCompletions(updated)
    }

    @discardableResult
    private func runBusyTask<T>(_ operation: @escaping @Sendable () async throws -> T) async -> T? {
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
            return try await operation()
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
            return nil
        }
    }

    @MainActor
    private func deduplicatedCompletions(for habitId: UUID, from completions: [HabitCompletion]) -> [HabitCompletion] {
        normalizedCompletions(completions)
            .filter { $0.habitId == habitId }
    }

    @MainActor
    private func latestCompletion(for habitId: UUID, on date: Date, from completions: [HabitCompletion]) -> HabitCompletion? {
        let calendar = Calendar.current
        return normalizedCompletions(completions)
            .filter { $0.habitId == habitId && calendar.isDate($0.date, inSameDayAs: date) }
            .max { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private nonisolated func normalizedCompletions(_ completions: [HabitCompletion]) -> [HabitCompletion] {
        let calendar = Calendar.current
        let grouped = completions.reduce(into: [String: HabitCompletion]()) { result, completion in
            let day = calendar.startOfDay(for: completion.date)
            let key = "\(completion.habitId.uuidString)-\(day.timeIntervalSinceReferenceDate)"
            if let existing = result[key] {
                result[key] = preferredCompletion(between: existing, and: completion)
            } else {
                result[key] = completion
            }
        }

        return grouped.values.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.date > rhs.date
        }
    }

    private nonisolated func preferredCompletion(between lhs: HabitCompletion, and rhs: HabitCompletion) -> HabitCompletion {
        if lhs.createdAt == rhs.createdAt {
            return rhs
        }
        return lhs.createdAt > rhs.createdAt ? lhs : rhs
    }
}
