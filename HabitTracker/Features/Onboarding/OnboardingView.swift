import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 18, height: 18)

                    Text("HabitClaw")
                        .font(AppTheme.serif(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Text("Build streaks that feel calm, not punishing.")
                    .font(AppTheme.serif(size: 40, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Track the routines you want to return to, see your rhythm across the week, and keep progress visible without making it feel heavy.")
                    .font(AppTheme.sans(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)

                VStack(alignment: .leading, spacing: 16) {
                    onboardingRow(icon: "checklist", title: "Flexible habits", subtitle: "Track daily habits on every day or only the weekdays you choose.")
                    onboardingRow(icon: "bell.badge.fill", title: "Helpful reminders", subtitle: "Set local notifications that match your real schedule.")
                    onboardingRow(icon: "chart.line.uptrend.xyaxis", title: "Real momentum", subtitle: "See streaks, trends, and daily progress at a glance.")
                }

                Button {
                    environment.completeOnboarding()
                } label: {
                    Text("Start Building Habits")
                        .font(AppTheme.sans(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 480, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func onboardingRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.serif(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(AppTheme.sans(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .appCard()
    }
}
