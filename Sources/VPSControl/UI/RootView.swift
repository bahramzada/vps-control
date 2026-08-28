import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(appState)
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 280)
        } detail: {
            Group {
                switch appState.selectedDestination {
                case .overview:
                    DashboardView()
                case .docker:
                    DockerView()
                case .services:
                    ServicesView()
                case .files:
                    FilesView()
                case .terminal:
                    TerminalWorkspaceView(workspace: appState.terminalWorkspace)
                case .activity:
                    ActivityView()
                case .settings:
                    SettingsView()
                }
            }
            .environmentObject(appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VPSTheme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .background(VPSTheme.canvas)
        .toolbar {
            rootToolbar
        }
        .onAppear {
            appState.start()
        }
        .onChange(of: scenePhase) { _, phase in
            appState.setSceneActive(phase == .active)
        }
        .onDisappear {
            appState.stop()
        }
    }

    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                NavigationToolbarControls()
                    .environmentObject(appState)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .principal) {
                PrincipalServerStatus()
                    .environmentObject(appState)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarControls()
                    .environmentObject(appState)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                NavigationToolbarControls()
                    .environmentObject(appState)
            }

            ToolbarItem(placement: .principal) {
                PrincipalServerStatus()
                    .environmentObject(appState)
            }

            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarControls()
                    .environmentObject(appState)
            }
        }
    }
}

private struct NavigationToolbarControls: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                navigationButton(
                    symbol: "chevron.left",
                    help: "Geri",
                    enabled: appState.canNavigateBack,
                    action: appState.navigateBack
                )

                Divider()
                    .frame(height: 18)
                    .overlay(VPSTheme.subtleBorder)

                navigationButton(
                    symbol: "chevron.right",
                    help: "İrəli",
                    enabled: appState.canNavigateForward,
                    action: appState.navigateForward
                )
            }
            .padding(.horizontal, 4)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(VPSTheme.border.opacity(0.78), lineWidth: 1)
            }

            Text("VPS Control")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VPSTheme.primaryText)
        }
        .fixedSize()
    }

    private func navigationButton(
        symbol: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

private struct PrincipalServerStatus: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text(appState.configuration.displayNameOrFallback)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VPSTheme.primaryText)
            StatusDot(color: appState.connectionTint, size: 8)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(appState.configuration.displayNameOrFallback), \(appState.connectionLabel)"
        )
    }
}

private struct PrimaryToolbarControls: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            Button {
                appState.openTerminal(elevated: false)
            } label: {
                Image(systemName: "terminal")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Yeni terminal")
            .disabled(!appState.configuration.isValid)

            Button {
                Task {
                    await appState.refreshAll()
                }
            } label: {
                Group {
                    if appState.isRefreshing || appState.isRefreshingDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Yenilə")
            .disabled(
                !appState.configuration.isValid
                    || appState.isRefreshing
                    || appState.isRefreshingDiagnostics
            )

            ConnectionToolbarStatus()
                .environmentObject(appState)

            Divider()
                .frame(height: 18)
                .overlay(VPSTheme.subtleBorder)
                .padding(.horizontal, 3)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 4) {
                    Text(
                        context.date,
                        format: .dateTime
                            .day()
                            .month(.abbreviated)
                            .year()
                            .weekday(.abbreviated)
                    )
                    Text(context.date, format: .dateTime.hour().minute())
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VPSTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(VPSTheme.border.opacity(0.78), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ConnectionToolbarStatus: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Image(systemName: appState.connectionSymbol)
            .foregroundStyle(appState.connectionTint)
            .frame(width: 28, height: 28)
            .help(appState.connectionLabel)
            .accessibilityLabel("Bağlantı: \(appState.connectionLabel)")
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(VPSTheme.secondaryText)
                Text("vps-control")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VPSTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 21)
            .padding(.bottom, 30)

            VStack(spacing: 6) {
                ForEach(AppDestination.allCases) { destination in
                    Button {
                        appState.navigate(to: destination)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: destination.systemImage)
                                .font(.system(size: 17, weight: .regular))
                                .frame(width: 22)
                            Text(destination.title)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(
                            appState.selectedDestination == destination
                            ? Color.white
                            : VPSTheme.primaryText.opacity(0.86)
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background {
                            if appState.selectedDestination == destination {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                VPSTheme.blue.opacity(0.94),
                                                VPSTheme.blue.opacity(0.67)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: VPSTheme.blue.opacity(0.24), radius: 10, y: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(
                        destination.keyboardShortcut ?? "0",
                        modifiers: .command
                    )
                    .accessibilityLabel(destination.title)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            ServerIdentityCard()
                .environmentObject(appState)
                .padding(16)
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        VPSTheme.sidebar.opacity(0.92),
                        VPSTheme.sidebar.opacity(0.74)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 1)
        }
    }
}

private struct ServerIdentityCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.navigate(to: .settings)
        } label: {
            HStack(spacing: 12) {
                StatusDot(color: appState.connectionTint, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.configuration.displayNameOrFallback)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VPSTheme.primaryText)
                    Text(appState.connectionLabel)
                        .font(.caption)
                        .foregroundStyle(VPSTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(VPSTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .background(VPSTheme.elevatedSurface.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VPSTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Server ayarlarını açır")
    }
}
