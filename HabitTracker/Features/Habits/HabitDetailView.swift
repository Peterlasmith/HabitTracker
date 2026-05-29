import SwiftUI

struct HabitDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingArchiveConfirmation = false

    let habit: Habit

    var body: some View {
        let history = environment.completionHistory(for: habit)
        let streak = StreakCalculator.currentStreak(for: habit, completions: history)
        let progress = habit.periodProgress(referenceDate: .now, completions: history)
        let recordedCount = history.reduce(0) { partialResult, completion in
            partialResult + max(completion.count, 0)
        }
        let streakLabel = habit.targetType == .binary ? "days" : "weeks"

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(habit.emojiOrIcon) \(habit.name)")
                        .font(AppTheme.serif(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(habitScheduleLabel(habit.schedule))
                        .font(AppTheme.sans(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 10) {
                        detailStat(title: "Current streak", value: "\(streak) \(streakLabel)")
                        detailStat(title: habit.targetType == .binary ? "Recorded" : "This week", value: habit.targetType == .binary ? "\(recordedCount)" : "\(progress.completedCount)/\(habit.targetCount)")
                    }
                }
                .appCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(AppTheme.sans(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)

                    detailRow(label: "Target", value: habitTargetLabel)
                    detailRow(label: "Reminder", value: reminderLabel)
                    detailRow(label: "Created", value: habit.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                .appCard(fill: AppTheme.surface)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent history")
                        .font(AppTheme.sans(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)

                    if history.isEmpty {
                        Text("No completions yet.")
                            .font(AppTheme.sans(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(history.prefix(14)) { completion in
                            HStack {
                                Text(completion.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppTheme.sans(size: 14))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Spacer()

                                Text(completionLabel(completion))
                                    .font(AppTheme.sans(size: 13, weight: .semibold))
                                    .foregroundStyle(completion.count > 0 ? AppTheme.success : AppTheme.textSecondary)
                            }
                        }
                    }
                }
                .appCard()
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }

                Button("Archive") {
                    showingArchiveConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Archive \(habit.name)?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Habit") {
                Task {
                    await environment.archiveHabit(habit)
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the habit from your active lists and keeps its history in Archived.")
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HabitEditorView(existingHabit: habit)
            }
        }
    }

    private var habitTargetLabel: String {
        switch habit.targetType {
        case .binary:
            return "Complete once"
        case .count:
            return "\(habit.targetCount) times per week"
        }
    }

    private var reminderLabel: String {
        guard let reminderTime = habit.reminderTime,
              let date = Calendar.current.date(from: reminderTime) else {
            return "Off"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.sans(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            Text(value)
                .font(AppTheme.serif(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.sans(size: 14))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Text(value)
                .font(AppTheme.sans(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func completionLabel(_ completion: HabitCompletion) -> String {
        switch habit.targetType {
        case .binary:
            return completion.count > 0 ? "Done" : "Skipped"
        case .count:
            return "\(completion.count) check-in\(completion.count == 1 ? "" : "s")"
        }
    }
}
