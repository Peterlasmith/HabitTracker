import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            background

            switch environment.phase {
            case .launching:
                ProgressView("Loading your habits...")
            case .onboarding:
                OnboardingView()
            case .authentication:
                AuthView()
            case .paywall:
                PurchaseView()
            case .ready:
                MainAppView()
            }
        }
        .overlay(alignment: .top) {
            if let errorMessage = environment.errorMessage {
                Text(errorMessage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.94, blue: 0.86),
                Color(red: 0.88, green: 0.95, blue: 0.91)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
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
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(AppTheme.accent)
    }
}
