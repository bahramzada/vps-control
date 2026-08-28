import AppKit
import SwiftTerm

@MainActor
final class TerminalSession: NSObject {
    var onConnectionStateChange: ((TerminalConnectionState) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onFirstRemoteOutput: (() -> Void)?

    private var terminalViewStorage: TerminalProcessView?
    var terminalView: TerminalProcessView {
        if let terminalViewStorage {
            return terminalViewStorage
        }
        let view = makeTerminalView()
        terminalViewStorage = view
        return view
    }
    private var command: TerminalSSHCommand?
    private var receivedRemoteOutput = false
    private var deliberatelyTerminating = false

    func startIfNeeded(configuration: TerminalSSHConfiguration) {
        guard !terminalView.process.running else { return }
        do {
            command = try TerminalSSHCommandBuilder.makeCommand(configuration: configuration)
            receivedRemoteOutput = false
            deliberatelyTerminating = false
            onConnectionStateChange?(.connecting)
            guard let command else { return }
            terminalView.startProcess(
                executable: command.executable,
                args: command.arguments,
                environment: TerminalSession.environment
            )
            if !terminalView.process.running {
                onConnectionStateChange?(.failed(message: "SSH prosesi başladıla bilmədi."))
            }
        } catch {
            onConnectionStateChange?(.failed(message: error.localizedDescription))
        }
    }

    func reconnect(configuration: TerminalSSHConfiguration) {
        if terminalView.process.running {
            deliberatelyTerminating = true
            terminalView.terminate()
        }
        receivedRemoteOutput = false
        deliberatelyTerminating = false
        onConnectionStateChange?(.reconnecting)
        startIfNeeded(configuration: configuration)
    }

    func terminate() {
        deliberatelyTerminating = true
        if terminalView.process.running {
            terminalView.terminate()
        }
        onConnectionStateChange?(.disconnected(exitCode: nil))
    }

    func sendFixedCommand(_ command: String) {
        guard terminalView.process.running else { return }
        terminalView.send(txt: command + "\r")
    }

    private func makeTerminalView() -> TerminalProcessView {
        let view = TerminalProcessView(frame: .zero)
        view.processDelegate = self
        view.session = self
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeForegroundColor = NSColor(
            calibratedRed: 0.86,
            green: 0.88,
            blue: 0.91,
            alpha: 1
        )
        view.nativeBackgroundColor = NSColor(
            calibratedRed: 0.035,
            green: 0.045,
            blue: 0.065,
            alpha: 1
        )
        view.caretColor = NSColor(
            calibratedRed: 0.36,
            green: 0.84,
            blue: 0.59,
            alpha: 1
        )
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.changeScrollback(10_000)
        return view
    }

    fileprivate func receivedOutput() {
        guard !receivedRemoteOutput else { return }
        receivedRemoteOutput = true
        onFirstRemoteOutput?()
    }

    fileprivate func pasteDecision(for text: String) -> TerminalPasteDecision {
        TerminalPastePolicy.evaluate(
            text,
            privilegeState: terminalView.privilegeStateProvider?() ?? .standard,
            isConnected: terminalView.process.running
        )
    }

    private static var environment: [String] {
        let inherited = ProcessInfo.processInfo.environment
        return sanitizedEnvironment(
            inherited: inherited,
            username: NSUserName(),
            homeDirectory: NSHomeDirectory(),
            isSocket: isLocalSocket(path:)
        )
    }

    nonisolated static func sanitizedEnvironment(
        inherited: [String: String],
        username: String,
        homeDirectory: String,
        isSocket: (String) -> Bool
    ) -> [String] {
        var environment = [
            "HOME=\(homeDirectory)",
            "USER=\(username)",
            "LOGNAME=\(username)",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM=xterm-256color",
            "COLORTERM=truecolor"
        ]

        for name in ["LANG", "LC_ALL"] {
            if let value = inherited[name], isSafeLocaleValue(value) {
                environment.append("\(name)=\(value)")
            }
        }

        if let socketPath = inherited["SSH_AUTH_SOCK"], isSocket(socketPath) {
            environment.append("SSH_AUTH_SOCK=\(socketPath)")
        }
        return environment
    }

    nonisolated private static func isSafeLocaleValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.@-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isLocalSocket(path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.contains("\n") else {
            return false
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSocket
    }
}

extension TerminalSession: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        receivedOutput()
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if deliberatelyTerminating {
            onConnectionStateChange?(.disconnected(exitCode: exitCode))
        } else if exitCode == 0 {
            onConnectionStateChange?(.disconnected(exitCode: exitCode))
        } else {
            onConnectionStateChange?(
                .failed(message: "SSH sessiyası dayandı (exit code: \(exitCode.map(String.init) ?? "naməlum")).")
            )
        }
    }
}

@MainActor
final class TerminalProcessView: LocalProcessTerminalView {
    weak var session: TerminalSession?
    var privilegeStateProvider: (() -> TerminalPrivilegeState)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        session?.receivedOutput()
    }

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        let clipboardChangeCount = NSPasteboard.general.changeCount
        let decision = session?.pasteDecision(for: text) ?? .block(reason: "Terminal sessiyası mövcud deyil.")
        switch decision {
        case .allow:
            super.paste(sender)
        case let .block(reason):
            presentPasteBlocked(reason: reason)
        case let .confirm(warnings):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Terminala yapışdırılsın?"
            alert.informativeText = warnings.map(\.message).joined(separator: "\n")
            alert.addButton(withTitle: "Yapışdır")
            alert.addButton(withTitle: "Ləğv et")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == clipboardChangeCount,
                  pasteboard.string(forType: .string) == text else {
                paste(sender)
                return
            }
            super.paste(sender)
        }
    }

    private func presentPasteBlocked(reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Yapışdırmaq mümkün deyil"
        alert.informativeText = reason
        alert.addButton(withTitle: "Oldu")
        alert.runModal()
    }
}
