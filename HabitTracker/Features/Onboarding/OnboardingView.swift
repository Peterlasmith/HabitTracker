import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()

            Text("Build streaks that feel calm, not punishing.")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                onboardingRow(icon: "checklist", title: "Flexible habits", subtitle: "Daily or selected weekdays, binary or count-based.")
                onboardingRow(icon: "bell.badge.fill", title: "Helpful reminders", subtitle: "Set local notifications that match your real schedule.")
                onboardingRow(icon: "chart.line.uptrend.xyaxis", title: "Real momentum", subtitle: "See streaks, history, and widget progress at a glance.")
            }

            Button {
                environment.completeOnboarding()
            } label: {
                Text("Start Building Habits")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            Spacer()
        }
        .padding(24)
    }

    private func onboardingRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .appCard()
    }
}
