import SwiftUI

struct HabitDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    let habit: Habit

    var body: some View {
        let history = environment.completionHistory(for: habit)
        let streak = StreakCalculator.currentStreak(for: habit, completions: history)
        let completedCount = history.filter { $0.isCompleted(for: habit) }.count

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
                        detailStat(title: "Current streak", value: "\(streak) days")
                        detailStat(title: "Recorded", value: "\(completedCount)")
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
                                    .foregroundStyle(completion.isCompleted(for: habit) ? AppTheme.success : AppTheme.textSecondary)
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

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete \(habit.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Habit", role: .destructive) {
                Task {
                    await environment.deleteHabit(habit)
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes only this habit and its check-ins.")
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
            return "\(habit.targetCount) check-ins"
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
            return completion.isCompleted(for: habit) ? "Done" : "Skipped"
        case .count:
            return "\(completion.count) / \(habit.targetCount)"
        }
    }
}
