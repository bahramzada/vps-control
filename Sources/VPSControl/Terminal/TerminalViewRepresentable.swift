import AppKit
import SwiftUI

struct TerminalViewRepresentable: NSViewRepresentable {
    @ObservedObject var tab: TerminalTabModel

    func makeNSView(context: Context) -> NSView {
        tab.session.terminalView.privilegeStateProvider = { [weak tab] in
            tab?.privilegeState ?? .standard
        }
        Task { @MainActor [weak tab] in
            tab?.startIfNeeded()
        }
        return tab.session.terminalView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        tab.session.terminalView.privilegeStateProvider = { [weak tab] in
            tab?.privilegeState ?? .standard
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Void) {
        nsView.removeFromSuperview()
    }
}
