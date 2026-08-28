import SwiftUI

@main
struct VPSControlApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1440, height: 960)
        .windowStyle(.titleBar)
        .commands {
            VPSControlCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(width: 560, height: 480)
        }
    }
}
