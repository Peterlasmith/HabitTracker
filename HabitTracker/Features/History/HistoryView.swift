import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private let calendar = Calendar.autoupdatingCurrent
    private let windowLength = 14

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
        HStack(spacing: 10) {
            trendStatCard(
                title: "Last 14 days",
                value: "\(snapshot.currentCompletionRate)%",
                detail: "\(snapshot.currentCompleted) of \(max(snapshot.currentEligible, 1)) check-ins"
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func trendChart(snapshot: TrendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily completion trend")
                .font(AppTheme.sans(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(snapshot.days) { day in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(AppTheme.surfaceStrong)
                                .frame(height: 104)

                            Capsule()
                                .fill(barColor(for: day.rate))
                                .frame(height: max(CGFloat(day.rate) * 104, day.eligible > 0 ? 10 : 4))
                        }

                        Text(shortLabel(for: day.date))
                            .font(AppTheme.sans(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(day.eligible == 0 ? "0" : "\(Int((day.rate * 100).rounded()))")
                            .font(AppTheme.sans(size: 10))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("Each bar shows the share of scheduled check-ins you completed that day.")
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "E"
        return formatter.string(from: date).prefix(1).uppercased()
    }

    private func barColor(for rate: Double) -> Color {
        if rate >= 0.8 { return AppTheme.success }
        if rate >= 0.5 { return AppTheme.accent }
        if rate > 0 { return AppTheme.accentSoft }
        return AppTheme.border
    }

    private func trendSnapshot(for habits: [Habit], referenceDate: Date) -> TrendSnapshot {
        let currentWindowEnd = referenceDate
        let currentWindowStart = calendar.date(byAdding: .day, value: -(windowLength - 1), to: currentWindowEnd) ?? currentWindowEnd
        let previousWindowEnd = calendar.date(byAdding: .day, value: -1, to: currentWindowStart) ?? currentWindowStart
        let previousWindowStart = calendar.date(byAdding: .day, value: -(windowLength - 1), to: previousWindowEnd) ?? previousWindowEnd

        let currentDays = buildDailyTrend(from: currentWindowStart, through: currentWindowEnd, habits: habits)
        let previousDays = buildDailyTrend(from: previousWindowStart, through: previousWindowEnd, habits: habits)

        let currentCompleted = currentDays.reduce(0) { $0 + $1.completed }
        let currentEligible = currentDays.reduce(0) { $0 + $1.eligible }
        let previousCompleted = previousDays.reduce(0) { $0 + $1.completed }
        let previousEligible = previousDays.reduce(0) { $0 + $1.eligible }
        let currentRate = completionRate(completed: currentCompleted, eligible: currentEligible)
        let previousRate = completionRate(completed: previousCompleted, eligible: previousEligible)

        return TrendSnapshot(
            days: currentDays,
            currentCompleted: currentCompleted,
            currentEligible: currentEligible,
            currentCompletionRate: currentRate,
            previousCompletionRate: previousRate
        )
    }

    private func buildDailyTrend(from start: Date, through end: Date, habits: [Habit]) -> [DailyTrendPoint] {
        calendar.days(from: start, through: end).map { date in
            var completed = 0
            var eligible = 0

            for habit in habits where habit.isDue(on: date, calendar: calendar) {
                eligible += 1
                if completion(for: habit, on: date)?.isCompleted(for: habit) == true {
                    completed += 1
                }
            }

            return DailyTrendPoint(date: date, completed: completed, eligible: eligible)
        }
    }

    private func completionRate(completed: Int, eligible: Int) -> Int {
        guard eligible > 0 else { return 0 }
        return Int((Double(completed) / Double(eligible) * 100).rounded())
    }

    private func completion(for habit: Habit, on date: Date) -> HabitCompletion? {
        environment.completion(for: habit, on: date)
    }
}

private struct TrendSnapshot {
    let days: [DailyTrendPoint]
    let currentCompleted: Int
    let currentEligible: Int
    let currentCompletionRate: Int
    let previousCompletionRate: Int

    var delta: Int {
        currentCompletionRate - previousCompletionRate
    }

    var momentumLabel: String {
        if delta > 0 { return "+\(delta) pts" }
        if delta < 0 { return "\(delta) pts" }
        return "Flat"
    }

    var momentumDetail: String {
        if delta > 0 { return "Up from \(previousCompletionRate)% in the prior 14 days" }
        if delta < 0 { return "Down from \(previousCompletionRate)% in the prior 14 days" }
        return "Matching the prior 14 days at \(previousCompletionRate)%"
    }

    var subtitle: String {
        if currentEligible == 0 {
            return "Once you start checking in, this screen will show how your consistency is moving."
        }

        if delta > 0 {
            return "Your consistency is building over the last two weeks."
        }

        if delta < 0 {
            return "Your recent pace is softer than the two weeks before it."
        }

        return "Your rhythm has held steady across the last two weeks."
    }
}

private struct DailyTrendPoint: Identifiable {
    let date: Date
    let completed: Int
    let eligible: Int

    var id: Date { date }

    var rate: Double {
        guard eligible > 0 else { return 0 }
        return Double(completed) / Double(eligible)
    }
}
