import SwiftUI
import StoreKit

struct PurchaseView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            Text("Unlock the full habit system once.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            feature(title: "Unlimited habits", subtitle: "Track your full routine instead of a tiny sample.")
            feature(title: "Widgets + reminders", subtitle: "See today’s plan and nudge yourself at the right time.")
            feature(title: "Cloud-backed history", subtitle: "Keep your streaks safe across reinstalls.")

            Button {
                Task { await environment.purchaseUnlock() }
            } label: {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            Button("Restore Purchase") {
                Task { await environment.restorePurchases() }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(24)
    }

    private var primaryButtonTitle: String {
        if let product = environment.purchaseService.products.first {
            return "Unlock for \(product.displayPrice)"
        }
        return "Unlock"
    }

    private func feature(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .appCard()
    }
}
