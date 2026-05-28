import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingHabitManager = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(AppTheme.serif(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Keep reminders, account access, and your daily setup feeling simple.")
                        .font(AppTheme.sans(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Account")
                        .font(AppTheme.sans(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)

                    Text(environment.currentUser?.email ?? "Not signed in")
                        .font(AppTheme.serif(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Button("Sign Out", role: .destructive) {
                        Task { await environment.signOut() }
                    }
                    .font(AppTheme.sans(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Notifications")
                        .font(AppTheme.sans(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)

                    Text("Enable reminders so your check-ins show up at the right moment.")
                        .font(AppTheme.sans(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)

                    Button {
                        Task {
                            await environment.enableReminderPermissions()
                        }
                    } label: {
                        Text("Enable Reminder Permission")
                            .font(AppTheme.sans(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Library")
                        .font(AppTheme.sans(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)

                    Text("\(environment.habits.filter { !$0.isArchived }.count) active habits")
                        .font(AppTheme.serif(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("\(environment.completions.count) total check-ins recorded")
                        .font(AppTheme.sans(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)

                    Button("Manage Habits") {
                        showingHabitManager = true
                    }
                    .font(AppTheme.sans(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(fill: AppTheme.surface)
            }
            .padding(20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingHabitManager) {
            NavigationStack {
                HabitManagerView()
            }
        }
    }
}
