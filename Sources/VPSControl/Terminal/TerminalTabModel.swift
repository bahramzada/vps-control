import Combine
import Foundation

enum TerminalConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected(exitCode: Int32?)
    case failed(message: String)

    var isConnected: Bool {
        self == .connected
    }

    var label: String {
        switch self {
        case .idle:
            return "Hazır"
        case .connecting:
            return "Qoşulur…"
        case .connected:
            return "Qoşulub"
        case .reconnecting:
            return "Yenidən qoşulur…"
        case .disconnected:
            return "Bağlantı kəsilib"
        case .failed:
            return "Xəta"
        }
    }
}

@MainActor
final class TerminalTabModel: ObservableObject, Identifiable {
    let id: UUID
    let configuration: TerminalSSHConfiguration
    let requestsElevation: Bool
    let session: TerminalSession

    @Published var title: String
    @Published private(set) var connectionState: TerminalConnectionState = .idle
    @Published private(set) var privilegeState: TerminalPrivilegeState = .standard

    init(
        id: UUID = UUID(),
        configuration: TerminalSSHConfiguration,
        requestsElevation: Bool
    ) {
        self.id = id
        self.configuration = configuration
        self.requestsElevation = requestsElevation
        self.title = requestsElevation ? "sudo · \(configuration.displayName)" : configuration.displayName
        self.session = TerminalSession()

        session.onConnectionStateChange = { [weak self] state in
            self?.connectionState = state
        }
        session.onTitleChange = { [weak self] title in
            guard let self else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.title = trimmed
            }
            self.markConnectedFromRemoteActivity()
        }
        session.onFirstRemoteOutput = { [weak self] in
            self?.markConnectedFromRemoteActivity()
        }
    }

    func startIfNeeded() {
        session.startIfNeeded(configuration: configuration)
    }

    func reconnect() {
        privilegeState = .standard
        session.reconnect(configuration: configuration)
    }

    func disconnect() {
        session.terminate()
        privilegeState = .standard
        connectionState = .disconnected(exitCode: nil)
    }

    func requestElevation() {
        guard connectionState.isConnected, privilegeState == .standard else {
            return
        }
        privilegeState = .elevating
        session.sendFixedCommand("sudo -i")
    }

    func leaveElevation() {
        guard connectionState.isConnected, privilegeState.isHighRisk else {
            return
        }
        session.sendFixedCommand("exit")
        privilegeState = .uncertain
    }

    func markPrivilegeUncertain() {
        guard privilegeState != .standard else { return }
        privilegeState = .uncertain
    }

    private func markConnectedFromRemoteActivity() {
        guard !connectionState.isConnected else { return }
        connectionState = .connected
        if requestsElevation, privilegeState == .standard {
            requestElevation()
        }
    }
}

enum TerminalWorkspaceError: LocalizedError, Equatable {
    case missingConfiguration
    case tabLimitReached(limit: Int)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Terminal üçün SSH konfiqurasiyası seçilməyib."
        case let .tabLimitReached(limit):
            return "Eyni anda maksimum \(limit) terminal tabı açıla bilər."
        }
    }
}

@MainActor
final class TerminalWorkspaceModel: ObservableObject {
    static let maximumTabCount = 6

    @Published private(set) var tabs: [TerminalTabModel] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var lastErrorMessage: String?

    private(set) var configuration: TerminalSSHConfiguration?

    init(configuration: TerminalSSHConfiguration? = nil) {
        self.configuration = configuration
    }

    func updateConfiguration(_ configuration: TerminalSSHConfiguration?) {
        self.configuration = configuration
        lastErrorMessage = nil
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    @discardableResult
    func createTab(
        configuration: TerminalSSHConfiguration? = nil,
        elevated: Bool = false
    ) throws -> TerminalTabModel {
        guard tabs.count < Self.maximumTabCount else {
            let error = TerminalWorkspaceError.tabLimitReached(limit: Self.maximumTabCount)
            lastErrorMessage = error.localizedDescription
            throw error
        }
        guard let configuration = configuration ?? self.configuration else {
            let error = TerminalWorkspaceError.missingConfiguration
            lastErrorMessage = error.localizedDescription
            throw error
        }

        let validatedConfiguration = try configuration.validated()
        let tab = TerminalTabModel(
            configuration: validatedConfiguration,
            requestsElevation: elevated
        )
        tabs.append(tab)
        selectedTabID = tab.id
        lastErrorMessage = nil
        return tab
    }

    @discardableResult
    func closeTab(id: UUID, confirmedHighRisk: Bool = false) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let requiresConfirmation = tabs[index].requestsElevation || tabs[index].privilegeState.isHighRisk
        guard !requiresConfirmation || confirmedHighRisk else {
            return false
        }
        let wasSelected = selectedTabID == id
        tabs[index].disconnect()
        tabs.remove(at: index)

        guard wasSelected else { return true }
        if tabs.isEmpty {
            selectedTabID = nil
        } else {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        return true
    }

    func reconnectTab(id: UUID) {
        tabs.first(where: { $0.id == id })?.reconnect()
    }

    func shutdownAll() {
        tabs.forEach { $0.disconnect() }
    }
}
