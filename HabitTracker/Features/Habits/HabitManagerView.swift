import SwiftUI

struct HabitManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    @State private var selectedHabitID: Habit.ID?
    @State private var habitPendingDeletion: Habit?

    private var habits: [Habit] {
        environment.habits.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manage habits")
                        .font(AppTheme.serif(size: 32, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Edit names, schedules, or reminders, and permanently delete habits you no longer want to track.")
                        .font(AppTheme.sans(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if habits.isEmpty {
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
                        ForEach(habits) { habit in
                            habitRow(habit)
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
        .sheet(
            isPresented: Binding(
                get: { selectedHabitID != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedHabitID = nil
                    }
                }
            )
        ) {
            NavigationStack {
                HabitEditorView(existingHabitID: selectedHabitID)
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
            Text("This permanently deletes the habit and all of its history.")
        }
    }

    private func habitRow(_ habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    editButton(for: habit)
                    deleteButton(for: habit)
                }

                VStack(alignment: .leading, spacing: 10) {
                    editButton(for: habit)
                    deleteButton(for: habit)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: AppTheme.surfaceStrong, padding: 14, cornerRadius: 20)
    }

    private func editButton(for habit: Habit) -> some View {
        Button("Edit") {
            selectedHabitID = habit.id
        }
        .font(AppTheme.sans(size: 13, weight: .semibold))
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .buttonStyle(.plain)
    }

    private func deleteButton(for habit: Habit) -> some View {
        Button("Delete", role: .destructive) {
            habitPendingDeletion = habit
        }
        .font(AppTheme.sans(size: 13, weight: .semibold))
        .foregroundStyle(AppTheme.error)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .buttonStyle(.plain)
    }
}
