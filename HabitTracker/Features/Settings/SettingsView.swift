import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        List {
            Section("Account") {
                Text(environment.currentUser?.email ?? "Not signed in")
                Button("Restore Purchases") {
                    Task { await environment.restorePurchases() }
                }
                Button("Sign Out", role: .destructive) {
                    Task { await environment.signOut() }
                }
            }

            Section("Notifications") {
                Button("Enable Reminder Permission") {
                    Task { _ = try? await environment.reminderService.requestAuthorization() }
                }
            }

            Section("Release Readiness") {
                Text("StoreKit 2 unlock, Supabase REST auth, local JSON cache, and widget sync are scaffolded.")
                Text("Next step after opening in Xcode: replace bundle ids, app group, Supabase keys, and product id.")
            }
            .foregroundStyle(AppTheme.textSecondary)
        }
        .navigationTitle("Settings")
    }
}
