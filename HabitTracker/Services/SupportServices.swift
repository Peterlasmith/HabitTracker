import Foundation
import OSLog
import UserNotifications
import WidgetKit

enum AppError: LocalizedError, Equatable {
    case network(String)
    case storage(String)
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .network(let message), .storage(let message), .configuration(let message):
            return message
        }
    }
}

protocol ReminderService {
    func requestAuthorization() async throws -> Bool
    func rescheduleNotifications(for habits: [Habit]) async throws
    func clearAllNotifications() async
}

struct DefaultReminderService: ReminderService {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func rescheduleNotifications(for habits: [Habit]) async throws {
        let center = UNUserNotificationCenter.current()
        let identifiers = habits.flatMap(notificationIdentifiers(for:))
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for habit in habits where habit.reminderTime != nil {
            let content = UNMutableNotificationContent()
            content.title = habit.name
            content.body = "Time to keep your streak alive."
            content.sound = .default

            switch habit.schedule {
            case .daily:
                guard let reminderTime = habit.reminderTime else { continue }
                var components = DateComponents()
                components.hour = reminderTime.hour
                components.minute = reminderTime.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: "habit-\(habit.id.uuidString)", content: content, trigger: trigger)
                try await center.add(request)
            case .weekdays(let days):
                for day in days {
                    guard let reminderTime = habit.reminderTime else { continue }
                    var components = DateComponents()
                    components.weekday = day.rawValue
                    components.hour = reminderTime.hour
                    components.minute = reminderTime.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "habit-\(habit.id.uuidString)-\(day.rawValue)",
                        content: content,
                        trigger: trigger
                    )
                    try await center.add(request)
                }
            }
        }
    }

    private func notificationIdentifiers(for habit: Habit) -> [String] {
        let baseIdentifier = "habit-\(habit.id.uuidString)"
        let weekdayIdentifiers = Weekday.allCases.map { "\(baseIdentifier)-\($0.rawValue)" }
        return [baseIdentifier] + weekdayIdentifiers
    }

    func clearAllNotifications() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

struct WidgetSyncService {
    static let appGroup = "group.com.done.HabitTracker.shared"
    static let summaryKey = "widget.summary"

    func publish(habits: [Habit], completions: [HabitCompletion], date: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        let dueHabits = habits.filter { $0.isDue(on: date, calendar: calendar) }
        let summaries = dueHabits.map { habit -> WidgetHabitSummary in
            let habitCompletions = completions
                .filter { $0.habitId == habit.id }
                .sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id.uuidString > rhs.id.uuidString
                    }
                    return lhs.createdAt > rhs.createdAt
                }
            return WidgetHabitSummary(
                id: habit.id,
                name: habit.name,
                emojiOrIcon: habit.emojiOrIcon,
                colorName: habit.color.rawValue,
                isComplete: habit.isComplete(referenceDate: today, completions: habitCompletions, calendar: calendar)
            )
        }

        let completedCount = summaries.filter(\.isComplete).count
        let summary = WidgetSummary(
            date: today,
            completionRatio: dueHabits.isEmpty ? 0 : Double(completedCount) / Double(dueHabits.count),
            completedCount: completedCount,
            totalCount: dueHabits.count,
            habits: summaries
        )

        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder.supabase.encode(summary)
        else { return }

        defaults.set(data, forKey: Self.summaryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clearPublishedData() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        defaults.removeObject(forKey: Self.summaryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct AnalyticsService {
    func track(_ event: AnalyticsEvent) {
        AppLogger.analytics.info("Analytics event: \(event.rawValue, privacy: .public)")
    }
}

enum AnalyticsEvent: String {
    case completedOnboarding
    case createdAccount
    case signedIn
    case createdHabit
    case enabledReminder
    case completedHabit
}

enum AppLogger {
    static let app = Logger(subsystem: "com.done.HabitTracker", category: "app")
    static let analytics = Logger(subsystem: "com.done.HabitTracker", category: "analytics")
}
