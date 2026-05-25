import SwiftUI

private enum TrackerScope: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

struct TodayDashboardView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingEditor = false
    @State private var showingManager = false
    @State private var selectedScope: TrackerScope = .week
    @State private var anchorDate = Calendar.autoupdatingCurrent.startOfDay(for: .now)

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let habits = activeHabits
        let period = TrackerPeriod(scope: selectedScope, anchor: anchorDate, calendar: calendar, today: today)
        let weekSummary = currentWeekSummary(for: habits)
        let topStreak = habits.map(currentStreak(for:)).max() ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar(habits: habits)
                trackerScopePicker
                periodHeader(period: period)
                summaryStrip(summary: weekSummary, topStreak: topStreak, habitCount: habits.count)
                trackerContent(habits: habits, period: period)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HabitEditorView()
            }
        }
        .sheet(isPresented: $showingManager) {
            NavigationStack {
                HabitManagerView()
            }
        }
    }

    private var activeHabits: [Habit] {
        environment.habits
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var today: Date {
        calendar.startOfDay(for: .now)
    }

    private func topBar(habits: [Habit]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 18, height: 18)

                    Text("HabitClaw")
                        .font(AppTheme.serif(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Text(habits.isEmpty ? "Build a calm routine that still feels easy to return to." : todaySummary(for: habits))
                    .font(AppTheme.sans(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if !habits.isEmpty {
                    Button("Manage") {
                        showingManager = true
                    }
                    .font(AppTheme.sans(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.surfaceStrong)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.surfaceStrong)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
                }
            }
        }
    }

    private var trackerScopePicker: some View {
        HStack(spacing: 6) {
            ForEach(TrackerScope.allCases) { scope in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedScope = scope
                        anchorDate = today
                    }
                } label: {
                    Text(scope.rawValue)
                        .font(AppTheme.sans(size: 14, weight: .medium))
                        .foregroundStyle(selectedScope == scope ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selectedScope == scope ? AppTheme.surfaceStrong : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(red: 0.91, green: 0.89, blue: 0.83))
        .clipShape(Capsule())
    }

    private func periodHeader(period: TrackerPeriod) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.kicker)
                    .font(AppTheme.sans(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.1)

                Text(period.title)
                    .font(AppTheme.serif(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer()

            HStack(spacing: 8) {
                periodButton(systemName: "chevron.left") {
                    anchorDate = period.shifted(by: -1)
                }
                periodButton(systemName: "chevron.right") {
                    anchorDate = period.shifted(by: 1)
                }
            }
        }
    }

    private func periodButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.surfaceStrong)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func summaryStrip(summary: TrackerWeekSummary, topStreak: Int, habitCount: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This week")
                    .font(AppTheme.sans(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.1)

                Text("\(summary.completed)")
                    .font(AppTheme.sans(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                + Text(" / \(max(summary.eligible, 1))")
                    .font(AppTheme.sans(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("\(summary.percentage)% complete")
                    .font(AppTheme.sans(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()

            VStack(alignment: .leading, spacing: 6) {
                Text("Top streak")
                    .font(AppTheme.sans(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.1)

                Text("\(topStreak)")
                    .font(AppTheme.sans(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                + Text(" days")
                    .font(AppTheme.sans(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("Across \(habitCount) habits")
                    .font(AppTheme.sans(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }

    @ViewBuilder
    private func trackerContent(habits: [Habit], period: TrackerPeriod) -> some View {
        if habits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("No habits yet")
                    .font(AppTheme.serif(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Add your first habit to start filling out the weekly rhythm and long-term streak views.")
                    .font(AppTheme.sans(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        } else {
            VStack(spacing: 10) {
                switch selectedScope {
                case .week:
                    let weekDates = calendar.days(from: period.start, through: period.end)
                    ForEach(habits, id: \.id) { habit in
                        WeekHabitCard(
                            habit: habit,
                            dates: weekDates,
                            today: today,
                            calendar: calendar,
                            streak: currentStreak(for: habit),
                            completionMap: completionMap(for: habit),
                            onToggle: { date in
                                Task { await toggle(habit: habit, on: date) }
                            }
                        )
                            .id(habit.id)
                    }
                case .month:
                    let monthCells = calendar.monthGridDates(for: period.start)
                    ForEach(habits, id: \.id) { habit in
                        MonthHabitCard(
                            habit: habit,
                            dates: monthCells,
                            monthAnchor: period.start,
                            today: today,
                            calendar: calendar,
                            completionMap: completionMap(for: habit)
                        )
                            .id(habit.id)
                    }
                case .year:
                    let yearCells = calendar.yearGridDates(for: period.start)
                    ForEach(habits, id: \.id) { habit in
                        YearHabitCard(
                            habit: habit,
                            dates: yearCells,
                            yearAnchor: period.start,
                            today: today,
                            calendar: calendar,
                            bestStreak: currentStreak(for: habit, through: min(calendar.endOfYear(containing: period.start), today)),
                            completionMap: completionMap(for: habit)
                        )
                            .id(habit.id)
                    }
                }

            }
        }
    }

    private func currentWeekSummary(for habits: [Habit]) -> TrackerWeekSummary {
        let weekStart = calendar.startOfWeek(containing: today)
        let weekDates = calendar.days(from: weekStart, through: min(calendar.endOfWeek(containing: today), today))

        var completed = 0
        var eligible = 0

        for habit in habits {
            for date in weekDates where habit.isDue(on: date, calendar: calendar) {
                eligible += 1
                if completion(for: habit, on: date)?.isCompleted(for: habit) == true {
                    completed += 1
                }
            }
        }

        return TrackerWeekSummary(completed: completed, eligible: eligible)
    }

    private func todaySummary(for habits: [Habit]) -> String {
        let dueHabits = habits.filter { $0.isDue(on: today, calendar: calendar) }
        let completed = dueHabits.filter { completion(for: $0, on: today)?.isCompleted(for: $0) == true }.count

        if dueHabits.isEmpty {
            return "Nothing is due today, but your trend view is still right here."
        }

        return "\(completed) of \(dueHabits.count) habits complete today."
    }

    private func completion(for habit: Habit, on date: Date) -> HabitCompletion? {
        environment.completion(for: habit, on: date)
    }

    private func currentStreak(for habit: Habit) -> Int {
        StreakCalculator.currentStreak(
            for: habit,
            completions: environment.completionHistory(for: habit),
            referenceDate: today,
            calendar: calendar
        )
    }

    private func currentStreak(for habit: Habit, through endDate: Date) -> Int {
        bestStreak(
            for: habit,
            through: endDate,
            calendar: calendar,
            completions: environment.completionHistory(for: habit)
        )
    }

    private func completionMap(for habit: Habit) -> [Date: HabitCompletion] {
        Dictionary(uniqueKeysWithValues: environment.completionHistory(for: habit).map {
            (calendar.startOfDay(for: $0.date), $0)
        })
    }

    private func toggle(habit: Habit, on date: Date) async {
        let current = completion(for: habit, on: date)
        let nextCount: Int
        switch habit.targetType {
        case .binary:
            nextCount = current?.count ?? 0 > 0 ? 0 : 1
        case .count:
            let existing = current?.count ?? 0
            nextCount = existing >= habit.targetCount ? 0 : existing + 1
        }

        await environment.recordCompletion(for: habit, count: nextCount, date: date)
    }
}

private struct WeekHabitCard: View {
    let habit: Habit
    let dates: [Date]
    let today: Date
    let calendar: Calendar
    let streak: Int
    let completionMap: [Date: HabitCompletion]
    let onToggle: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HabitCardHeader(
                habit: habit,
                subtitle: habitScheduleLabel(habit.schedule),
                trailingValue: streak == 0 ? nil : "\(streak)",
                trailingLabel: streak == 1 ? "day" : "days"
            )

            HStack(spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    let completion = completion(on: date)
                    let isDue = habit.isDue(on: date, calendar: calendar)
                    let isFuture = date > today
                    let isComplete = completion?.isCompleted(for: habit) == true
                    let count = completion?.count ?? 0

                    VStack(spacing: 5) {
                        Text(shortWeekdayLabel(for: date))
                            .font(AppTheme.sans(size: 10, weight: .semibold))
                            .foregroundStyle(calendar.isDate(date, inSameDayAs: today) ? AppTheme.accent : AppTheme.textSecondary)

                        Button {
                            onToggle(date)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(isComplete ? AppTheme.accent : .clear)

                                if isComplete {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 10, height: 10)
                                } else if habit.targetType == .count, count > 0 {
                                    Text("\(count)")
                                        .font(AppTheme.sans(size: 11, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                            .background(
                                Circle()
                                    .fill(calendar.isDate(date, inSameDayAs: today) && !isComplete ? AppTheme.accentSoft : .clear)
                                    .padding(-3)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        strokeColor(isDue: isDue, isFuture: isFuture, isComplete: isComplete, isToday: calendar.isDate(date, inSameDayAs: today)),
                                        style: StrokeStyle(lineWidth: isComplete ? 0 : 1.5, dash: isFuture ? [4] : [])
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isDue || isFuture)

                        Text("\(calendar.component(.day, from: date))")
                            .font(AppTheme.serif(size: 13, weight: .semibold))
                            .foregroundStyle(calendar.isDate(date, inSameDayAs: today) ? AppTheme.accent : AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if habit.targetType == .count {
                Text("Goal: \(habit.targetCount) check-ins on each scheduled day.")
                    .font(AppTheme.sans(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .appCard()
    }

    private func completion(on date: Date) -> HabitCompletion? {
        completionMap[calendar.startOfDay(for: date)]
    }
}

private struct MonthHabitCard: View {
    let habit: Habit
    let dates: [Date]
    let monthAnchor: Date
    let today: Date
    let calendar: Calendar
    let completionMap: [Date: HabitCompletion]

    var body: some View {
        let monthDates = dates.filter { calendar.isDate($0, equalTo: monthAnchor, toGranularity: .month) && $0 <= today }
        let eligible = monthDates.filter { habit.isDue(on: $0, calendar: calendar) }.count
        let completed = monthDates.filter { completion(on: $0)?.isCompleted(for: habit) == true }.count
        let percentage = Int((Double(completed) / Double(max(eligible, 1)) * 100).rounded())

        VStack(alignment: .leading, spacing: 14) {
            HabitCardHeader(
                habit: habit,
                subtitle: habitScheduleLabel(habit.schedule),
                trailingValue: "\(completed)",
                trailingLabel: "/ \(max(eligible, 1)) · \(percentage)%"
            )

            HStack(spacing: 4) {
                ForEach(Array(calendar.veryShortWeekdaySymbolsMondayFirst.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(AppTheme.sans(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    let isInMonth = calendar.isDate(date, equalTo: monthAnchor, toGranularity: .month)
                    let completion = completion(on: date)
                    let isDue = habit.isDue(on: date, calendar: calendar)
                    let isFuture = date > today
                    let isComplete = completion?.isCompleted(for: habit) == true
                    let count = completion?.count ?? 0

                    Group {
                        if isInMonth {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isComplete ? AppTheme.accent : .clear)
                                if isComplete {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(AppTheme.sans(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                } else if habit.targetType == .count, count > 0 {
                                    Text("\(count)")
                                        .font(AppTheme.sans(size: 11, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                } else {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(AppTheme.sans(size: 11, weight: .medium))
                                        .foregroundStyle(isFuture ? AppTheme.border : AppTheme.textSecondary)
                                }
                            }
                            .frame(height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(
                                        strokeColor(isDue: isDue, isFuture: isFuture, isComplete: isComplete, isToday: calendar.isDate(date, inSameDayAs: today)),
                                        style: StrokeStyle(lineWidth: isComplete ? 0 : 1, dash: isFuture ? [4] : [])
                                    )
                            )
                            .overlay(alignment: .center) {
                                if calendar.isDate(date, inSameDayAs: today) && !isComplete {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(AppTheme.accent, lineWidth: 1)
                                        .padding(1)
                                }
                            }
                        } else {
                            Color.clear
                                .frame(height: 32)
                        }
                    }
                }
            }
        }
        .appCard()
    }

    private func completion(on date: Date) -> HabitCompletion? {
        completionMap[calendar.startOfDay(for: date)]
    }
}

private struct YearHabitCard: View {
    let habit: Habit
    let dates: [Date]
    let yearAnchor: Date
    let today: Date
    let calendar: Calendar
    let bestStreak: Int
    let completionMap: [Date: HabitCompletion]

    var body: some View {
        let inYearDates = dates.filter { calendar.isDate($0, equalTo: yearAnchor, toGranularity: .year) && $0 <= today }
        let eligible = inYearDates.filter { habit.isDue(on: $0, calendar: calendar) }.count
        let completed = inYearDates.filter { completion(on: $0)?.isCompleted(for: habit) == true }.count
        let percentage = Int((Double(completed) / Double(max(eligible, 1)) * 100).rounded())

        VStack(alignment: .leading, spacing: 14) {
            HabitCardHeader(
                habit: habit,
                subtitle: "\(completed) / \(max(eligible, 1)) days · \(percentage)%",
                trailingValue: "\(bestStreak)",
                trailingLabel: "best"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(10), spacing: 3), count: 7), spacing: 3) {
                    ForEach(dates, id: \.self) { date in
                        let isInYear = calendar.isDate(date, equalTo: yearAnchor, toGranularity: .year)
                        let isFuture = date > today
                        let isComplete = completion(on: date)?.isCompleted(for: habit) == true

                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(isComplete ? AppTheme.accent : Color(red: 0.92, green: 0.89, blue: 0.84))
                            .frame(width: 10, height: 10)
                            .overlay {
                                if isFuture, isInYear {
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .stroke(AppTheme.border, style: StrokeStyle(lineWidth: 1, dash: [2]))
                                } else if calendar.isDate(date, inSameDayAs: today), isInYear {
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .stroke(AppTheme.textPrimary, lineWidth: 1.5)
                                }
                            }
                            .padding(5)
                            .contentShape(Rectangle())
                            .opacity(isInYear ? 1 : 0)
                    }
                }
                .frame(height: 92)
                .padding(.vertical, 2)
            }

            HStack {
                Text("Jan")
                Spacer()
                Text("Dec")
            }
            .font(AppTheme.sans(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .appCard()
    }

    private func completion(on date: Date) -> HabitCompletion? {
        completionMap[calendar.startOfDay(for: date)]
    }
}

private struct HabitCardHeader: View {
    let habit: Habit
    let subtitle: String
    let trailingValue: String?
    let trailingLabel: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(habit.emojiOrIcon) \(habit.name)")
                    .font(AppTheme.serif(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(AppTheme.sans(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if let trailingValue, let trailingLabel {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(trailingValue)
                        .font(AppTheme.sans(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text(trailingLabel)
                        .font(AppTheme.sans(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }
}

private struct TrackerWeekSummary {
    let completed: Int
    let eligible: Int

    var percentage: Int {
        Int((Double(completed) / Double(max(eligible, 1)) * 100).rounded())
    }
}

private struct TrackerPeriod {
    let scope: TrackerScope
    let anchor: Date
    let calendar: Calendar
    let today: Date

    var start: Date {
        switch scope {
        case .week:
            calendar.startOfWeek(containing: anchor)
        case .month:
            calendar.startOfMonth(containing: anchor)
        case .year:
            calendar.startOfYear(containing: anchor)
        }
    }

    var end: Date {
        switch scope {
        case .week:
            calendar.endOfWeek(containing: anchor)
        case .month:
            calendar.endOfMonth(containing: anchor)
        case .year:
            calendar.endOfYear(containing: anchor)
        }
    }

    var kicker: String {
        switch scope {
        case .week:
            return calendar.isDate(start, inSameDayAs: calendar.startOfWeek(containing: today)) ? "This week" : "Week of"
        case .month:
            return calendar.isDate(anchor, equalTo: today, toGranularity: .month) ? "This month" : "Month"
        case .year:
            return calendar.isDate(anchor, equalTo: today, toGranularity: .year) ? "This year" : "Year"
        }
    }

    var title: String {
        switch scope {
        case .week:
            let startMonth = start.formatted(.dateTime.month(.abbreviated))
            let endMonth = end.formatted(.dateTime.month(.abbreviated))
            let startDay = calendar.component(.day, from: start)
            let endDay = calendar.component(.day, from: end)
            if calendar.isDate(start, equalTo: end, toGranularity: .month) {
                return "\(startMonth) \(startDay)-\(endDay)"
            }
            return "\(startMonth) \(startDay) - \(endMonth) \(endDay)"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .year:
            return anchor.formatted(.dateTime.year())
        }
    }

    func shifted(by direction: Int) -> Date {
        switch scope {
        case .week:
            calendar.date(byAdding: .day, value: 7 * direction, to: anchor) ?? anchor
        case .month:
            calendar.date(byAdding: .month, value: direction, to: anchor) ?? anchor
        case .year:
            calendar.date(byAdding: .year, value: direction, to: anchor) ?? anchor
        }
    }
}

private func strokeColor(isDue: Bool, isFuture: Bool, isComplete: Bool, isToday: Bool) -> Color {
    if isComplete {
        return AppTheme.accent
    }
    if isFuture {
        return AppTheme.border
    }
    if !isDue {
        return Color(red: 0.91, green: 0.89, blue: 0.85)
    }
    if isToday {
        return AppTheme.accent
    }
    return AppTheme.border
}

private func shortWeekdayLabel(for date: Date) -> String {
    let symbols = Calendar.autoupdatingCurrent.veryShortWeekdaySymbolsMondayFirst
    guard let weekday = Weekday(date: date, calendar: .autoupdatingCurrent) else { return "?" }
    let mondayFirstIndex = (weekday.rawValue + 5) % 7
    guard symbols.indices.contains(mondayFirstIndex) else { return "?" }
    return symbols[mondayFirstIndex]
}

func habitScheduleLabel(_ schedule: HabitSchedule) -> String {
    switch schedule {
    case .daily:
        return "Daily"
    case .weekdays(let days):
        return days.sorted().map(\.label).joined(separator: " · ")
    }
}

private func bestStreak(for habit: Habit, through endDate: Date, calendar: Calendar, completions: [HabitCompletion]) -> Int {
    let completionLookup = Dictionary(uniqueKeysWithValues: completions.map { (calendar.startOfDay(for: $0.date), $0) })
    let startDate = calendar.startOfYear(containing: endDate)

    var best = 0
    var current = 0

    for date in calendar.days(from: startDate, through: endDate) {
        guard habit.isDue(on: date, calendar: calendar) else { continue }
        if completionLookup[calendar.startOfDay(for: date)]?.isCompleted(for: habit) == true {
            current += 1
            best = max(best, current)
        } else {
            current = 0
        }
    }

    return best
}

extension Calendar {
    var veryShortWeekdaySymbolsMondayFirst: [String] {
        let symbols = veryShortWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        return Array(symbols[1...6]) + [symbols[0]]
    }

    func startOfWeek(containing date: Date) -> Date {
        let normalized = startOfDay(for: date)
        let weekday = component(.weekday, from: normalized)
        let offset = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -offset, to: normalized) ?? normalized
    }

    func endOfWeek(containing date: Date) -> Date {
        self.date(byAdding: .day, value: 6, to: startOfWeek(containing: date)) ?? date
    }

    func startOfMonth(containing date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }

    func endOfMonth(containing date: Date) -> Date {
        let start = startOfMonth(containing: date)
        let next = self.date(byAdding: .month, value: 1, to: start) ?? start
        return self.date(byAdding: .day, value: -1, to: next) ?? date
    }

    func startOfYear(containing date: Date) -> Date {
        self.date(from: dateComponents([.year], from: date)) ?? date
    }

    func endOfYear(containing date: Date) -> Date {
        let start = startOfYear(containing: date)
        let next = self.date(byAdding: .year, value: 1, to: start) ?? start
        return self.date(byAdding: .day, value: -1, to: next) ?? date
    }

    func days(from start: Date, through end: Date) -> [Date] {
        guard start <= end else { return [] }

        var dates: [Date] = []
        var cursor = startOfDay(for: start)
        let finalDate = startOfDay(for: end)

        while cursor <= finalDate {
            dates.append(cursor)
            guard let next = self.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return dates
    }

    func monthGridDates(for anchor: Date) -> [Date] {
        let monthStart = startOfMonth(containing: anchor)
        let monthEnd = endOfMonth(containing: anchor)
        let gridStart = startOfWeek(containing: monthStart)
        let gridEnd = endOfWeek(containing: monthEnd)
        return days(from: gridStart, through: gridEnd)
    }

    func yearGridDates(for anchor: Date) -> [Date] {
        let yearStart = startOfYear(containing: anchor)
        let yearEnd = endOfYear(containing: anchor)
        let gridStart = startOfWeek(containing: yearStart)
        let gridEnd = endOfWeek(containing: yearEnd)
        return days(from: gridStart, through: gridEnd)
    }
}
