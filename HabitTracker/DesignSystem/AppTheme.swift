import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let card = Color.white.opacity(0.78)
    static let textPrimary = Color(red: 0.12, green: 0.16, blue: 0.18)
    static let textSecondary = Color(red: 0.34, green: 0.39, blue: 0.42)
    static let accent = Color(red: 0.09, green: 0.47, blue: 0.45)
    static let success = Color(red: 0.23, green: 0.60, blue: 0.34)
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 20, x: 0, y: 10)
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}
