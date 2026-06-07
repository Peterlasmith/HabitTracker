import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    enum Phase: Equatable {
        case launching
        case onboarding
        case authentication
        case accountDeleted
        case ready
    }

    enum HabitSaveOutcome: Equatable {
        case savedLocally
        case syncPending
    }

    @Published var phase: Phase = .launching
    @Published var currentUser: AppUser?
    @Published var habits: [Habit] = []
    @Published var completions: [HabitCompletion] = []
    @Published var bucketItems: [BucketItem] = []
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var recentlyDeletedAccountEmail: String?
    @Published private(set) var hasPendingHabitSync = false
    @Published private(set) var hasPendingBucketSync = false

    let authService: SupabaseAuthService
    let habitRepository: HabitRepository
    let checkInRepository: CheckInRepository
    let bucketRepository: BucketListRepository
    let reminderService: ReminderService
    let widgetSyncService: WidgetSyncService
    let analyticsService: AnalyticsService

    private let defaults: UserDefaults
    private let localStore: LocalStore
    private let onboardingKey = "hasCompletedOnboarding"
    private var habitSyncTask: Task<Void, Never>?
    private var bucketSyncTask: Task<Void, Never>?
    private static let pendingRemoteSyncMessage = "Saved on this device. We'll sync when you're back online."

    // All properties are initialized on the main actor due to the enclosing class annotation.
    init(
        authService: SupabaseAuthService,
        reminderService: ReminderService,
        widgetSyncService: WidgetSyncService,
        analyticsService: AnalyticsService,
        defaults: UserDefaults,
        localStore: LocalStore? = nil,
        habitRepository: HabitRepository? = nil,
        checkInRepository: CheckInRepository? = nil,
        bucketRepository: BucketListRepository? = nil
    ) {
        self.authService = authService
        self.reminderService = reminderService
        self.widgetSyncService = widgetSyncService
        self.analyticsService = analyticsService
        self.defaults = defaults
        self.localStore = localStore ?? LocalStore()

        let remote = SupabaseHabitRemoteDataSource()
        let bucketRemote = SupabaseBucketListRemoteDataSource()
        if let habitRepository { self.habitRepository = habitRepository } else { self.habitRepository = DefaultHabitRepository(localStore: self.localStore, remote: remote, authService: authService) }
        if let checkInRepository { self.checkInRepository = checkInRepository } else { self.checkInRepository = DefaultCheckInRepository(localStore: self.localStore, remote: remote, authService: authService) }
        if let bucketRepository { self.bucketRepository = bucketRepository } else { self.bucketRepository = DefaultBucketListRepository(localStore: self.localStore, remote: bucketRemote, authService: authService) }
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

        if self.currentUser != nil {
            await self.refreshLocalState()
            try? await self.syncAll()
        } else {
            await self.clearPersistedUserState()
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
            await self.clearPersistedUserState()
            await self.determinePhase()
        }
    }

    func deleteAccount(currentPassword: String) async -> Bool {
        let deletedEmail = self.currentUser?.email

        let result: Bool? = await self.runBusyTask {
            try await self.authService.deleteAccount(currentPassword: currentPassword)
            await self.clearPersistedUserState()
            await MainActor.run {
                self.recentlyDeletedAccountEmail = deletedEmail
                self.phase = .accountDeleted
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                self.recentlyDeletedAccountEmail = nil
                await self.determinePhase()
            }
            return true
        }

        return result ?? false
    }

    func createOrUpdateHabit(_ habit: Habit) async throws -> HabitSaveOutcome {
        let previousHabits = self.habits
        let updatedHabits = self.upsertHabit(habit, in: previousHabits)

        self.errorMessage = nil
        self.habits = updatedHabits
        do {
            try await self.localStore.writeHabits(updatedHabits)
            try await self.reminderService.rescheduleNotifications(for: updatedHabits)
            self.widgetSyncService.publish(habits: updatedHabits, completions: self.completions)
        } catch {
            await self.rollbackHabits(to: previousHabits)
            throw error
        }

        self.analyticsService.track(.createdHabit)
        return self.queueHabitSync(for: habit)
    }

    func retryPendingHabitSyncIfNeeded() {
        guard self.currentUser != nil,
              self.hasPendingHabitSync,
              self.habitSyncTask == nil
        else { return }

        self.startPendingHabitSyncTask()
    }

    func retryPendingBucketSyncIfNeeded() {
        guard self.currentUser != nil,
              self.hasPendingBucketSync,
              self.bucketSyncTask == nil
        else { return }

        self.startPendingBucketSyncTask()
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

    func deleteHabit(_ habit: Habit) async {
        let previousHabits = self.habits
        let previousCompletions = self.completions
        let updatedHabits = previousHabits.filter { $0.id != habit.id }
        let updatedCompletions = previousCompletions.filter { $0.habitId != habit.id }

        self.habits = updatedHabits
        self.completions = updatedCompletions
        do {
            try await self.localStore.writeHabits(updatedHabits)
            try await self.localStore.writeCompletions(updatedCompletions)
        } catch {
            self.habits = previousHabits
            self.completions = previousCompletions
            try? await self.localStore.writeHabits(previousHabits)
            try? await self.localStore.writeCompletions(previousCompletions)
            self.errorMessage = error.localizedDescription
            return
        }

        let updatedHabitsCopy = updatedHabits
        let updatedCompletionsCopy = updatedCompletions
        let habitCopy = habit
        let didDelete = await self.runBusyTask { [updatedHabitsCopy, updatedCompletionsCopy, habitCopy] in
            try await self.habitRepository.deleteHabit(habitCopy)
            try await self.reminderService.rescheduleNotifications(for: updatedHabitsCopy)
            self.widgetSyncService.publish(habits: updatedHabitsCopy, completions: updatedCompletionsCopy)
            return true
        } ?? false

        guard didDelete else {
            await self.rollbackState(habits: previousHabits, completions: previousCompletions)
            return
        }
    }

    func createBucketItem(title: String, category: BucketCategory) async throws -> HabitSaveOutcome {
        guard let user = self.currentUser else {
            throw AppError.network("Your session expired. Sign in again to keep going.")
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw AppError.configuration("Bucket list items need a title.")
        }

        let now = Date()
        let item = BucketItem(
            id: UUID(),
            userId: user.id,
            title: trimmedTitle,
            category: category,
            completedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        let outcome = try await self.saveBucketItem(item)
        self.analyticsService.track(.createdBucketItem)
        return outcome
    }

    func updateBucketItem(_ item: BucketItem) async throws -> HabitSaveOutcome {
        let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw AppError.configuration("Bucket list items need a title.")
        }

        var updatedItem = item
        updatedItem.title = trimmedTitle
        updatedItem.updatedAt = .now
        return try await self.saveBucketItem(updatedItem)
    }

    func toggleBucketItemCompletion(_ item: BucketItem, achievedDate: Date?) async throws -> HabitSaveOutcome {
        var updatedItem = item
        updatedItem.completedAt = item.completedAt == nil ? achievedDate : nil
        updatedItem.updatedAt = .now
        let outcome = try await self.saveBucketItem(updatedItem)
        if updatedItem.completedAt != nil {
            self.analyticsService.track(.completedBucketItem)
        }
        return outcome
    }

    func deleteBucketItem(_ item: BucketItem) async {
        let previousItems = self.bucketItems
        let updatedItems = previousItems.filter { $0.id != item.id }

        self.bucketItems = updatedItems
        do {
            try await self.localStore.writeBucketItems(updatedItems)
        } catch {
            self.bucketItems = previousItems
            try? await self.localStore.writeBucketItems(previousItems)
            self.errorMessage = error.localizedDescription
            return
        }

        let updatedItemsCopy = updatedItems
        let itemCopy = item
        let didDelete = await self.runBusyTask { [updatedItemsCopy, itemCopy] in
            try await self.bucketRepository.deleteBucketItem(itemCopy)
            await MainActor.run {
                self.bucketItems = updatedItemsCopy
            }
            return true
        } ?? false

        guard didDelete else {
            await self.rollbackBucketItems(to: previousItems)
            return
        }
    }

    func recordCompletion(for habit: Habit, count: Int, note: String = "", date: Date = .now) async {
        guard let user = self.currentUser else { return }

        let startOfDay = Calendar.current.startOfDay(for: date)
        let existing = self.completion(for: habit, on: startOfDay)
        let normalizedCount = normalizedCheckCount(count)
        let completion = HabitCompletion(
            id: existing?.id ?? UUID(),
            habitId: habit.id,
            userId: user.id,
            date: startOfDay,
            count: normalizedCount,
            note: note,
            createdAt: existing?.createdAt ?? .now
        )
        let previousCompletions = self.completions
        let optimisticCompletions = upsertCompletion(completion, in: previousCompletions)

        self.completions = optimisticCompletions
        self.widgetSyncService.publish(habits: self.habits, completions: optimisticCompletions)
        do {
            try await self.localStore.writeCompletions(optimisticCompletions)
        } catch {
            self.completions = previousCompletions
            self.widgetSyncService.publish(habits: self.habits, completions: previousCompletions)
            self.errorMessage = error.localizedDescription
            return
        }

        let didRecord = await self.runBusyTask {
            try await self.checkInRepository.recordCompletion(completion)
            self.analyticsService.track(.completedHabit)
            return true
        } ?? false

        guard didRecord else {
            await self.rollbackCompletions(to: previousCompletions)
            return
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

    @MainActor
    func habit(id: UUID) -> Habit? {
        self.habits.first { $0.id == id }
    }

    private func syncAll() async throws {
        async let syncedHabits = self.habitRepository.sync()
        async let syncedCompletions = self.checkInRepository.sync()
        async let syncedBucketItems = self.bucketRepository.sync()
        let habits = try await syncedHabits
        let completions = try await syncedCompletions
        let bucketItems = try await syncedBucketItems
        let habitIDs = Set(habits.map(\.id))
        let filteredCompletions = self.normalizedCompletions(completions).filter { habitIDs.contains($0.habitId) }
        await MainActor.run {
            self.habits = habits
            self.completions = filteredCompletions
            self.bucketItems = sortedBucketItems(bucketItems)
            self.hasPendingHabitSync = false
            self.hasPendingBucketSync = false
            self.clearPendingRemoteSyncMessageIfNeeded()
        }
        try? await self.localStore.writeCompletions(filteredCompletions)
        try? await self.localStore.writeBucketItems(bucketItems)
        self.widgetSyncService.publish(habits: habits, completions: filteredCompletions)
    }

    private func clearPersistedUserState() async {
        self.habitSyncTask?.cancel()
        self.habitSyncTask = nil
        self.bucketSyncTask?.cancel()
        self.bucketSyncTask = nil
        self.hasPendingHabitSync = false
        self.hasPendingBucketSync = false
        self.clearPendingRemoteSyncMessageIfNeeded()
        await self.reminderService.clearAllNotifications()
        try? await self.localStore.clearAll()
        self.widgetSyncService.clearPublishedData()
        await MainActor.run {
            self.currentUser = nil
            self.habits = []
            self.completions = []
            self.bucketItems = []
        }
    }

    private func refreshLocalState() async {
        do {
            let fetchedHabits = try await self.habitRepository.fetchHabits()
            let fetchedCompletions = try await self.checkInRepository.fetchCompletions()
            let fetchedBucketItems = try await self.bucketRepository.fetchBucketItems()
            await MainActor.run {
                self.habits = fetchedHabits
                self.completions = self.normalizedCompletions(fetchedCompletions)
                self.bucketItems = sortedBucketItems(fetchedBucketItems)
            }
            self.widgetSyncService.publish(habits: fetchedHabits, completions: self.normalizedCompletions(fetchedCompletions))
        } catch {
            await MainActor.run {
                self.habits = []
                self.completions = []
                self.bucketItems = []
            }
        }
    }

    private func syncReminders() async {
        try? await self.reminderService.rescheduleNotifications(for: self.habits)
    }

    private func queueHabitSync(for habit: Habit) -> HabitSaveOutcome {
        if self.habitSyncTask != nil {
            self.hasPendingHabitSync = true
            return .syncPending
        }

        if self.hasPendingHabitSync {
            self.startPendingHabitSyncTask()
            return .syncPending
        }

        self.startHabitSaveTask(for: habit)
        return .savedLocally
    }

    private func saveBucketItem(_ item: BucketItem) async throws -> HabitSaveOutcome {
        let previousItems = self.bucketItems
        let updatedItems = self.upsertBucketItem(item, in: previousItems)

        self.errorMessage = nil
        self.bucketItems = updatedItems
        do {
            try await self.localStore.writeBucketItems(updatedItems)
        } catch {
            await self.rollbackBucketItems(to: previousItems)
            throw error
        }

        return self.queueBucketSync(for: item)
    }

    private func startHabitSaveTask(for habit: Habit) {
        let habitCopy = habit
        self.habitSyncTask = Task { @MainActor in
            await self.finishHabitSaveTask(for: habitCopy)
        }
    }

    private func finishHabitSaveTask(for habit: Habit) async {
        do {
            try await self.habitRepository.saveHabit(habit)
        } catch {
            self.hasPendingHabitSync = true
            self.errorMessage = Self.pendingRemoteSyncMessage
            self.habitSyncTask = nil
            return
        }

        let shouldFlushPendingSync = self.hasPendingHabitSync
        self.habitSyncTask = nil

        if shouldFlushPendingSync {
            self.startPendingHabitSyncTask()
        }
    }

    private func startPendingHabitSyncTask() {
        guard self.habitSyncTask == nil else { return }

        self.habitSyncTask = Task { @MainActor in
            await self.finishPendingHabitSyncTask()
        }
    }

    private func finishPendingHabitSyncTask() async {
        do {
            try await self.syncAll()
            self.hasPendingHabitSync = false
            self.clearPendingRemoteSyncMessageIfNeeded()
        } catch {
            self.hasPendingHabitSync = true
            self.errorMessage = Self.pendingRemoteSyncMessage
        }

        self.habitSyncTask = nil
    }

    private func queueBucketSync(for item: BucketItem) -> HabitSaveOutcome {
        if self.bucketSyncTask != nil {
            self.hasPendingBucketSync = true
            return .syncPending
        }

        if self.hasPendingBucketSync {
            self.startPendingBucketSyncTask()
            return .syncPending
        }

        self.startBucketSaveTask(for: item)
        return .savedLocally
    }

    private func startBucketSaveTask(for item: BucketItem) {
        let itemCopy = item
        self.bucketSyncTask = Task { @MainActor in
            await self.finishBucketSaveTask(for: itemCopy)
        }
    }

    private func finishBucketSaveTask(for item: BucketItem) async {
        do {
            try await self.bucketRepository.saveBucketItem(item)
        } catch {
            self.hasPendingBucketSync = true
            self.errorMessage = Self.pendingRemoteSyncMessage
            self.bucketSyncTask = nil
            return
        }

        let shouldFlushPendingSync = self.hasPendingBucketSync
        self.bucketSyncTask = nil

        if shouldFlushPendingSync {
            self.startPendingBucketSyncTask()
        }
    }

    private func startPendingBucketSyncTask() {
        guard self.bucketSyncTask == nil else { return }

        self.bucketSyncTask = Task { @MainActor in
            await self.finishPendingBucketSyncTask()
        }
    }

    private func finishPendingBucketSyncTask() async {
        do {
            try await self.syncAll()
            self.hasPendingBucketSync = false
            self.clearPendingRemoteSyncMessageIfNeeded()
        } catch {
            self.hasPendingBucketSync = true
            self.errorMessage = Self.pendingRemoteSyncMessage
        }

        self.bucketSyncTask = nil
    }

    private func rollbackHabits(to previousHabits: [Habit]) async {
        self.habits = previousHabits
        try? await self.localStore.writeHabits(previousHabits)
        try? await self.reminderService.rescheduleNotifications(for: previousHabits)
        self.widgetSyncService.publish(habits: previousHabits, completions: self.completions)
    }

    private func rollbackBucketItems(to previousItems: [BucketItem]) async {
        self.bucketItems = previousItems
        try? await self.localStore.writeBucketItems(previousItems)
    }

    private func clearPendingRemoteSyncMessageIfNeeded() {
        if !self.hasPendingHabitSync,
           !self.hasPendingBucketSync,
           self.errorMessage == Self.pendingRemoteSyncMessage {
            self.errorMessage = nil
        }
    }

    private func rollbackCompletions(to previousCompletions: [HabitCompletion]) async {
        self.completions = previousCompletions
        try? await self.localStore.writeCompletions(previousCompletions)
        self.widgetSyncService.publish(habits: self.habits, completions: previousCompletions)
    }

    private func rollbackState(habits previousHabits: [Habit], completions previousCompletions: [HabitCompletion]) async {
        self.habits = previousHabits
        self.completions = previousCompletions
        try? await self.localStore.writeHabits(previousHabits)
        try? await self.localStore.writeCompletions(previousCompletions)
        try? await self.reminderService.rescheduleNotifications(for: previousHabits)
        self.widgetSyncService.publish(habits: previousHabits, completions: previousCompletions)
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

    private func upsertBucketItem(_ item: BucketItem, in items: [BucketItem]) -> [BucketItem] {
        var updatedItems = items
        if let index = updatedItems.firstIndex(where: { $0.id == item.id }) {
            updatedItems[index] = item
        } else {
            updatedItems.append(item)
        }
        return sortedBucketItems(updatedItems)
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
            var normalizedCompletion = completion
            normalizedCompletion.count = normalizedCheckCount(completion.count)
            if let existing = result[key] {
                result[key] = preferredCompletion(between: existing, and: normalizedCompletion)
            } else {
                result[key] = normalizedCompletion
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
