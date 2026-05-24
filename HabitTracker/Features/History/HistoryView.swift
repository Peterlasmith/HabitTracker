import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        List {
            ForEach(environment.habits) { habit in
                let completions = environment.completionHistory(for: habit)
                Section("\(habit.emojiOrIcon) \(habit.name)") {
                    if completions.isEmpty {
                        Text("No completions yet.")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(completions.prefix(20)) { completion in
                            HStack {
                                Text(completion.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(completion.count)")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("History")
    }
}
