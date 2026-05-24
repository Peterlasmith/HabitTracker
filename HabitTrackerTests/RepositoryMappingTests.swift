import XCTest
@testable import HabitTracker

final class RepositoryMappingTests: XCTestCase {
    func testHabitRowRoundTripPreservesScheduleAndReminder() {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Meditate",
            emojiOrIcon: "🧘",
            color: .moss,
            schedule: .weekdays([.monday, .thursday]),
            targetType: .count,
            targetCount: 3,
            reminderTime: DateComponents(hour: 7, minute: 15),
            createdAt: .now,
            archivedAt: nil
        )

        let row = HabitRow(habit: habit)
        XCTAssertEqual(row.habit.schedule, habit.schedule)
        XCTAssertEqual(row.habit.reminderTime?.hour, 7)
        XCTAssertEqual(row.habit.reminderTime?.minute, 15)
    }
}
