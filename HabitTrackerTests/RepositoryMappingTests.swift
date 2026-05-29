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
        XCTAssertEqual(row.habit.targetPeriod, .week)
        XCTAssertEqual(row.habit.reminderTime?.hour, 7)
        XCTAssertEqual(row.habit.reminderTime?.minute, 15)
    }

    func testHabitRowEncodingIncludesNullOptionals() throws {
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

        let row = HabitRow(habit: habit)
        let data = try JSONEncoder.supabase.encode([row])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let encodedRow = try XCTUnwrap(payload.first)

        XCTAssertTrue(encodedRow.keys.contains("archived_at"))
        XCTAssertTrue(encodedRow.keys.contains("reminder_hour"))
        XCTAssertTrue(encodedRow.keys.contains("reminder_minute"))
        XCTAssertTrue(encodedRow.keys.contains("target_period"))
        XCTAssertTrue(encodedRow["archived_at"] is NSNull)
        XCTAssertTrue(encodedRow["reminder_hour"] is NSNull)
        XCTAssertTrue(encodedRow["reminder_minute"] is NSNull)
        XCTAssertEqual(encodedRow["target_period"] as? String, "day")
    }
}
