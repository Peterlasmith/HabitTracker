import SwiftUI

struct HabitManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    @State private var selectedHabit: Habit?
    @State private var habitPendingDeletion: Habit?

    private var activeHabits: [Habit] {
        environment.habits
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var archivedHabits: [Habit] {
        environment.habits
            .filter(\.isArchived)
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manage habits")
                        .font(AppTheme.serif(size: 32, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Edit names, schedules, or reminders, and remove habits you no longer want to track.")
                        .font(AppTheme.sans(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if activeHabits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No habits yet")
                            .font(AppTheme.serif(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Create a habit first, then come back here anytime to make quick changes.")
                            .font(AppTheme.sans(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(activeHabits) { habit in
                            habitRow(habit)
                        }
                    }
                }

                if !archivedHabits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Archived")
                            .font(AppTheme.sans(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1.1)

                        VStack(spacing: 10) {
                            ForEach(archivedHabits) { habit in
                                archivedHabitRow(habit)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Manage Habits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $selectedHabit) { habit in
            NavigationStack {
                HabitEditorView(existingHabit: habit)
            }
        }
        .confirmationDialog(
            habitPendingDeletion == nil ? "Delete habit" : "Delete \(habitPendingDeletion?.name ?? "habit")?",
            isPresented: Binding(
                get: { habitPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        habitPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Habit", role: .destructive) {
                guard let habit = habitPendingDeletion else { return }
                Task {
                    await environment.deleteHabit(habit)
                    habitPendingDeletion = nil
                }
            }

            Button("Cancel", role: .cancel) {
                habitPendingDeletion = nil
            }
        } message: {
            Text("This permanently removes only this habit and its check-ins.")
        }
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(habit.color.color)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(habit.emojiOrIcon) \(habit.name)")
                    .font(AppTheme.serif(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(habitScheduleLabel(habit.schedule))
                    .font(AppTheme.sans(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button("Edit") {
                selectedHabit = habit
            }
            .font(AppTheme.sans(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.border, lineWidth: 1)
            )

            Button("Delete", role: .destructive) {
                habitPendingDeletion = habit
            }
            .font(AppTheme.sans(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: AppTheme.surfaceStrong, padding: 14, cornerRadius: 20)
    }

    private func archivedHabitRow(_ habit: Habit) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(habit.color.color.opacity(0.55))
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(habit.emojiOrIcon) \(habit.name)")
                    .font(AppTheme.serif(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Archived")
                    .font(AppTheme.sans(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button("Restore") {
                Task {
                    await environment.restoreHabit(habit)
                }
            }
            .font(AppTheme.sans(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: AppTheme.surfaceStrong, padding: 14, cornerRadius: 20)
    }
}
