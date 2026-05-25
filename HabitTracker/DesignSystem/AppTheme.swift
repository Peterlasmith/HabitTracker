import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let surface = Color(red: 0.98, green: 0.98, blue: 0.97)
    static let surfaceStrong = Color.white.opacity(0.96)
    static let card = surfaceStrong
    static let fieldBackground = Color.white.opacity(0.92)
    static let border = Color(red: 0.87, green: 0.84, blue: 0.78)
    static let textPrimary = Color(red: 0.12, green: 0.16, blue: 0.22)
    static let textSecondary = Color(red: 0.37, green: 0.42, blue: 0.48)
    static let accent = Color(red: 0.29, green: 0.42, blue: 0.97)
    static let accentSoft = Color(red: 0.93, green: 0.95, blue: 1.0)
    static let success = Color(red: 0.18, green: 0.56, blue: 0.42)
    static let successSoft = Color(red: 0.91, green: 0.96, blue: 0.93)
    static let warning = Color(red: 0.84, green: 0.51, blue: 0.16)
    static let warningSoft = Color(red: 1.0, green: 0.96, blue: 0.91)
    static let error = Color(red: 0.71, green: 0.33, blue: 0.29)
    static let errorBackground = Color(red: 0.98, green: 0.93, blue: 0.91)
    static let shadow = Color(red: 0.14, green: 0.16, blue: 0.18).opacity(0.08)

    static func sans(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }

    static func serif(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Iowan Old Style", size: size).weight(weight)
    }
}

struct AppCardModifier: ViewModifier {
    let fill: Color
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 20, x: 0, y: 10)
    }
}

struct AppInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.sans(size: 17, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func appCard(
        fill: Color = AppTheme.card,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 22
    ) -> some View {
        modifier(AppCardModifier(fill: fill, padding: padding, cornerRadius: cornerRadius))
    }

    func appInput() -> some View {
        modifier(AppInputModifier())
    }
}
