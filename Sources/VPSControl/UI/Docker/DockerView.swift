import SwiftUI

struct DockerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "Docker",
                    subtitle: "Engine vəziyyəti və təhlükəsiz idarəetmə",
                    systemImage: "shippingbox"
                )

                HStack(spacing: 14) {
                    DockerStatTile(
                        title: "Engine",
                        value: appState.dockerServiceActive ? "Running" : "Unknown",
                        symbol: "shippingbox.fill",
                        tint: appState.dockerServiceActive ? VPSTheme.green : VPSTheme.yellow
                    )
                    DockerStatTile(
                        title: "CLI",
                        value: appState.dockerVersion,
                        symbol: "terminal",
                        tint: VPSTheme.blue
                    )
                    DockerStatTile(
                        title: "Socket",
                        value: appState.dockerAccessLabel,
                        symbol: "lock.shield",
                        tint: appState.dockerSocketAvailable ? VPSTheme.green : VPSTheme.orange
                    )
                }

                if !appState.dockerSocketAvailable {
                    SafetyNotice(
                        title: "Docker socket root-equivalent icazədir",
                        message: "Hazırkı jarvis istifadəçisi socket-ə giriş etmir. Bu təhlükəsiz default-dur. Advanced idarəetmə üçün Portainer ayrıca təsdiqlə VPS loopback-də qurulub SSH tunnel ilə açılacaq.",
                        color: VPSTheme.orange
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Konteynerlər")

                    ContentUnavailableView {
                        Label("Native siyahı hələ kilidlidir", systemImage: "lock")
                    } description: {
                        Text("Engine aktivdir, lakin təhlükəsiz Docker management kanalı qurulmayıb. Heç bir public port açılmayacaq.")
                    } actions: {
                        Button("Terminalda Docker yoxla") {
                            appState.openTerminal(elevated: false)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, minHeight: 230)
                }
                .glassCard()
            }
            .padding(26)
        }
        .background(VPSTheme.canvas)
    }
}

private struct DockerStatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(VPSTheme.secondaryText)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VPSTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 16)
    }
}
