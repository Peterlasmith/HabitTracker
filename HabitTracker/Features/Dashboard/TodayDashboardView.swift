import SwiftUI

struct TodayDashboardView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingEditor = false

    var body: some View {
        let todayHabits = environment.todayHabits()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(todayHabits: todayHabits)

                if todayHabits.isEmpty {
                    emptyState
                } else {
                    ForEach(todayHabits) { item in
                        NavigationLink {
                            HabitDetailView(habit: item.habit)
                        } label: {
                            HabitProgressCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HabitEditorView()
            }
        }
    }

    private func header(todayHabits: [HabitWithProgress]) -> some View {
        let completed = todayHabits.filter(\.isComplete).count
        let ratio = todayHabits.isEmpty ? 0 : Double(completed) / Double(todayHabits.count)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Today’s rhythm")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text(todayHabits.isEmpty ? "Create your first habit to get started." : "\(completed) of \(todayHabits.count) complete")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            ProgressView(value: ratio)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
        }
        .appCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No habits scheduled for today.")
                .font(.headline)
            Text("Add a habit with a daily or weekday schedule to populate the dashboard and widget.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

private struct HabitProgressCard: View {
    @EnvironmentObject private var environment: AppEnvironment
    let item: HabitWithProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(item.habit.emojiOrIcon) \(item.habit.name)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(StreakCalculator.currentStreak(for: item.habit, completions: environment.completionHistory(for: item.habit))) day streak")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(item.isComplete ? AppTheme.success : AppTheme.textSecondary)
            }

            ProgressView(value: item.progress)
                .tint(item.habit.color.color)

            Button {
                Task {
                    let nextCount: Int
                    switch item.habit.targetType {
                    case .binary:
                        nextCount = item.isComplete ? 0 : 1
                    case .count:
                        nextCount = min((item.completion?.count ?? 0) + 1, item.habit.targetCount)
                    }
                    await environment.recordCompletion(for: item.habit, count: nextCount)
                }
            } label: {
                Text(item.isComplete ? "Completed" : "Check In")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isComplete ? .white : AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(item.isComplete ? item.habit.color.color : Color.white.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .appCard()
    }
}
