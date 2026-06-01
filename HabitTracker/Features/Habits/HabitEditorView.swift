import SwiftUI

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    let existingHabitID: Habit.ID?

    @State private var name = ""
    @State private var emoji = "🌿"
    @State private var color: HabitColor = .teal
    @State private var isDaily = true
    @State private var selectedWeekdays = Set(Weekday.allCases)
    @State private var remindersEnabled = false
    @State private var reminderDate = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? .now
    @State private var inlineErrorMessage: String?
    @State private var isSaving = false
    @State private var hasPopulatedExistingHabit = false

    init(existingHabitID: Habit.ID? = nil) {
        self.existingHabitID = existingHabitID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                previewCard
                if let inlineErrorMessage {
                    inlineErrorCard(message: inlineErrorMessage)
                }
                identitySection
                goalSection
                scheduleSection
                reminderSection
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .disabled(isSaving)
        .scrollIndicators(.hidden)
        .navigationTitle(existingHabitID == nil ? "New Habit" : "Edit Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await saveHabit()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(AppTheme.accent)
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: populateIfNeeded)
        .onChange(of: existingHabitID) { _, _ in
            hasPopulatedExistingHabit = false
            populateIfNeeded()
        }
    }

    private var existingHabit: Habit? {
        guard let existingHabitID else { return nil }
        return environment.habit(id: existingHabitID)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(emoji) \(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New habit" : name)")
                .font(AppTheme.serif(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(previewSubtitle)
                .font(AppTheme.sans(size: 14))
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 10) {
                Circle()
                    .fill(color.color)
                    .frame(width: 14, height: 14)

                Text("Complete once per scheduled day")
                    .font(AppTheme.sans(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func inlineErrorCard(message: String) -> some View {
        Text(message)
            .font(AppTheme.sans(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.errorBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var identitySection: some View {
        sectionCard(title: "Identity") {
            VStack(spacing: 12) {
                TextField("Habit name", text: $name)
                    .appInput()

                TextField("Emoji or symbol", text: $emoji)
                    .appInput()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(AppTheme.sans(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 10) {
                        ForEach(HabitColor.allCases) { swatch in
                            Button {
                                color = swatch
                            } label: {
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(color == swatch ? AppTheme.textPrimary : .clear, lineWidth: 2)
                                            .padding(-5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        sectionCard(title: "Goal") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Simple daily check-off")
                    .font(AppTheme.sans(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("A habit is either done or not done on each scheduled day.")
                    .font(AppTheme.sans(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var scheduleSection: some View {
        sectionCard(title: "Schedule") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Frequency", selection: $isDaily) {
                    Text("Daily").tag(true)
                    Text("Custom").tag(false)
                }
                .pickerStyle(.segmented)

                if !isDaily {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 84), spacing: 8)], spacing: 8) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                if selectedWeekdays.contains(day) {
                                    selectedWeekdays.remove(day)
                                } else {
                                    selectedWeekdays.insert(day)
                                }
                            } label: {
                                Text(day.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .font(AppTheme.sans(size: 14, weight: .semibold))
                            .foregroundStyle(selectedWeekdays.contains(day) ? .white : AppTheme.textPrimary)
                            .background(selectedWeekdays.contains(day) ? AppTheme.accent : AppTheme.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedWeekdays.contains(day) ? AppTheme.accent : AppTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private var reminderSection: some View {
        sectionCard(title: "Reminder") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable reminder", isOn: $remindersEnabled)
                    .font(AppTheme.sans(size: 16, weight: .medium))
                    .tint(AppTheme.accent)

                if remindersEnabled {
                    DatePicker("Time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                        .font(AppTheme.sans(size: 16))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }

    private var previewSubtitle: String {
        if isDaily {
            return "Shows up every day."
        }
        let selected = selectedWeekdays.sorted().map(\.label).joined(separator: ", ")
        return selected.isEmpty ? "Choose at least one day." : "Scheduled for \(selected)."
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(AppTheme.sans(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: AppTheme.surface)
    }

    private func populateIfNeeded() {
        guard !hasPopulatedExistingHabit else { return }
        guard let existingHabit else {
            hasPopulatedExistingHabit = true
            return
        }

        hasPopulatedExistingHabit = true
        name = existingHabit.name
        emoji = existingHabit.emojiOrIcon
        color = existingHabit.color
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard let habit = habitForSaving() else {
            inlineErrorMessage = existingHabitID == nil
                ? "Your session expired. Sign in again to create a habit."
                : "This habit is no longer available. Close this sheet and try again."
            return
        }

        if remindersEnabled {
            environment.analyticsService.track(.enabledReminder)
        }

        inlineErrorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await environment.createOrUpdateHabit(habit)
            dismiss()
        } catch {
            inlineErrorMessage = error.localizedDescription
        }
    }

    private func habitForSaving() -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let userId: UUID
        if let existingHabit {
            userId = existingHabit.userId
        } else if existingHabitID != nil {
            return nil
        } else if let currentUser = environment.currentUser {
            userId = currentUser.id
        } else {
            return nil
        }

        let timeComponents = remindersEnabled ? Calendar.current.dateComponents([.hour, .minute], from: reminderDate) : nil
        let schedule: HabitSchedule = isDaily ? .daily : .weekdays(selectedWeekdays.isEmpty ? Set([.monday]) : selectedWeekdays)

        return Habit(
            id: existingHabit?.id ?? UUID(),
            userId: userId,
            name: trimmedName,
            emojiOrIcon: emoji,
            color: color,
            schedule: schedule,
            targetType: .binary,
            targetCount: 1,
            targetPeriod: .day,
            reminderTime: timeComponents,
            createdAt: existingHabit?.createdAt ?? .now
        )
    }
}
