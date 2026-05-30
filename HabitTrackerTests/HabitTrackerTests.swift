import XCTest
@testable import HabitTracker

final class HabitTrackerTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

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

    func testLegacyCountHabitNormalizesToBinary() {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Workout",
            emojiOrIcon: "🏃",
            color: .rose,
            schedule: .weekdays([.monday, .wednesday, .friday]),
            targetType: .count,
            targetCount: 3,
            targetPeriod: .week,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )

        XCTAssertEqual(habit.targetType, .binary)
        XCTAssertEqual(habit.targetCount, 1)
        XCTAssertEqual(habit.targetPeriod, .day)
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

    func testSavingHabitThrowsWhenRemoteUpsertFails() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: FailingRemoteDataSource(),
                authService: MockAuthService(authorizationHeaderValue: "Bearer test-token")
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

        do {
            try await repository.saveHabit(habit)
            XCTFail("Expected remote upsert failure")
        } catch {
            XCTAssertEqual(error as? AppError, .network("Remote unavailable"))
        }

        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits.count, 1)
        XCTAssertEqual(savedHabits.first?.id, habit.id)
        XCTAssertEqual(savedHabits.first?.name, habit.name)
        XCTAssertNil(savedHabits.first?.archivedAt)
    }

    @MainActor
    func testSavingHabitRetriesAfterRefreshingExpiredSession() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let remote = ExpiringTokenRemoteDataSource()
        let authService = RefreshingMockAuthService(
            user: AppUser(id: UUID(), email: "test@example.com"),
            initialAuthorizationHeader: "Bearer expired-access-token",
            refreshedAuthorizationHeader: "Bearer fresh-access-token"
        )
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: remote,
                authService: authService
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

        let receivedHeaders = await remote.receivedHeaders()
        XCTAssertEqual(receivedHeaders, ["Bearer expired-access-token", "Bearer fresh-access-token"])
        let restoreSessionCallCount = authService.restoreSessionCallCount
        XCTAssertEqual(restoreSessionCallCount, 1)
    }

    func testSavingHabitWaitsForRemoteUpsertBeforeCompleting() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let remote = BlockingRemoteDataSource()
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: remote,
                authService: MockAuthService()
            )
        }

        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Journal",
            emojiOrIcon: "📓",
            color: .moss,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: .now
        )

        let completionTracker = TaskCompletionTracker()
        let saveTask = Task {
            try await repository.saveHabit(habit)
            await completionTracker.markFinished()
        }

        let remoteCallStarted = await remote.waitForUpsertToStart()
        XCTAssertTrue(remoteCallStarted)

        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits.count, 1)
        XCTAssertEqual(savedHabits.first?.id, habit.id)
        XCTAssertEqual(savedHabits.first?.name, habit.name)
        XCTAssertNotNil(savedHabits.first?.archivedAt)

        try? await Task.sleep(for: .milliseconds(50))
        let saveFinishedBeforeUnblock = await completionTracker.isFinished()
        XCTAssertFalse(saveFinishedBeforeUnblock)

        await remote.finishUpserts()
        try await saveTask.value
        let saveFinishedAfterUnblock = await completionTracker.isFinished()
        XCTAssertTrue(saveFinishedAfterUnblock)
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

        XCTAssertEqual(syncedHabits.count, 1)
        XCTAssertEqual(syncedHabits.first?.id, localOnlyHabit.id)
        XCTAssertEqual(syncedHabits.first?.name, localOnlyHabit.name)
        XCTAssertNil(syncedHabits.first?.archivedAt)
        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits.count, 1)
        XCTAssertEqual(savedHabits.first?.id, localOnlyHabit.id)
        XCTAssertEqual(savedHabits.first?.name, localOnlyHabit.name)
        XCTAssertNil(savedHabits.first?.archivedAt)
    }

    func testArchivingOneHabitDoesNotArchiveOthersWithMatchingCreationTime() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: SuccessfulRemoteDataSource(),
                authService: MockAuthService(authorizationHeaderValue: "Bearer test-token")
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

    func testArchivingOneHabitDoesNotArchiveOthers() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: SuccessfulRemoteDataSource(),
                authService: MockAuthService(authorizationHeaderValue: "Bearer test-token")
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
        try await repository.archiveHabit(firstHabit)

        let savedHabits = try await repository.fetchHabits()
        XCTAssertEqual(savedHabits.count, 2)
        XCTAssertNotNil(savedHabits.first(where: { $0.id == firstHabit.id })?.archivedAt)
        XCTAssertNil(savedHabits.first(where: { $0.id == secondHabit.id })?.archivedAt)
    }

    func testArchivingHabitWaitsForRemoteUpsertBeforeCompleting() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let remote = BlockingRemoteDataSource()
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: remote,
                authService: MockAuthService()
            )
        }

        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Meditate",
            emojiOrIcon: "🧘",
            color: .rose,
            schedule: .daily,
            targetType: .binary,
            targetCount: 1,
            reminderTime: nil,
            createdAt: .now,
            archivedAt: nil
        )
        try await localStore.writeHabits([habit])

        let completionTracker = TaskCompletionTracker()
        let archiveTask = Task {
            try await repository.archiveHabit(habit)
            await completionTracker.markFinished()
        }

        let remoteCallStarted = await remote.waitForUpsertToStart()
        XCTAssertTrue(remoteCallStarted)

        let savedHabits = try await repository.fetchHabits()
        XCTAssertNotNil(savedHabits.first?.archivedAt)

        try? await Task.sleep(for: .milliseconds(50))
        let archiveFinishedBeforeUnblock = await completionTracker.isFinished()
        XCTAssertFalse(archiveFinishedBeforeUnblock)

        await remote.finishUpserts()
        try await archiveTask.value
        let archiveFinishedAfterUnblock = await completionTracker.isFinished()
        XCTAssertTrue(archiveFinishedAfterUnblock)
    }

    func testSavingUpdatedHabitDoesNotChangeOthersWithMatchingCreationTime() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let repository = await MainActor.run {
            DefaultHabitRepository(
                localStore: localStore,
                remote: SuccessfulRemoteDataSource(),
                authService: MockAuthService(authorizationHeaderValue: "Bearer test-token")
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
                remote: SuccessfulRemoteDataSource(),
                authService: MockAuthService(authorizationHeaderValue: "Bearer test-token")
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

    func testSyncPrefersLocalCompletionWhenTimestampsTie() async throws {
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
        let sharedTimestamp = day.addingTimeInterval(120)
        let remoteCompletion = HabitCompletion(
            id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff") ?? UUID(),
            habitId: habitId,
            userId: userId,
            date: day,
            count: 0,
            note: "",
            createdAt: sharedTimestamp
        )
        let localCompletion = HabitCompletion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            habitId: habitId,
            userId: userId,
            date: day,
            count: 1,
            note: "",
            createdAt: sharedTimestamp
        )

        try await localStore.writeCompletions([localCompletion])
        await remote.setCompletions([remoteCompletion])

        let synced = try await repository.sync()
        XCTAssertEqual(synced.count, 1)
        XCTAssertEqual(synced.first?.count, 1)
    }

    @MainActor
    func testRecordCompletionOnlyChangesTappedHabit() async {
        let habitRepository = StubHabitRepository()
        let checkInRepository = StubCheckInRepository()
        let environment = AppEnvironment(
            authService: SupabaseAuthService(),
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

    @MainActor
    func testArchiveRollbackRestoresLocalStateWhenRemoteUpsertFails() async throws {
        let localStore = LocalStore(
            baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let authService = SupabaseAuthService()
        let habitRepository = DefaultHabitRepository(
            localStore: localStore,
            remote: FailingRemoteDataSource(),
            authService: authService
        )
        let environment = AppEnvironment(
            authService: authService,
            reminderService: NoopReminderService(),
            widgetSyncService: WidgetSyncService(),
            analyticsService: AnalyticsService(),
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            localStore: localStore,
            habitRepository: habitRepository,
            checkInRepository: StubCheckInRepository()
        )

        let habit = Habit(
            id: UUID(),
            userId: UUID(),
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

        environment.habits = [habit]
        try await localStore.writeHabits([habit])

        await environment.archiveHabit(habit)

        XCTAssertNil(environment.habits.first?.archivedAt)
        XCTAssertEqual(environment.errorMessage, "Remote unavailable")
        let persistedHabits = try await localStore.readHabits()
        XCTAssertNil(persistedHabits.first?.archivedAt)
    }

    @MainActor
    func testRestoreSessionRefreshesExpiredAccessToken() async throws {
        let user = SupabaseUser(id: UUID(), email: "test@example.com")
        let sessionStore = SessionStore(
            service: "HabitTracker.auth.tests.\(UUID().uuidString)",
            account: "supabase.session"
        )
        defer { try? sessionStore.clear() }

        try sessionStore.write(
            SupabaseSession(
                accessToken: "expired-access-token",
                refreshToken: "valid-refresh-token",
                user: user
            )
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let supabaseURL = URL(string: "https://example.supabase.co")!

        MockURLProtocol.requestHandler = { request in
            switch (request.url?.path, request.url?.query) {
            case ("/auth/v1/user", _):
                let authHeader = request.value(forHTTPHeaderField: "Authorization")
                if authHeader == "Bearer expired-access-token" {
                    return (
                        HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                        #"{"message":"Invalid JWT","code":"bad_jwt"}"#.data(using: .utf8)!
                    )
                }

                XCTFail("Unexpected user request authorization header: \(authHeader ?? "nil")")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            case ("/auth/v1/token", "grant_type=refresh_token"):
                let refreshed = """
                {
                  "access_token": "fresh-access-token",
                  "refresh_token": "fresh-refresh-token",
                  "user": {
                    "id": "\(user.id.uuidString.lowercased())",
                    "email": "\(user.email)"
                  }
                }
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(refreshed.utf8)
                )

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return (
                    HTTPURLResponse(url: supabaseURL, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let authService = SupabaseAuthService(
            configuration: SupabaseConfiguration(url: supabaseURL, anonKey: "anon-key"),
            urlSession: urlSession,
            sessionStore: sessionStore
        )

        let restoredUser = try await authService.restoreSession()
        let storedSession = try sessionStore.read()

        XCTAssertEqual(restoredUser, AppUser(id: user.id, email: user.email))
        XCTAssertEqual(storedSession?.accessToken, "fresh-access-token")
        XCTAssertEqual(storedSession?.refreshToken, "fresh-refresh-token")
    }
}

private struct FailingRemoteDataSource: HabitRemoteDataSource {
    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }
    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        throw AppError.network("Remote unavailable")
    }
    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {
        throw AppError.network("Remote unavailable")
    }
}

private struct SuccessfulRemoteDataSource: HabitRemoteDataSource {
    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }
    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {}
    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}
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

    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}
}

private actor BlockingRemoteDataSource: HabitRemoteDataSource {
    private var didStartUpsert = false
    private var continuation: CheckedContinuation<Void, Never>?

    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }

    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        didStartUpsert = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}

    func waitForUpsertToStart() async -> Bool {
        for _ in 0..<50 {
            if didStartUpsert {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func finishUpserts() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ExpiringTokenRemoteDataSource: HabitRemoteDataSource {
    private var headers: [String?] = []

    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }

    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        headers.append(authHeader)
        if authHeader == "Bearer expired-access-token" {
            throw AppError.network("Invalid JWT")
        }
    }

    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { [] }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}

    func receivedHeaders() -> [String?] {
        headers
    }
}

private actor DuplicateCompletionRemoteDataSource: HabitRemoteDataSource {
    private var completions: [HabitCompletion] = []

    func setCompletions(_ completions: [HabitCompletion]) {
        self.completions = completions
    }

    func fetchHabits(authHeader: String?) async throws -> [Habit] { [] }
    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {}
    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] { completions }
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {}
}

private actor TaskCompletionTracker {
    private var finished = false

    func markFinished() {
        finished = true
    }

    func isFinished() -> Bool {
        finished
    }
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

    func sync() async throws -> [HabitCompletion] { completions }
}

private struct NoopReminderService: ReminderService {
    func requestAuthorization() async throws -> Bool { true }
    func rescheduleNotifications(for habits: [Habit]) async throws {}
    func clearAllNotifications() async {}
}

@MainActor
private final class MockAuthService: AuthService {
    var currentUser: AppUser?
    private let authorizationHeaderValue: String?

    init(currentUser: AppUser? = nil, authorizationHeaderValue: String? = nil) {
        self.currentUser = currentUser
        self.authorizationHeaderValue = authorizationHeaderValue
    }

    func restoreSession() async throws -> AppUser? { currentUser }
    func signIn(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signUp(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func deleteAccount(currentPassword: String) async throws {}
    func signOut() async throws {}
    func authorizationHeader() -> String? { authorizationHeaderValue }
}

@MainActor
private final class RefreshingMockAuthService: AuthService {
    var currentUser: AppUser?
    var authorizationHeaderValue: String?
    let refreshedAuthorizationHeader: String
    private(set) var restoreSessionCallCount = 0

    init(user: AppUser, initialAuthorizationHeader: String?, refreshedAuthorizationHeader: String) {
        self.currentUser = user
        self.authorizationHeaderValue = initialAuthorizationHeader
        self.refreshedAuthorizationHeader = refreshedAuthorizationHeader
    }

    func restoreSession() async throws -> AppUser? {
        restoreSessionCallCount += 1
        authorizationHeaderValue = refreshedAuthorizationHeader
        return currentUser
    }

    func signIn(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signUp(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func deleteAccount(currentPassword: String) async throws {}
    func signOut() async throws {}
    func authorizationHeader() -> String? { authorizationHeaderValue }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: AppError.network("Missing request handler"))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
