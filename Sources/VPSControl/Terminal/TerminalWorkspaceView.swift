import SwiftUI

struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: TerminalWorkspaceModel
    @State private var pendingHighRiskCloseID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().overlay(Color.white.opacity(0.08))
            terminalContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.035, green: 0.045, blue: 0.065))
        .alert(
            "Terminal xətası",
            isPresented: Binding(
                get: { workspace.lastErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        workspace.clearLastError()
                    }
                }
            )
        ) {
            Button("Oldu", role: .cancel) {}
        } message: {
            Text(workspace.lastErrorMessage ?? "Naməlum xəta")
        }
        .confirmationDialog(
            "sudo terminalı bağlansın?",
            isPresented: Binding(
                get: { pendingHighRiskCloseID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingHighRiskCloseID = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Ləğv et", role: .cancel) {
                pendingHighRiskCloseID = nil
            }
            Button("Sessiyanı bağla", role: .destructive) {
                guard let id = pendingHighRiskCloseID else { return }
                workspace.closeTab(id: id, confirmedHighRisk: true)
                pendingHighRiskCloseID = nil
            }
        } message: {
            Text("Bu tabda sudo aktiv ola bilər. Bağlamaq SSH PTY-ni dayandıracaq və remote shell üçün SIGHUP yaradacaq.")
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if workspace.tabs.isEmpty {
                        Label("Terminal sessiyaları", systemImage: "terminal")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(VPSTheme.secondaryText)
                    }

                    ForEach(workspace.tabs) { tab in
                        TerminalTabButton(
                            tab: tab,
                            selected: workspace.selectedTabID == tab.id,
                            select: { workspace.selectedTabID = tab.id },
                            close: {
                                if tab.requestsElevation || tab.privilegeState.isHighRisk {
                                    pendingHighRiskCloseID = tab.id
                                } else {
                                    workspace.closeTab(id: tab.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Yeni terminal") {
                    _ = try? workspace.createTab(elevated: false)
                }
                Button("Yeni sudo terminal…") {
                    _ = try? workspace.createTab(elevated: true)
                }
                .disabled(workspace.configuration == nil)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .disabled(workspace.tabs.count >= TerminalWorkspaceModel.maximumTabCount)
            .help("Terminal aç")

            if let tab = selectedTab {
                TerminalStatusControls(
                    tab: tab,
                    reconnect: { workspace.reconnectTab(id: tab.id) }
                )
            }
        }
        .frame(height: 46)
        .padding(.trailing, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(VPSTheme.elevatedSurface.opacity(0.34))
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let selectedTab {
            TerminalSessionContent(tab: selectedTab)
        } else {
            TerminalEmptyState(
                canConnect: workspace.configuration != nil,
                openTerminal: { _ = try? workspace.createTab() }
            )
        }
    }

    private var selectedTab: TerminalTabModel? {
        guard let selectedTabID = workspace.selectedTabID else { return nil }
        return workspace.tabs.first { $0.id == selectedTabID }
    }

}

private struct TerminalEmptyState: View {
    let canConnect: Bool
    let openTerminal: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(VPSTheme.secondaryText)
                .frame(width: 58, height: 58)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(spacing: 5) {
                Text("Terminal açılmayıb")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(VPSTheme.primaryText)
                Text("SSH sessiyası jarvis istifadəçisi ilə başlayacaq.")
                    .font(.callout)
                    .foregroundStyle(VPSTheme.secondaryText)
            }
            .multilineTextAlignment(.center)

            Button("Terminal aç", action: openTerminal)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canConnect)
        }
        .padding(32)
        .frame(maxWidth: 410)
        .accessibilityElement(children: .contain)
    }
}

private struct TerminalStatusControls: View {
    @ObservedObject var tab: TerminalTabModel
    let reconnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(tab.connectionState.label, systemImage: connectionIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(connectionColor)

            if tab.requestsElevation || tab.privilegeState.isHighRisk {
                Button("sudo-dan çıx") {
                    tab.leaveElevation()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("sudo") {
                    tab.requestElevation()
                }
                .buttonStyle(.bordered)
                .disabled(!tab.connectionState.isConnected)
            }

            if tab.connectionState.isConnected {
                Button {
                    tab.disconnect()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.plain)
                .help("Bağlantını kəs")
            } else {
                Button(action: reconnect) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Yenidən qoşul")
            }
        }
    }

    private var connectionIcon: String {
        switch tab.connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle, .disconnected:
            return "circle"
        }
    }

    private var connectionColor: Color {
        switch tab.connectionState {
        case .connected:
            return Color(red: 0.36, green: 0.84, blue: 0.59)
        case .connecting, .reconnecting:
            return .secondary
        case .failed:
            return Color(red: 1, green: 0.45, blue: 0.42)
        case .idle, .disconnected:
            return .secondary
        }
    }
}

private struct TerminalSessionContent: View {
    @ObservedObject var tab: TerminalTabModel

    var body: some View {
        VStack(spacing: 0) {
            if tab.privilegeState.isHighRisk {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                    Text("Yüksək səlahiyyətli rejim: \(tab.privilegeState.label)")
                    Spacer()
                    Text("jarvis → sudo -i")
                        .font(.caption.monospaced())
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(red: 1, green: 0.67, blue: 0.65))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.red.opacity(0.13))
                .accessibilityLabel("Yüksək səlahiyyətli sudo terminalı")
            }

            TerminalViewRepresentable(tab: tab)
                .accessibilityLabel("\(tab.configuration.displayName) terminalı")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalTabButton: View {
    @ObservedObject var tab: TerminalTabModel
    let selected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(tab.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if tab.privilegeState.isHighRisk {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tabı bağla")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.045))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusColor: Color {
        switch tab.connectionState {
        case .connected:
            return Color(red: 0.36, green: 0.84, blue: 0.59)
        case .connecting, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .idle, .disconnected:
            return .gray
        }
    }
}
