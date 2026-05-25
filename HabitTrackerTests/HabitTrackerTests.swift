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

@MainActor
private final class MockAuthService: AuthService {
    var currentUser: AppUser?

    func restoreSession() async throws -> AppUser? { currentUser }
    func signIn(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signUp(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signOut() async throws {}
    func authorizationHeader() -> String? { nil }
}
