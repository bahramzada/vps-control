import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(VPSTheme.blue)
                .frame(width: 42, height: 42)
                .background(VPSTheme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(VPSTheme.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(VPSTheme.secondaryText)
            }
            Spacer()
        }
    }
}

struct SafetyNotice: View {
    let title: String
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VPSTheme.primaryText)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(VPSTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .glassCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsCallout: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ContentUnavailableView {
            Label("Server ayarları tələb olunur", systemImage: "gear.badge")
        } description: {
            Text("Əvvəlcə təhlükəsiz SSH bağlantısını konfiqurasiya et.")
        } actions: {
            Button("Ayarları aç") {
                appState.navigate(to: .settings)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .glassCard()
    }
}
