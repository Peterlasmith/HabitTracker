import SwiftUI

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    let existingHabit: Habit?

    @State private var name = ""
    @State private var emoji = "🌿"
    @State private var color: HabitColor = .teal
    @State private var targetType: HabitTargetType = .binary
    @State private var targetCount = 1
    @State private var isDaily = true
    @State private var selectedWeekdays = Set(Weekday.allCases)
    @State private var remindersEnabled = false
    @State private var reminderDate = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? .now

    init(existingHabit: Habit? = nil) {
        self.existingHabit = existingHabit
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Habit name", text: $name)
                TextField("Emoji or symbol", text: $emoji)

                Picker("Color", selection: $color) {
                    ForEach(HabitColor.allCases) { color in
                        Text(color.rawValue.capitalized).tag(color)
                    }
                }
            }

            Section("Goal") {
                Picker("Target type", selection: $targetType) {
                    ForEach(HabitTargetType.allCases) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }

                if targetType == .count {
                    Stepper("Target count: \(targetCount)", value: $targetCount, in: 1...20)
                }
            }

            Section("Schedule") {
                Toggle("Every day", isOn: $isDaily)
                if !isDaily {
                    weekdayPicker
                }
            }

            Section("Reminder") {
                Toggle("Enable reminder", isOn: $remindersEnabled)
                if remindersEnabled {
                    DatePicker("Time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                }
            }
        }
        .navigationTitle(existingHabit == nil ? "New Habit" : "Edit Habit")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        await saveHabit()
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: populateIfNeeded)
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(Weekday.allCases) { day in
                Button(day.label) {
                    if selectedWeekdays.contains(day) {
                        selectedWeekdays.remove(day)
                    } else {
                        selectedWeekdays.insert(day)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedWeekdays.contains(day) ? AppTheme.accent : .gray.opacity(0.3))
            }
        }
    }

    private func populateIfNeeded() {
        guard let existingHabit else { return }
        name = existingHabit.name
        emoji = existingHabit.emojiOrIcon
        color = existingHabit.color
        targetType = existingHabit.targetType
        targetCount = existingHabit.targetCount
        remindersEnabled = existingHabit.reminderTime != nil
        if let reminderTime = existingHabit.reminderTime,
           let date = Calendar.current.date(from: reminderTime) {
            reminderDate = date
        }

        switch existingHabit.schedule {
        case .daily:
            isDaily = true
            selectedWeekdays = Set(Weekday.allCases)
        case .weekdays(let days):
            isDaily = false
            selectedWeekdays = days
        }
    }

    private func saveHabit() async {
        guard let currentUser = environment.currentUser else { return }
        let timeComponents = remindersEnabled ? Calendar.current.dateComponents([.hour, .minute], from: reminderDate) : nil
        let schedule: HabitSchedule = isDaily ? .daily : .weekdays(selectedWeekdays.isEmpty ? Set([.monday]) : selectedWeekdays)

        let habit = Habit(
            id: existingHabit?.id ?? UUID(),
            userId: currentUser.id,
            name: name,
            emojiOrIcon: emoji,
            color: color,
            schedule: schedule,
            targetType: targetType,
            targetCount: targetType == .binary ? 1 : targetCount,
            reminderTime: timeComponents,
            createdAt: existingHabit?.createdAt ?? .now,
            archivedAt: existingHabit?.archivedAt
        )

        if remindersEnabled {
            environment.analyticsService.track(.enabledReminder)
        }

        await environment.createOrUpdateHabit(habit)
    }
}
