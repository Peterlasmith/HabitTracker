import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingHabitManager = false
    @State private var showingDeleteAccountSheet = false

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

                    Button("Delete Account", role: .destructive) {
                        environment.errorMessage = nil
                        showingDeleteAccountSheet = true
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
        .sheet(isPresented: $showingDeleteAccountSheet) {
            DeleteAccountView(isPresented: $showingDeleteAccountSheet)
                .environmentObject(environment)
        }
    }
}

private struct DeleteAccountView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var isPresented: Bool
    @State private var password = ""

    private var canDelete: Bool {
        !environment.isBusy && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Delete Account")
                            .font(AppTheme.serif(size: 32, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Are you sure? This permanently deletes your account instead of simply signing you out or temporarily disabling access.")
                            .font(AppTheme.sans(size: 15))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        consequenceRow("Your sign-in account is removed from Supabase Auth.")
                        consequenceRow("Your habits, check-ins, streak history, and assistant access tokens are permanently erased.")
                        consequenceRow("Cached app data, widget summaries, and reminder notifications on this device are cleared immediately.")
                    }
                    .appCard(fill: AppTheme.surface)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Confirm with your password")
                            .font(AppTheme.sans(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        SecureField("Enter your password", text: $password)
                            .textContentType(.password)
                            .appInput()
                    }
                    .appCard(fill: AppTheme.surfaceStrong, padding: 18, cornerRadius: 22)

                    if let errorMessage = environment.errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.sans(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.errorBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button(role: .destructive, action: deleteAccount) {
                            HStack(spacing: 10) {
                                if environment.isBusy {
                                    ProgressView()
                                        .tint(.white)
                                }

                                Text(environment.isBusy ? "Deleting..." : "Delete Account Forever")
                                    .font(AppTheme.sans(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canDelete ? AppTheme.error : AppTheme.error.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canDelete)

                        Button("Cancel") {
                            environment.errorMessage = nil
                            isPresented = false
                        }
                        .font(AppTheme.sans(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        environment.errorMessage = nil
                        isPresented = false
                    }
                }
            }
        }
    }

    private func consequenceRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
                .padding(.top, 2)

            Text(text)
                .font(AppTheme.sans(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deleteAccount() {
        environment.errorMessage = nil
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let didDelete = await environment.deleteAccount(currentPassword: trimmedPassword)
            if didDelete {
                await MainActor.run {
                    isPresented = false
                }
            }
        }
    }
}
