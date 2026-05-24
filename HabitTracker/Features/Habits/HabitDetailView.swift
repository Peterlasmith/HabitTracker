import SwiftUI

struct HabitDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingEditor = false
    let habit: Habit

    var body: some View {
        let history = environment.completionHistory(for: habit)
        let streak = StreakCalculator.currentStreak(for: habit, completions: history)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(habit.emojiOrIcon) \(habit.name)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("\(streak) day streak")
                        .font(.headline)
                        .foregroundStyle(habit.color.color)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("History")
                        .font(.headline)
                    ForEach(history.prefix(14)) { completion in
                        HStack {
                            Text(completion.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\(completion.count)")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    if history.isEmpty {
                        Text("No completions yet.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .appCard()
            }
            .padding(20)
        }
        .navigationTitle("Habit")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
                Button(role: .destructive) {
                    Task { await environment.archiveHabit(habit) }
                } label: {
                    Image(systemName: "archivebox")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HabitEditorView(existingHabit: habit)
            }
        }
    }
}
