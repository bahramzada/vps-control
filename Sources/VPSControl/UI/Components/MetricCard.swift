import SwiftUI

struct MetricCard: View {
    let title: String
    let systemImage: String
    let primaryValue: String
    let secondaryValue: String
    let percent: Double?
    var tint: Color = VPSTheme.green
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VPSTheme.secondaryText)

            Text(primaryValue)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(VPSTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(secondaryValue)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(VPSTheme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 3)

            Sparkline(values: history, color: tint)
                .frame(height: 28)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(VPSTheme.elevatedSurface.opacity(0.24))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(VPSTheme.subtleBorder)
                .frame(width: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(percent.map { "\(Int($0.rounded())) percent" } ?? secondaryValue)
    }
}
