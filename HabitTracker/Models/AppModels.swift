import Foundation
import SwiftUI

struct AppUser: Codable, Equatable, Identifiable {
    let id: UUID
    let email: String
}

enum HabitColor: String, Codable, CaseIterable, Identifiable {
    case coral
    case gold
    case teal
    case slate
    case moss
    case rose

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .coral: return Color(red: 0.92, green: 0.42, blue: 0.34)
        case .gold: return Color(red: 0.88, green: 0.66, blue: 0.18)
        case .teal: return Color(red: 0.18, green: 0.58, blue: 0.56)
        case .slate: return Color(red: 0.26, green: 0.31, blue: 0.39)
        case .moss: return Color(red: 0.35, green: 0.50, blue: 0.25)
        case .rose: return Color(red: 0.76, green: 0.37, blue: 0.49)
        }
    }
}

enum HabitTargetType: String, Codable, CaseIterable, Identifiable {
    case binary
    case count

    var id: String { rawValue }
}

enum HabitSchedule: Codable, Equatable {
    case daily
    case weekdays(Set<Weekday>)

    var weekdays: [Weekday] {
        switch self {
        case .daily:
            return Weekday.allCases
        case .weekdays(let days):
            return days.sorted()
        }
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays(let days):
            guard let weekday = Weekday(date: date, calendar: calendar) else { return false }
            return days.contains(weekday)
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    init?(date: Date, calendar: Calendar) {
        self.init(rawValue: calendar.component(.weekday, from: date))
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Habit: Codable, Equatable, Identifiable {
    var id: UUID
    var userId: UUID
    var name: String
    var emojiOrIcon: String
    var color: HabitColor
    var schedule: HabitSchedule
    var targetType: HabitTargetType
    var targetCount: Int
    var reminderTime: DateComponents?
    var createdAt: Date
    var archivedAt: Date?

    var isArchived: Bool {
        archivedAt != nil
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        !isArchived && schedule.isDue(on: date, calendar: calendar)
    }
}

struct HabitCompletion: Codable, Equatable, Identifiable {
    var id: UUID
    var habitId: UUID
    var userId: UUID
    var date: Date
    var count: Int
    var note: String
    var createdAt: Date

    func isCompleted(for habit: Habit) -> Bool {
        switch habit.targetType {
        case .binary:
            return count > 0
        case .count:
            return count >= habit.targetCount
        }
    }
}

struct WidgetHabitSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let emojiOrIcon: String
    let colorName: String
    let isComplete: Bool
}

struct WidgetSummary: Codable, Equatable {
    let date: Date
    let completionRatio: Double
    let completedCount: Int
    let totalCount: Int
    let habits: [WidgetHabitSummary]
}

struct HabitWithProgress: Identifiable, Equatable {
    let habit: Habit
    let completion: HabitCompletion?

    var id: UUID { habit.id }

    var progress: Double {
        guard let completion else { return 0 }
        switch habit.targetType {
        case .binary:
            return completion.count > 0 ? 1 : 0
        case .count:
            return min(Double(completion.count) / Double(max(habit.targetCount, 1)), 1)
        }
    }

    var isComplete: Bool {
        completion?.isCompleted(for: habit) == true
    }

    var streakLabel: String {
        habit.targetType == .binary ? "Done" : "\(completion?.count ?? 0)/\(habit.targetCount)"
    }
}

enum StreakCalculator {
    static func currentStreak(
        for habit: Habit,
        completions: [HabitCompletion],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let normalizedCompletions = Dictionary(uniqueKeysWithValues: completions.map {
            (calendar.startOfDay(for: $0.date), $0)
        })

        var streak = 0
        var cursor = calendar.startOfDay(for: referenceDate)

        while true {
            guard habit.isDue(on: cursor, calendar: calendar) else {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }

            guard let completion = normalizedCompletions[cursor], completion.isCompleted(for: habit) else {
                break
            }

            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }
}
