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

    static var supportedCases: [HabitTargetType] {
        [.binary]
    }
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
        createdAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.emojiOrIcon = emojiOrIcon
        self.color = color
        self.schedule = schedule
        self.targetType = Habit.normalizedTargetType(targetType)
        self.targetCount = Habit.normalizedTargetCount(for: targetType, targetCount: targetCount)
        self.targetPeriod = .day
        self.reminderTime = reminderTime
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        emojiOrIcon = try container.decode(String.self, forKey: .emojiOrIcon)
        color = try container.decode(HabitColor.self, forKey: .color)
        schedule = try container.decode(HabitSchedule.self, forKey: .schedule)
        let decodedTargetType = try container.decode(HabitTargetType.self, forKey: .targetType)
        let decodedTargetCount = try container.decode(Int.self, forKey: .targetCount)
        targetType = Habit.normalizedTargetType(decodedTargetType)
        targetCount = Habit.normalizedTargetCount(for: decodedTargetType, targetCount: decodedTargetCount)
        targetPeriod = .day
        reminderTime = try container.decodeIfPresent(DateComponents.self, forKey: .reminderTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(emojiOrIcon, forKey: .emojiOrIcon)
        try container.encode(color, forKey: .color)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(Habit.normalizedTargetType(targetType), forKey: .targetType)
        try container.encode(targetCount, forKey: .targetCount)
        try container.encode(HabitTargetPeriod.day, forKey: .targetPeriod)
        try container.encode(reminderTime, forKey: .reminderTime)
        try container.encode(createdAt, forKey: .createdAt)
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        schedule.isDue(on: date, calendar: calendar)
    }

    func currentPeriodRange(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: start)
    }

    func periodProgress(
        referenceDate: Date,
        completions: [HabitCompletion],
        calendar: Calendar = .current
    ) -> HabitPeriodProgress {
        let day = calendar.startOfDay(for: referenceDate)
        let completion = completions.first { calendar.isDate($0.date, inSameDayAs: day) }
        let completed = completion?.count ?? 0 > 0 ? 1 : 0
        return HabitPeriodProgress(
            period: currentPeriodRange(containing: referenceDate, calendar: calendar),
            completedCount: completed,
            targetCount: 1
        )
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

    private static func normalizedTargetType(_ type: HabitTargetType) -> HabitTargetType {
        switch type {
        case .binary, .count:
            return .binary
        }
    }

    private static func normalizedTargetCount(for type: HabitTargetType, targetCount: Int) -> Int {
        switch type {
        case .binary, .count:
            return 1
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

func normalizedCheckCount(_ count: Int) -> Int {
    count > 0 ? 1 : 0
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
        return normalizedCheckCount(completion.count) > 0 ? 1 : 0
    }

    var isComplete: Bool {
        normalizedCheckCount(completion?.count ?? 0) > 0
    }

    var streakLabel: String {
        "Done"
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

            guard let completion = normalizedCompletions[cursor], normalizedCheckCount(completion.count) > 0 else {
                break
            }

            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    static func currentCalendarDayStreak(
        for habit: Habit,
        completions: [HabitCompletion],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let normalizedCompletions = Set(
            completions
                .filter { normalizedCheckCount($0.count) > 0 }
                .map { calendar.startOfDay(for: $0.date) }
        )

        var streak = 0
        var cursor = calendar.startOfDay(for: referenceDate)

        while normalizedCompletions.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }
}
