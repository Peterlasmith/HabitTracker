import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private let calendar = Calendar.autoupdatingCurrent
    private let windowLength = 8

    var body: some View {
        let habits = activeHabits
        let snapshot = trendSnapshot(for: habits, referenceDate: calendar.startOfDay(for: .now))

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(snapshot: snapshot)

                if habits.isEmpty {
                    emptyState(
                        title: "No trend data yet",
                        message: "Add your first habit and your completion patterns will start showing up here."
                    )
                } else {
                    overviewCards(snapshot: snapshot)
                    trendChart(snapshot: snapshot)
                }
            }
            .padding(20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeHabits: [Habit] {
        environment.habits
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func header(snapshot: TrendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trends")
                .font(AppTheme.serif(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(snapshot.subtitle)
                .font(AppTheme.sans(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func overviewCards(snapshot: TrendSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            trendStatCard(
                title: "Last 8 weeks",
                value: "\(snapshot.currentCompletionRate)%",
                detail: snapshot.currentDetail
            )

            trendStatCard(
                title: "Momentum",
                value: snapshot.momentumLabel,
                detail: snapshot.momentumDetail
            )
        }
    }

    private func trendStatCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.sans(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            Text(value)
                .font(AppTheme.sans(size: 28, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)

            Text(detail)
                .font(AppTheme.sans(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .appCard()
    }

    private func trendChart(snapshot: TrendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly progress trend")
                .font(AppTheme.sans(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(snapshot.weeks) { week in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(AppTheme.surfaceStrong)
                                .frame(height: 104)

                            Capsule()
                                .fill(barColor(for: week.rate))
                                .frame(height: max(CGFloat(week.rate) * 104, week.eligibleUnits > 0 ? 10 : 4))
                        }

                        Text(shortLabel(for: week.weekStart))
                            .font(AppTheme.sans(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        Text(week.eligibleUnits == 0 ? "0" : "\(Int((week.rate * 100).rounded()))")
                            .font(AppTheme.sans(size: 10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("Binary habits contribute due-day completion. Count habits contribute weekly progress toward their target.")
                .font(AppTheme.sans(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .appCard()
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.serif(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(AppTheme.sans(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func shortLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func barColor(for rate: Double) -> Color {
        if rate >= 0.8 { return AppTheme.success }
        if rate >= 0.5 { return AppTheme.accent }
        if rate > 0 { return AppTheme.accentSoft }
        return AppTheme.border
    }

    private func trendSnapshot(for habits: [Habit], referenceDate: Date) -> TrendSnapshot {
        let currentWindowEnd = calendar.startOfWeek(containing: referenceDate)
        let currentWindowStart = calendar.date(byAdding: .day, value: -7 * (windowLength - 1), to: currentWindowEnd) ?? currentWindowEnd
        let previousWindowEnd = calendar.date(byAdding: .day, value: -7, to: currentWindowStart) ?? currentWindowStart
        let previousWindowStart = calendar.date(byAdding: .day, value: -7 * (windowLength - 1), to: previousWindowEnd) ?? previousWindowEnd

        let currentWeeks = buildWeeklyTrend(from: currentWindowStart, through: currentWindowEnd, habits: habits, referenceDate: referenceDate)
        let previousWeeks = buildWeeklyTrend(from: previousWindowStart, through: previousWindowEnd, habits: habits, referenceDate: referenceDate)

        let currentCompleted = currentWeeks.reduce(0.0) { $0 + $1.completedUnits }
        let currentEligible = currentWeeks.reduce(0) { $0 + $1.eligibleUnits }
        let previousCompleted = previousWeeks.reduce(0.0) { $0 + $1.completedUnits }
        let previousEligible = previousWeeks.reduce(0) { $0 + $1.eligibleUnits }
        let currentRate = completionRate(completed: currentCompleted, eligible: currentEligible)
        let previousRate = completionRate(completed: previousCompleted, eligible: previousEligible)

        return TrendSnapshot(
            weeks: currentWeeks,
            currentCompleted: currentCompleted,
            currentEligible: currentEligible,
            currentCompletionRate: currentRate,
            previousCompletionRate: previousRate
        )
    }

    private func buildWeeklyTrend(from start: Date, through end: Date, habits: [Habit], referenceDate: Date) -> [WeeklyTrendPoint] {
        var weeks: [WeeklyTrendPoint] = []
        var cursor = calendar.startOfWeek(containing: start)
        let finalWeek = calendar.startOfWeek(containing: end)

        while cursor <= finalWeek {
            let weekEnd = min(calendar.endOfWeek(containing: cursor), referenceDate)
            let weekDates = calendar.days(from: cursor, through: weekEnd)
            var completedUnits = 0.0
            var eligibleUnits = 0

            for habit in habits {
                let completions = environment.completionHistory(for: habit)
                switch habit.targetType {
                case .binary:
                    for date in weekDates where habit.isDue(on: date, calendar: calendar) {
                        eligibleUnits += 1
                        if habit.isComplete(referenceDate: date, completions: completions, calendar: calendar) {
                            completedUnits += 1
                        }
                    }
                case .count:
                    guard weekDates.contains(where: { habit.isDue(on: $0, calendar: calendar) }) else { continue }
                    eligibleUnits += 1
                    completedUnits += habit.periodProgress(referenceDate: cursor, completions: completions, calendar: calendar).progress
                }
            }

            weeks.append(
                WeeklyTrendPoint(
                    weekStart: cursor,
                    completedUnits: completedUnits,
                    eligibleUnits: eligibleUnits
                )
            )

            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = nextWeek
        }

        return weeks
    }

    private func completionRate(completed: Double, eligible: Int) -> Int {
        guard eligible > 0 else { return 0 }
        return Int((completed / Double(eligible) * 100).rounded())
    }
}

private struct TrendSnapshot {
    let weeks: [WeeklyTrendPoint]
    let currentCompleted: Double
    let currentEligible: Int
    let currentCompletionRate: Int
    let previousCompletionRate: Int

    var delta: Int {
        currentCompletionRate - previousCompletionRate
    }

    var currentDetail: String {
        "\(Int(currentCompleted.rounded())) of \(max(currentEligible, 1)) goal units met or in progress"
    }

    var momentumLabel: String {
        if delta > 0 { return "+\(delta) pts" }
        if delta < 0 { return "\(delta) pts" }
        return "Flat"
    }

    var momentumDetail: String {
        if delta > 0 { return "Up from \(previousCompletionRate)% in the prior 8 weeks" }
        if delta < 0 { return "Down from \(previousCompletionRate)% in the prior 8 weeks" }
        return "Matching the prior 8 weeks at \(previousCompletionRate)%"
    }

    var subtitle: String {
        if currentEligible == 0 {
            return "Once you start checking in, this screen will show how your consistency is moving."
        }

        if delta > 0 {
            return "Your weekly consistency is building."
        }

        if delta < 0 {
            return "Your recent pace is softer than the stretch before it."
        }

        return "Your rhythm has held steady lately."
    }
}

private struct WeeklyTrendPoint: Identifiable {
    let weekStart: Date
    let completedUnits: Double
    let eligibleUnits: Int

    var id: Date { weekStart }

    var rate: Double {
        guard eligibleUnits > 0 else { return 0 }
        return completedUnits / Double(eligibleUnits)
    }
}
