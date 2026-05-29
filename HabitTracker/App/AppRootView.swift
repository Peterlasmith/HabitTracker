import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            background

            switch environment.phase {
            case .launching:
                VStack(alignment: .leading, spacing: 14) {
                    Text("HabitClaw")
                        .font(AppTheme.serif(size: 30, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    ProgressView("Loading your habits...")
                        .tint(AppTheme.accent)
                        .font(AppTheme.sans(size: 16))
                }
                .frame(maxWidth: 320, alignment: .leading)
                .appCard()
            case .onboarding:
                OnboardingView()
            case .authentication:
                AuthView()
            case .accountDeleted:
                AccountDeletedView(email: environment.recentlyDeletedAccountEmail)
            case .ready:
                MainAppView()
            }
        }
        .overlay(alignment: .top) {
            if environment.phase != .authentication, let errorMessage = environment.errorMessage {
                Text(errorMessage)
                    .font(AppTheme.sans(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.error)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.light)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.92, blue: 0.86),
                AppTheme.background,
                Color(red: 0.91, green: 0.88, blue: 0.80)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.accentSoft)
                .frame(width: 220, height: 220)
                .blur(radius: 10)
                .offset(x: 70, y: -70)
        }
        .ignoresSafeArea()
    }
}

private struct AccountDeletedView: View {
    let email: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account deleted")
                .font(AppTheme.serif(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(AppTheme.sans(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppTheme.accent)

                Text("Returning to sign in...")
                    .font(AppTheme.sans(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .appCard()
    }

    private var message: String {
        if let email, !email.isEmpty {
            return "\(email) and its habit data have been permanently removed from HabitClaw."
        }

        return "Your HabitClaw account and its habit data have been permanently removed."
    }
}

private struct MainAppView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayDashboardView()
            }
            .tabItem {
                Label("Today", systemImage: "sun.max.fill")
            }

            NavigationStack {
                TrendsView()
            }
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
