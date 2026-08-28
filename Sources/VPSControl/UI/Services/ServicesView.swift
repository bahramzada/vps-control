import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "Servislər",
                    subtitle: "systemd servislərinin read-only vəziyyəti",
                    systemImage: "gearshape.2"
                )

                if !appState.configuration.isValid {
                    SettingsCallout()
                        .environmentObject(appState)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Servis")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Vəziyyət")
                                .frame(width: 150, alignment: .leading)
                            Text("İdarəetmə")
                                .frame(width: 130, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(VPSTheme.secondaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 42)

                        Divider().overlay(VPSTheme.subtleBorder)

                        ForEach(appState.serviceRows) { service in
                            HStack(spacing: 12) {
                                Image(systemName: service.systemImage)
                                    .foregroundStyle(service.healthy ? VPSTheme.green : VPSTheme.yellow)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(service.displayName)
                                        .foregroundStyle(VPSTheme.primaryText)
                                    Text(service.name)
                                        .font(.caption2)
                                        .foregroundStyle(VPSTheme.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Label(
                                    service.status,
                                    systemImage: service.healthy ? "checkmark.circle.fill" : "questionmark.circle"
                                )
                                .foregroundStyle(service.healthy ? VPSTheme.green : VPSTheme.yellow)
                                .frame(width: 150, alignment: .leading)

                                Button("Logları aç") {
                                    appState.inspectService(service.name)
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 130, alignment: .trailing)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 61)

                            Divider().overlay(VPSTheme.subtleBorder)
                        }
                    }
                    .glassCard(padding: 0)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            FailedUnitsCard()
                                .environmentObject(appState)
                                .frame(maxWidth: .infinity)
                            ListenersCard()
                                .environmentObject(appState)
                                .frame(maxWidth: .infinity)
                        }

                        VStack(spacing: 16) {
                            FailedUnitsCard()
                                .environmentObject(appState)
                            ListenersCard()
                                .environmentObject(appState)
                        }
                    }

                    SafetyNotice(
                        title: "Servis dəyişiklikləri qorunur",
                        message: "Restart, stop və disable əməliyyatları privileged-dir. Onlar ayrıca təsdiq və nəticə yoxlaması olmadan icra edilməyəcək.",
                        color: VPSTheme.yellow
                    )
                }
            }
            .padding(26)
        }
        .background(VPSTheme.canvas)
    }
}

private struct FailedUnitsCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Failed systemd units")

            if let diagnostics = appState.diagnostics,
               diagnostics.failedUnitsAvailability == .available {
                if diagnostics.failedUnits.isEmpty {
                    DiagnosticEmptyRow(
                        title: "Problem yoxdur",
                        systemImage: "checkmark.circle.fill",
                        tint: VPSTheme.green
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(diagnostics.failedUnits.prefix(10)) { unit in
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.gearshape")
                                    .foregroundStyle(VPSTheme.yellow)
                                Text(unit.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(unit.activeState)/\(unit.subState)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(VPSTheme.secondaryText)
                            }
                            .font(.system(size: 13))
                            .frame(minHeight: 38)
                            if unit.id != diagnostics.failedUnits.prefix(10).last?.id {
                                Divider().overlay(VPSTheme.subtleBorder)
                            }
                        }
                    }
                }
                if diagnostics.failedUnitsTotal > 10 {
                    Text("Daha \(diagnostics.failedUnitsTotal - 10) unit göstərilmir")
                        .font(.caption2)
                        .foregroundStyle(VPSTheme.secondaryText)
                }
            } else {
                DiagnosticEmptyRow(
                    title: appState.diagnosticsError ?? "Diaqnostika gözlənilir",
                    systemImage: "clock",
                    tint: VPSTheme.secondaryText
                )
            }
        }
        .glassCard()
    }
}

private struct ListenersCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Listening sockets")

            if let diagnostics = appState.diagnostics,
               diagnostics.listenersAvailability == .available {
                if diagnostics.listeners.isEmpty {
                    DiagnosticEmptyRow(
                        title: "Listening socket yoxdur",
                        systemImage: "network.slash",
                        tint: VPSTheme.secondaryText
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(diagnostics.listeners.prefix(10)) { listener in
                            HStack(spacing: 10) {
                                Text(listener.transport.rawValue.uppercased())
                                    .font(.caption2.weight(.semibold).monospaced())
                                    .foregroundStyle(VPSTheme.blue)
                                    .frame(width: 34, alignment: .leading)
                                Text(endpoint(listener))
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(scopeLabel(listener.scope))
                                    .font(.caption2)
                                    .foregroundStyle(VPSTheme.secondaryText)
                            }
                            .frame(minHeight: 38)
                            if listener.id != diagnostics.listeners.prefix(10).last?.id {
                                Divider().overlay(VPSTheme.subtleBorder)
                            }
                        }
                    }
                }
                if diagnostics.listenersTotal > 10 {
                    Text("Daha \(diagnostics.listenersTotal - 10) socket göstərilmir")
                        .font(.caption2)
                        .foregroundStyle(VPSTheme.secondaryText)
                }
            } else {
                DiagnosticEmptyRow(
                    title: appState.diagnosticsError ?? "Diaqnostika gözlənilir",
                    systemImage: "clock",
                    tint: VPSTheme.secondaryText
                )
            }
        }
        .glassCard()
    }

    private func endpoint(_ listener: ListenerMetric) -> String {
        listener.family == .v6
            ? "[\(listener.address)]:\(listener.port)"
            : "\(listener.address):\(listener.port)"
    }

    private func scopeLabel(_ scope: ListenerScope) -> String {
        switch scope {
        case .wildcard: "all interfaces"
        case .loopback: "loopback"
        case .specific: "specific"
        }
    }
}

private struct DiagnosticEmptyRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    }
}
