import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DashboardHeader()
                    .environmentObject(appState)

                if !appState.configuration.isValid {
                    ConfigurationRequiredCard()
                        .environmentObject(appState)
                } else if let error = appState.lastError, appState.snapshot == nil {
                    ErrorStateCard(message: error) {
                        Task {
                            await appState.refreshAll()
                        }
                    }
                } else {
                    SystemHealthCard()
                        .environmentObject(appState)

                    HStack(alignment: .top, spacing: 16) {
                        RecentActivityCard()
                            .environmentObject(appState)
                            .frame(maxWidth: .infinity)

                        DockerSummaryCard()
                            .environmentObject(appState)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 32)
        }
        .refreshable {
            await appState.refreshAll()
        }
        .background(VPSTheme.canvas)
        .navigationTitle("")
    }
}

private struct DashboardHeader: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Text(appState.configuration.displayNameOrFallback)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(VPSTheme.primaryText)
                StatusDot(color: appState.connectionTint, size: 10)
                Text(appState.connectionLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(appState.connectionTint)
                Spacer()
            }

            HStack(spacing: 11) {
                Label(appState.operatingSystemLabel, systemImage: "circle.grid.cross.fill")
                    .foregroundStyle(VPSTheme.secondaryText)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(VPSTheme.orange, VPSTheme.orange.opacity(0.55))

                Text("•")
                    .foregroundStyle(VPSTheme.tertiaryText)

                Label("SSH: \(appState.connectionDetail)", systemImage: "link")
                    .foregroundStyle(appState.connectionTint)

                Text("•")
                    .foregroundStyle(VPSTheme.tertiaryText)

                Label(appState.maskedEndpoint, systemImage: "lock")
                    .foregroundStyle(VPSTheme.secondaryText)
            }
            .font(.system(size: 13))
        }
    }
}

private struct ConfigurationRequiredCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ContentUnavailableView {
            Label("Server bağlantısı qurulmayıb", systemImage: "server.rack")
        } description: {
            Text("Host, istifadəçi və SSH key yolunu daxil etdikdən sonra real göstəricilər burada görünəcək.")
        } actions: {
            Button("Ayarları aç") {
                appState.navigate(to: .settings)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .glassCard()
    }
}

private struct ErrorStateCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("VPS-ə qoşulmaq olmadı", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            Button("Yenidən yoxla", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .glassCard()
    }
}

private struct SystemHealthCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionHeader(title: "Sistem sağlamlığı")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    healthGauge
                        .frame(width: 236)
                        .padding(.trailing, 12)

                    Divider()
                        .overlay(VPSTheme.subtleBorder)

                    metrics(columns: 6)
                }
                .frame(minWidth: 1_080)

                HStack(alignment: .center, spacing: 10) {
                    healthGauge
                        .frame(width: 214)
                        .padding(.trailing, 6)

                    Divider()
                        .overlay(VPSTheme.subtleBorder)

                    compactMetrics
                }
            }

            Divider()
                .overlay(VPSTheme.subtleBorder)

            SecurityStrip()
                .environmentObject(appState)

            Divider()
                .overlay(VPSTheme.subtleBorder)

            MaintenanceStrip()
                .environmentObject(appState)
        }
        .glassCard(padding: 18)
        .overlay(alignment: .topTrailing) {
            if appState.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(19)
            }
        }
    }

    private var healthGauge: some View {
        VStack(spacing: 12) {
            ZStack {
                Gauge(value: appState.healthScore, in: 0...100) {}
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(appState.healthTint)
                .labelsHidden()
                .scaleEffect(2.25)
                .accessibilityLabel("Sağlamlıq")

                VStack(spacing: 5) {
                    Image(systemName: "heart")
                        .font(.system(size: 25, weight: .medium))
                    Text(appState.healthLabel)
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                }
                .foregroundStyle(appState.healthTint)
            }
            .frame(height: 166)
            .accessibilityValue(percent: appState.healthScore)

            Text(appState.healthDescription)
                .font(.caption)
                .foregroundStyle(VPSTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func metrics(columns columnCount: Int) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 118), spacing: 0),
                count: columnCount
            ),
            spacing: 0
        ) {
            ForEach(HealthMetric.allCases, id: \.self) { metric in
                metricCard(metric)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compactMetrics: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(HealthMetric.allCases.prefix(4)), id: \.self) { metric in
                    metricCard(metric)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(HealthMetric.allCases.dropFirst(4)), id: \.self) { metric in
                    metricCard(metric)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func metricCard(_ metric: HealthMetric) -> some View {
        switch metric {
        case .cpu:
            MetricCard(
                title: "CPU",
                systemImage: "cpu",
                primaryValue: appState.cpuPrimary,
                secondaryValue: appState.cpuSecondary,
                percent: appState.snapshot?.cpuPercent,
                history: appState.cpuHistory
            )
        case .memory:
            MetricCard(
                title: "RAM",
                systemImage: "memorychip",
                primaryValue: appState.memoryPrimary,
                secondaryValue: appState.memorySecondary,
                percent: appState.memoryPercent,
                history: appState.memoryHistory
            )
        case .disk:
            MetricCard(
                title: "Disk",
                systemImage: "externaldrive",
                primaryValue: appState.diskPrimary,
                secondaryValue: appState.diskSecondary,
                percent: appState.diskPercent,
                history: appState.diskHistory
            )
        case .swap:
            MetricCard(
                title: "Swap",
                systemImage: "arrow.left.arrow.right",
                primaryValue: appState.swapPrimary,
                secondaryValue: appState.swapSecondary,
                percent: appState.swapPercent,
                history: appState.swapHistory
            )
        case .uptime:
            MetricCard(
                title: "Uptime",
                systemImage: "clock",
                primaryValue: appState.uptimePrimary,
                secondaryValue: appState.uptimeSecondary,
                percent: nil,
                tint: VPSTheme.blue,
                history: []
            )
        case .load:
            MetricCard(
                title: "Load",
                systemImage: "waveform.path.ecg",
                primaryValue: appState.loadPrimary,
                secondaryValue: appState.loadSecondary,
                percent: nil,
                tint: VPSTheme.blue,
                history: appState.loadHistory
            )
        }
    }

    private enum HealthMetric: CaseIterable {
        case cpu
        case memory
        case disk
        case swap
        case uptime
        case load
    }
}

private struct MaintenanceStrip: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Label("Diaqnostika", systemImage: "stethoscope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VPSTheme.primaryText)
                .frame(width: 225, alignment: .leading)

            MaintenanceItem(
                title: "Updates",
                subtitle: appState.updateSummary,
                systemImage: "arrow.down.circle",
                tint: updateTint
            )
            MaintenanceItem(
                title: "Reboot",
                subtitle: appState.rebootSummary,
                systemImage: "restart",
                tint: appState.diagnostics?.rebootRequired == true ? VPSTheme.yellow : VPSTheme.green
            )
            MaintenanceItem(
                title: "Failed units",
                subtitle: appState.failedUnitsSummary,
                systemImage: "gearshape.2",
                tint: (appState.diagnostics?.failedUnitsTotal ?? 0) > 0 ? VPSTheme.yellow : VPSTheme.green
            )
            MaintenanceItem(
                title: "Listeners",
                subtitle: appState.listenersSummary,
                systemImage: "network",
                tint: VPSTheme.blue
            )
        }
        .overlay(alignment: .topTrailing) {
            if appState.isRefreshingDiagnostics {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private var updateTint: Color {
        guard let updates = appState.diagnostics?.updates,
              updates.availability == .available else {
            return VPSTheme.secondaryText
        }
        return (updates.pending ?? 0) > 0 ? VPSTheme.yellow : VPSTheme.green
    }
}

private struct MaintenanceItem: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VPSTheme.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(VPSTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.leading, 22)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VPSTheme.subtleBorder)
                .frame(width: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SecurityStrip: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Label("Təhlükəsizlik", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VPSTheme.primaryText)
                .frame(width: 225, alignment: .leading)

            SecurityItem(
                title: "UFW",
                subtitle: appState.serviceLabel(named: "ufw"),
                healthy: appState.serviceIsHealthy(named: "ufw")
            )
            SecurityItem(
                title: "Fail2ban",
                subtitle: appState.serviceLabel(named: "fail2ban"),
                healthy: appState.serviceIsHealthy(named: "fail2ban")
            )
            SecurityItem(
                title: "SSH key",
                subtitle: appState.configuration.identityFilePath.isEmpty ? "Seçilməyib" : "Qeydiyyatdadır",
                healthy: !appState.configuration.identityFilePath.isEmpty
            )
        }
    }
}

private struct SecurityItem: View {
    let title: String
    let subtitle: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: healthy ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(healthy ? VPSTheme.green : VPSTheme.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VPSTheme.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(VPSTheme.secondaryText)
            }
            Spacer(minLength: 12)
        }
        .padding(.leading, 22)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VPSTheme.subtleBorder)
                .frame(width: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct RecentActivityCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Son fəaliyyət", actionTitle: "Hamısına bax") {
                appState.navigate(to: .activity)
            }

            if appState.activities.isEmpty {
                ContentUnavailableView(
                    "Fəaliyyət yoxdur",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Tətbiqin təsdiqlənmiş əməliyyatları burada görünəcək.")
                )
                .frame(minHeight: 226)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.activities.prefix(5)) { activity in
                        ActivityRow(activity: activity)
                    }
                }
            }
        }
        .glassCard()
    }
}

private struct DockerSummaryCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Docker", actionTitle: "Hamısına bax") {
                appState.navigate(to: .docker)
            }

            HStack(spacing: 18) {
                Label(appState.dockerServiceActive ? "Engine aktiv" : "Engine əlçatmaz", systemImage: "circle.fill")
                    .foregroundStyle(appState.dockerServiceActive ? VPSTheme.green : VPSTheme.yellow)
                Text(appState.dockerAccessLabel)
                    .foregroundStyle(VPSTheme.secondaryText)
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Mənbə")
                    Spacer()
                    Text("Status")
                }
                .font(.caption)
                .foregroundStyle(VPSTheme.secondaryText)
                .padding(.horizontal, 13)
                .frame(height: 36)

                Divider().overlay(VPSTheme.subtleBorder)

                HStack(spacing: 11) {
                    StatusDot(color: appState.dockerServiceActive ? VPSTheme.green : VPSTheme.yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Docker Engine")
                            .foregroundStyle(VPSTheme.primaryText)
                        Text(appState.dockerVersion)
                            .font(.caption2)
                            .foregroundStyle(VPSTheme.secondaryText)
                    }
                    Spacer()
                    Text(appState.dockerServiceActive ? "Running" : "Unknown")
                        .foregroundStyle(appState.dockerServiceActive ? VPSTheme.green : VPSTheme.yellow)
                }
                .font(.system(size: 13))
                .padding(13)
            }
            .background(Color.black.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VPSTheme.subtleBorder)
            }

            Button {
                appState.openTerminal(elevated: false)
            } label: {
                HStack {
                    Text(appState.configuration.user.isEmpty ? "jarvis" : appState.configuration.user)
                        .foregroundStyle(VPSTheme.green)
                    Text("@\(appState.configuration.displayNameOrFallback.lowercased().replacingOccurrences(of: " ", with: "-")):~$")
                        .foregroundStyle(VPSTheme.green)
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 7, height: 15)
                    Spacer()
                }
                .font(.system(size: 13, design: .monospaced))
                .padding(13)
                .frame(minHeight: 64)
                .background(Color.black.opacity(0.60))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terminalı aç")
        }
        .glassCard()
    }
}
