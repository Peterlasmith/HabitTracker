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

enum HabitTargetPeriod: String, Codable, CaseIterable, Identifiable {
    case day
    case week

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
    var targetPeriod: HabitTargetPeriod
    var reminderTime: DateComponents?
    var createdAt: Date
    var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case name
        case emojiOrIcon
        case color
        case schedule
        case targetType
        case targetCount
        case targetPeriod
        case reminderTime
        case createdAt
        case archivedAt
    }

    init(
        id: UUID,
        userId: UUID,
        name: String,
        emojiOrIcon: String,
        color: HabitColor,
        schedule: HabitSchedule,
        targetType: HabitTargetType,
        targetCount: Int,
        targetPeriod: HabitTargetPeriod? = nil,
        reminderTime: DateComponents?,
        createdAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.emojiOrIcon = emojiOrIcon
        self.color = color
        self.schedule = schedule
        self.targetType = targetType
        self.targetCount = targetCount
        self.targetPeriod = targetPeriod ?? Habit.defaultTargetPeriod(for: targetType)
        self.reminderTime = reminderTime
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        emojiOrIcon = try container.decode(String.self, forKey: .emojiOrIcon)
        color = try container.decode(HabitColor.self, forKey: .color)
        schedule = try container.decode(HabitSchedule.self, forKey: .schedule)
        targetType = try container.decode(HabitTargetType.self, forKey: .targetType)
        targetCount = try container.decode(Int.self, forKey: .targetCount)
        targetPeriod = try container.decodeIfPresent(HabitTargetPeriod.self, forKey: .targetPeriod)
            ?? Habit.defaultTargetPeriod(for: targetType)
        reminderTime = try container.decodeIfPresent(DateComponents.self, forKey: .reminderTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(emojiOrIcon, forKey: .emojiOrIcon)
        try container.encode(color, forKey: .color)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(targetType, forKey: .targetType)
        try container.encode(targetCount, forKey: .targetCount)
        try container.encode(targetPeriod, forKey: .targetPeriod)
        try container.encode(reminderTime, forKey: .reminderTime)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(archivedAt, forKey: .archivedAt)
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var effectiveTargetPeriod: HabitTargetPeriod {
        targetType == .binary ? .day : targetPeriod
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        !isArchived && schedule.isDue(on: date, calendar: calendar)
    }

    func currentPeriodRange(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start: Date
        let end: Date

        switch effectiveTargetPeriod {
        case .day:
            start = calendar.startOfDay(for: date)
            end = start
        case .week:
            start = calendar.startOfWeek(containing: date)
            end = calendar.endOfWeek(containing: date)
        }

        return DateInterval(start: start, end: end)
    }

    func periodProgress(
        referenceDate: Date,
        completions: [HabitCompletion],
        calendar: Calendar = .current
    ) -> HabitPeriodProgress {
        switch targetType {
        case .binary:
            let day = calendar.startOfDay(for: referenceDate)
            let completion = completions.first { calendar.isDate($0.date, inSameDayAs: day) }
            let completed = completion?.count ?? 0 > 0 ? 1 : 0
            return HabitPeriodProgress(
                period: currentPeriodRange(containing: referenceDate, calendar: calendar),
                completedCount: completed,
                targetCount: 1
            )
        case .count:
            let period = currentPeriodRange(containing: referenceDate, calendar: calendar)
            let endDate = min(calendar.startOfDay(for: referenceDate), period.end)
            let total = completions.reduce(into: 0) { partialResult, completion in
                let day = calendar.startOfDay(for: completion.date)
                guard day >= period.start, day <= endDate, isDue(on: day, calendar: calendar) else { return }
                partialResult += max(completion.count, 0)
            }

            return HabitPeriodProgress(
                period: period,
                completedCount: total,
                targetCount: targetCount
            )
        }
    }

    func isComplete(
        referenceDate: Date,
        completions: [HabitCompletion],
        calendar: Calendar = .current
    ) -> Bool {
        periodProgress(referenceDate: referenceDate, completions: completions, calendar: calendar).isComplete
    }

    func eventCount(
        on date: Date,
        completions: [HabitCompletion],
        calendar: Calendar = .current
    ) -> Int {
        completions.first { calendar.isDate($0.date, inSameDayAs: date) }?.count ?? 0
    }

    private static func defaultTargetPeriod(for type: HabitTargetType) -> HabitTargetPeriod {
        switch type {
        case .binary:
            return .day
        case .count:
            return .week
        }
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
}

struct HabitPeriodProgress: Equatable {
    let period: DateInterval
    let completedCount: Int
    let targetCount: Int

    var isComplete: Bool {
        completedCount >= targetCount
    }

    var progress: Double {
        min(Double(completedCount) / Double(max(targetCount, 1)), 1)
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
        completion?.count ?? 0 > 0
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
        switch habit.effectiveTargetPeriod {
        case .day:
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

                guard let completion = normalizedCompletions[cursor], completion.count > 0 else {
                    break
                }

                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            }

            return streak
        case .week:
            var streak = 0
            var cursor = calendar.startOfWeek(containing: referenceDate)

            while true {
                let progress = habit.periodProgress(referenceDate: cursor, completions: completions, calendar: calendar)
                guard progress.isComplete else { break }
                streak += 1
                guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
                cursor = previousWeek
            }

            return streak
        }
    }
}
