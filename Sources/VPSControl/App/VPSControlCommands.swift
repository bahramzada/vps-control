import SwiftUI

struct VPSControlCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Server") {
            Button("Refresh") {
                Task {
                    await appState.refreshAll()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!appState.configuration.isValid)

            Divider()

            Button("New Terminal") {
                appState.openTerminal(elevated: false)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!appState.configuration.isValid)

            Button("New Elevated Terminal…") {
                appState.openTerminal(elevated: true)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!appState.configuration.isValid)
        }
    }
}
