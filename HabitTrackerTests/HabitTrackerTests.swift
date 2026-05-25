import XCTest
@testable import HabitTracker

final class HabitTrackerTests: XCTestCase {
    func testDailyHabitStreakCountsBackwardUntilGap() {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Read",
            emojiOrIcon: "📚",
            color: .teal,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let completions = [
            HabitCompletion(id: UUID(), habitId: habit.id, userId: habit.userId, date: today, count: 1, note: "", createdAt: .now),
            HabitCompletion(id: UUID(), habitId: habit.id, userId: habit.userId, date: yesterday, count: 1, note: "", createdAt: .now)
        ]

        XCTAssertEqual(StreakCalculator.currentStreak(for: habit, completions: completions, referenceDate: today), 2)
    }

    func testWeekdayHabitOnlyAppearsOnConfiguredDays() {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Gym",
            emojiOrIcon: "🏋️",
            color: .rose,
            schedule: .weekdays([.monday, .wednesday, .friday]),
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        let date = Calendar.current.nextDate(after: .now, matching: DateComponents(weekday: Weekday.tuesday.rawValue), matchingPolicy: .nextTime)!
        XCTAssertFalse(habit.isDue(on: date))
    }

    func testSavingHabitSucceedsLocallyWhenRemoteUpsertFails() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: FailingRemoteDataSource(),
                authService: MockAuthService()
            )
        }

        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Walk",
            emojiOrIcon: "🚶",
            color: .teal,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        try await repository.saveHabit(habit)

        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits, [habit])
    }

    func testSyncKeepsLocalHabitWhenRemoteDoesNotReturnIt() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let remote = EventuallyConsistentRemoteDataSource()
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: remote,
                authService: MockAuthService()
            )
        }

        let localOnlyHabit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Journal",
            emojiOrIcon: "📝",
            color: .moss,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        try await repository.saveHabit(localOnlyHabit)
        let syncedHabits = try await repository.sync()

        XCTAssertEqual(syncedHabits, [localOnlyHabit])
        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits, [localOnlyHabit])
    }

    func testArchivingOneHabitDoesNotArchiveOthersWithMatchingCreationTime() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: FailingRemoteDataSource(),
                authService: MockAuthService()
            )
        }

        let createdAt = Date(timeIntervalSince1970: 1_717_171_717)
        let userId = UUID()
        let firstHabit = Habit(
            id: UUID(),
            userId: userId,
            name: "Read",
            emojiOrIcon: "📚",
            color: .teal,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: createdAt,
            archivedAt: nil
        )
        let secondHabit = Habit(
            id: UUID(),
            userId: userId,
            name: "Walk",
            emojiOrIcon: "🚶",
            color: .moss,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: createdAt,
            archivedAt: nil
        )

        try await repository.saveHabit(firstHabit)
        try await repository.saveHabit(secondHabit)
        try await repository.archiveHabit(firstHabit)

        let savedHabits = try await repository.fetchHabits().sorted { $0.name < $1.name }
        XCTAssertEqual(savedHabits.count, 2)
        XCTAssertNotNil(savedHabits.first(where: { $0.id == firstHabit.id })?.archivedAt)
        XCTAssertNil(savedHabits.first(where: { $0.id == secondHabit.id })?.archivedAt)
    }

    func testDeletingOneHabitDoesNotDeleteOthers() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: FailingRemoteDataSource(),
                authService: MockAuthService()
            )
        }

        let userId = UUID()
        let firstHabit = Habit(
            id: UUID(),
            userId: userId,
            name: "Stretch",
            emojiOrIcon: "🧘",
            color: .rose,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )
        let secondHabit = Habit(
            id: UUID(),
            userId: userId,
            name: "Hydrate",
            emojiOrIcon: "💧",
            color: .teal,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now.addingTimeInterval(1),
            archivedAt: nil
        )

        try await repository.saveHabit(firstHabit)
        try await repository.saveHabit(secondHabit)
        try await repository.deleteHabit(firstHabit)

        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits, [secondHabit])
    }

    func testSavingUpdatedHabitDoesNotChangeOthersWithMatchingCreationTime() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: FailingRemoteDataSource(),
                authService: MockAuthService()
            )
        }

        let createdAt = Date(timeIntervalSince1970: 1_717_171_717)
        let userId = UUID()
        let firstHabit = Habit(
            id: UUID(),
            userId: userId,
            name: "Read",
            emojiOrIcon: "📚",
            color: .teal,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: createdAt,
            archivedAt: nil
        )
        let secondHabit = Habit(
            id: UUID(),
            userId: userId,
            name: "Walk",
            emojiOrIcon: "🚶",
            color: .moss,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: createdAt,
            archivedAt: nil
        )
        var updatedFirstHabit = firstHabit
        updatedFirstHabit.name = "Deep Read"

        try await repository.saveHabit(firstHabit)
        try await repository.saveHabit(secondHabit)
        try await repository.saveHabit(updatedFirstHabit)

        let savedHabits = try await repository.fetchHabits().sorted { $0.name < $1.name }
        XCTAssertEqual(savedHabits.count, 2)
        XCTAssertEqual(savedHabits.first(where: { $0.id == firstHabit.id })?.name, "Deep Read")
        XCTAssertEqual(savedHabits.first(where: { $0.id == secondHabit.id })?.name, "Walk")
    }

    func testRecordingCompletionReplacesDuplicateEntriesForSameHabitDay() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultCheckInRepository(
                localStore: localStore,
                remote: FailingRemoteDataSource(),
                authService: MockAuthService()
            )
        }

        let userId = UUID()
        let habitId = UUID()
        let day = Calendar.current.startOfDay(for: .now)
        let stale = HabitCompletion(
            id: UUID(),
            habitId: habitId,
            userId: userId,
            date: day,
            count: 1,
            note: "",
            createdAt: day
        )
        let newer = HabitCompletion(
            id: UUID(),
            habitId: habitId,
            userId: userId,
            date: day.addingTimeInterval(60),
            count: 0,
            note: "",
            createdAt: day.addingTimeInterval(60)
        )
        try await localStore.writeCompletions([stale, newer])

        let replacement = HabitCompletion(
            id: newer.id,
            habitId: habitId,
            userId: userId,
            date: day,
            count: 0,
            note: "",
            createdAt: newer.createdAt
        )
        try await repository.recordCompletion(replacement)

        let completions = try await repository.fetchCompletions()
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.count, 0)
    }

    func testSyncPrefersLatestCompletionWhenLocalAndRemoteDisagreeForSameHabitDay() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let remote = DuplicateCompletionRemoteDataSource()
        let repository = await MainActor.run {
            DefaultCheckInRepository(
                localStore: localStore,
                remote: remote,
                authService: MockAuthService()
            )
        }

        let userId = UUID()
        let habitId = UUID()
        let day = Calendar.current.startOfDay(for: .now)
        let remoteCompletion = HabitCompletion(
            id: UUID(),
            habitId: habitId,
            userId: userId,
            date: day,
            count: 1,
            note: "",
            createdAt: day
        )
        let localCompletion = HabitCompletion(
            id: UUID(),
            habitId: habitId,
            userId: userId,
            date: day.addingTimeInterval(60),
            count: 0,
            note: "",
            createdAt: day.addingTimeInterval(60)
        )

        try await localStore.writeCompletions([localCompletion])
        await remote.setCompletions([remoteCompletion])

        let synced = try await repository.sync()
        XCTAssertEqual(synced.count, 1)
        XCTAssertEqual(synced.first?.count, 0)
    }

    @MainActor
    func testRecordCompletionOnlyChangesTappedHabit() async {
        let habitRepository = StubHabitRepository()
        let checkInRepository = StubCheckInRepository()
        let environment = AppEnvironment(
            authService: SupabaseAuthService(),
            purchaseService: PurchaseService(),
            reminderService: NoopReminderService(),
            widgetSyncService: WidgetSyncService(),
            analyticsService: AnalyticsService(),
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            habitRepository: habitRepository,
            checkInRepository: checkInRepository
        )

        let user = AppUser(id: UUID(), email: "test@example.com")
        let coding = Habit(
            id: UUID(),
            userId: user.id,
            name: "Coding",
            emojiOrIcon: "💻",
            color: .slate,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )
        let reading = Habit(
            id: UUID(),
            userId: user.id,
            name: "Reading",
            emojiOrIcon: "📚",
            color: .moss,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now.addingTimeInterval(1),
            archivedAt: nil
        )

        environment.currentUser = user
        environment.habits = [coding, reading]

        await environment.recordCompletion(for: coding, count: 1, date: .now)

        XCTAssertEqual(environment.completion(for: coding, on: .now)?.count, 1)
        XCTAssertNil(environment.completion(for: reading, on: .now))
    }

    @MainActor
    func testRecordCompletionTogglesOnThenOffForSameHabitDay() async {
        let habitRepository = StubHabitRepository()
        let checkInRepository = StubCheckInRepository()
        let environment = AppEnvironment(
            authService: SupabaseAuthService(),
            purchaseService: PurchaseService(),
            reminderService: NoopReminderService(),
            widgetSyncService: WidgetSyncService(),
            analyticsService: AnalyticsService(),
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            habitRepository: habitRepository,
            checkInRepository: checkInRepository
        )

        let user = AppUser(id: UUID(), email: "test@example.com")
        let coding = Habit(
            id: UUID(),
            userId: user.id,
            name: "Coding",
            emojiOrIcon: "💻",
            color: .slate,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        environment.currentUser = user
        environment.habits = [coding]

        await environment.recordCompletion(for: coding, count: 1, date: .now)
        XCTAssertEqual(environment.completion(for: coding, on: .now)?.count, 1)

        await environment.recordCompletion(for: coding, count: 0, date: .now)
        XCTAssertEqual(environment.completion(for: coding, on: .now)?.count, 0)
        XCTAssertEqual(environment.completionHistory(for: coding).count, 1)
    }

    @MainActor
    func testRecordCompletionDoesNotSnapBackWhenRepositoryFetchIsStale() async {
        let habitRepository = StubHabitRepository()
        let checkInRepository = StaleFetchCheckInRepository()
        let environment = AppEnvironment(
            authService: SupabaseAuthService(),
            purchaseService: PurchaseService(),
            reminderService: NoopReminderService(),
            widgetSyncService: WidgetSyncService(),
            analyticsService: AnalyticsService(),
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            habitRepository: habitRepository,
            checkInRepository: checkInRepository
        )

        let user = AppUser(id: UUID(), email: "test@example.com")
        let habit = Habit(
            id: UUID(),
            userId: user.id,
            name: "Stretch",
            emojiOrIcon: "🧘",
            color: .rose,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        environment.currentUser = user
        environment.habits = [habit]

        await environment.recordCompletion(for: habit, count: 1, date: .now)

        XCTAssertEqual(environment.completion(for: habit, on: .now)?.count, 1)
        XCTAssertEqual(environment.completionHistory(for: habit).count, 1)
    }
}

private struct FailingRemoteDataSource: HabitRemoteDataSource {
    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }
    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        throw AppError.network("Remote unavailable")
    }
    func deleteHabit(_ habit: Habit, authHeader: String?) async throws {
        throw AppError.network("Remote unavailable")
    }
    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {
        throw AppError.network("Remote unavailable")
    }
    func deleteCompletions(for habit: Habit, authHeader: String?) async throws {
        throw AppError.network("Remote unavailable")
    }
}

private actor EventuallyConsistentRemoteDataSource: HabitRemoteDataSource {
    private var fetchedHabits: [Habit] = []

    func fetchHabits(authHeader: String?) async throws -> [Habit] {
        fetchedHabits
    }

    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        // Simulate a lagging remote read replica: writes succeed, but the next read
        // does not necessarily include the record yet.
    }

    func deleteHabit(_ habit: Habit, authHeader: String?) async throws {}

    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}
    func deleteCompletions(for habit: Habit, authHeader: String?) async throws {}
}

private actor DuplicateCompletionRemoteDataSource: HabitRemoteDataSource {
    private var completions: [HabitCompletion] = []

    func setCompletions(_ completions: [HabitCompletion]) {
        self.completions = completions
    }

    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }
    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {}
    func deleteHabit(_ habit: Habit, authHeader: String?) async throws {}
    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { completions }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}
    func deleteCompletions(for habit: Habit, authHeader: String?) async throws {}
}

private actor StubHabitRepository: HabitRepository {
    private var habits: [Habit] = []

    func fetchHabits() async throws -> [Habit] { habits }
    func saveHabit(_ habit: Habit) async throws {
        if let index = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[index] = habit
        } else {
            habits.append(habit)
        }
    }
    func archiveHabit(_ habit: Habit) async throws {}
    func deleteHabit(_ habit: Habit) async throws {}
    func sync() async throws -> [Habit] { habits }
}

private actor StubCheckInRepository: CheckInRepository {
    private var completions: [HabitCompletion] = []

    func fetchCompletions() async throws -> [HabitCompletion] { completions }
    func recordCompletion(_ completion: HabitCompletion) async throws {
        completions.removeAll {
            $0.habitId == completion.habitId && Calendar.current.isDate($0.date, inSameDayAs: completion.date)
        }
        completions.append(completion)
    }
    func deleteCompletions(for habit: Habit) async throws {
        completions.removeAll { $0.habitId == habit.id }
    }
    func sync() async throws -> [HabitCompletion] { completions }
}

private actor StaleFetchCheckInRepository: CheckInRepository {
    private var completions: [HabitCompletion] = []

    func fetchCompletions() async throws -> [HabitCompletion] { [] }

    func recordCompletion(_ completion: HabitCompletion) async throws {
        completions.removeAll {
            $0.habitId == completion.habitId && Calendar.current.isDate($0.date, inSameDayAs: completion.date)
        }
        completions.append(completion)
    }

    func deleteCompletions(for habit: Habit) async throws {
        completions.removeAll { $0.habitId == habit.id }
    }

    func sync() async throws -> [HabitCompletion] { completions }
}

private struct NoopReminderService: ReminderService {
    func requestAuthorization() async throws -> Bool { true }
    func rescheduleNotifications(for habits: [Habit]) async throws {}
}

@MainActor
private final class MockAuthService: AuthService {
    var currentUser: AppUser?

    func restoreSession() async throws -> AppUser? { currentUser }
    func signIn(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signUp(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signOut() async throws {}
    func authorizationHeader() -> String? { nil }
}
