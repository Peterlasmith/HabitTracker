import SwiftUI
import UIKit

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
                Image(uiImage: tabSymbol(.habits))
                Text("Habits")
            }

            NavigationStack {
                BucketListView()
            }
            .tabItem {
                Image(uiImage: tabSymbol(.bucket))
                Text("Bucket")
            }

            NavigationStack {
                TrendsView()
            }
            .tabItem {
                Image(uiImage: tabSymbol(.trends))
                Text("Trends")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Image(uiImage: tabSymbol(.settings))
                Text("Settings")
            }
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func tabSymbol(_ icon: TabBarIcon) -> UIImage {
        let size = CGSize(width: 28, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.black.setStroke()

            let stroke = UIBezierPath()
            stroke.lineWidth = 1.8
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round

            switch icon {
            case .habits:
                stroke.move(to: CGPoint(x: 9.6, y: 5))
                stroke.addLine(to: CGPoint(x: 20, y: 5))
                stroke.move(to: CGPoint(x: 9.6, y: 11.5))
                stroke.addLine(to: CGPoint(x: 20, y: 11.5))
                stroke.move(to: CGPoint(x: 9.6, y: 18))
                stroke.addLine(to: CGPoint(x: 20, y: 18))
                stroke.stroke()

                circle(center: CGPoint(x: 5, y: 5), radius: 2.6)
                circle(center: CGPoint(x: 5, y: 18), radius: 2.6)

            case .bucket:
                stroke.move(to: CGPoint(x: 6, y: 3))
                stroke.addLine(to: CGPoint(x: 6, y: 20))
                stroke.move(to: CGPoint(x: 7, y: 4))
                stroke.addLine(to: CGPoint(x: 18, y: 4))
                stroke.addLine(to: CGPoint(x: 15, y: 7.5))
                stroke.addLine(to: CGPoint(x: 18, y: 11))
                stroke.addLine(to: CGPoint(x: 7, y: 11))
                stroke.stroke()

            case .trends:
                stroke.move(to: CGPoint(x: 5, y: 16))
                stroke.addLine(to: CGPoint(x: 11, y: 10))
                stroke.addLine(to: CGPoint(x: 15, y: 14))
                stroke.addLine(to: CGPoint(x: 21, y: 8))
                stroke.move(to: CGPoint(x: 17, y: 8))
                stroke.addLine(to: CGPoint(x: 21, y: 8))
                stroke.addLine(to: CGPoint(x: 21, y: 12))
                stroke.stroke()

            case .settings:
                circle(center: CGPoint(x: 14, y: 12), radius: 3)

                let rays = [
                    (CGPoint(x: 14, y: 2.5), CGPoint(x: 14, y: 5.5)),
                    (CGPoint(x: 14, y: 18.5), CGPoint(x: 14, y: 21.5)),
                    (CGPoint(x: 4.5, y: 12), CGPoint(x: 7.5, y: 12)),
                    (CGPoint(x: 20.5, y: 12), CGPoint(x: 23.5, y: 12)),
                    (CGPoint(x: 7.2, y: 5.2), CGPoint(x: 9.4, y: 7.4)),
                    (CGPoint(x: 18.6, y: 16.6), CGPoint(x: 20.8, y: 18.8)),
                    (CGPoint(x: 18.6, y: 7.4), CGPoint(x: 20.8, y: 5.2)),
                    (CGPoint(x: 7.2, y: 18.8), CGPoint(x: 9.4, y: 16.6))
                ]

                for ray in rays {
                    stroke.move(to: ray.0)
                    stroke.addLine(to: ray.1)
                }
                stroke.stroke()
            }
        }

        return image.withRenderingMode(.alwaysTemplate)
    }

    private func circle(center: CGPoint, radius: CGFloat) {
        let circlePath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        circlePath.lineWidth = 1.8
        circlePath.stroke()
    }
}

private enum TabBarIcon {
    case habits
    case bucket
    case trends
    case settings
}
