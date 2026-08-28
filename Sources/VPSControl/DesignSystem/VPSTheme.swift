import SwiftUI

enum VPSTheme {
    static let canvas = Color(red: 0.055, green: 0.063, blue: 0.071)
    static let sidebar = Color(red: 0.085, green: 0.094, blue: 0.104)
    static let surface = Color(red: 0.075, green: 0.084, blue: 0.093)
    static let elevatedSurface = Color(red: 0.095, green: 0.105, blue: 0.116)
    static let border = Color.white.opacity(0.105)
    static let subtleBorder = Color.white.opacity(0.065)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let blue = Color(red: 0.27, green: 0.52, blue: 0.93)
    static let green = Color(red: 0.23, green: 0.78, blue: 0.33)
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.12)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.25)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.20)
    static let cornerRadius: CGFloat = 13
    static let compactRadius: CGFloat = 9
}

struct GlassCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(VPSTheme.surface.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.13))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(VPSTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(
        padding: CGFloat = 18,
        radius: CGFloat = VPSTheme.cornerRadius
    ) -> some View {
        modifier(GlassCardModifier(padding: padding, radius: radius))
    }

    func accessibilityValue(percent: Double) -> some View {
        accessibilityValue(Text("\(Int(percent.rounded())) percent"))
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.35), radius: 3)
            .accessibilityHidden(true)
    }
}

struct LabelValue: View {
    let label: String
    let value: String
    var tint: Color = VPSTheme.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(VPSTheme.secondaryText)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}
