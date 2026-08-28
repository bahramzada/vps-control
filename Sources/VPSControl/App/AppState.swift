import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var configuration: ServerConfiguration
    @Published var selectedDestination: AppDestination = .overview
    @Published private(set) var connectionState: ConnectionState = .offline
    @Published private(set) var metricState: MetricState = .offline
    @Published private(set) var snapshot: ServerSnapshot?
    @Published private(set) var diagnostics: ServerDiagnostics?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingDiagnostics = false
    @Published private(set) var lastError: String?
    @Published private(set) var diagnosticsError: String?
    @Published private(set) var activities: [ActivityEntry] = []
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var diskHistory: [Double] = []
    @Published private(set) var swapHistory: [Double] = []
    @Published private(set) var loadHistory: [Double] = []

    let terminalWorkspace: TerminalWorkspaceModel
    let fileBrowser: RemoteFileBrowserModel

    private let collector: MetricsCollector
    private let diagnosticsCollector: DiagnosticsCollector
    private let defaults: UserDefaults
    private var refreshLoop: Task<Void, Never>?
    private var diagnosticsLoop: Task<Void, Never>?
    private var sceneIsActive = true
    private var navigationBackStack: [AppDestination] = []
    private var navigationForwardStack: [AppDestination] = []
    private var hasCompletedInitialCPUSample = false
    private var hasRecordedInitialSnapshotSummary = false
    private var lastRecordedConnectionState: ConnectionState?

    private static let configurationKey = "serverConfiguration.v1"
    private static let maximumHistoryPoints = 60

    init(
        collector: MetricsCollector = MetricsCollector(),
        diagnosticsCollector: DiagnosticsCollector = DiagnosticsCollector(),
        defaults: UserDefaults = .standard
    ) {
        self.collector = collector
        self.diagnosticsCollector = diagnosticsCollector
        self.defaults = defaults

        let loaded = Self.loadConfiguration(defaults: defaults)
        configuration = loaded
        terminalWorkspace = TerminalWorkspaceModel(
            configuration: try? Self.makeTerminalConfiguration(from: loaded)
        )
        fileBrowser = RemoteFileBrowserModel(configuration: loaded)
    }

    deinit {
        refreshLoop?.cancel()
        diagnosticsLoop?.cancel()
    }

    func start() {
        guard refreshLoop == nil else { return }

        if configuration.isValid {
            Task {
                await refreshNow()
                await refreshDiagnosticsNow()
            }
        }

        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.refreshInterval
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refreshIfAppropriate()
            }
        }

        diagnosticsLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.diagnosticsRefreshInterval
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refreshDiagnosticsIfAppropriate()
            }
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
        diagnosticsLoop?.cancel()
        diagnosticsLoop = nil
        terminalWorkspace.shutdownAll()
        fileBrowser.cancel()
    }

    func setSceneActive(_ active: Bool) {
        sceneIsActive = active
    }

    func refreshNow() async {
        guard configuration.isValid, !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        connectionState = .connecting

        var result = await collector.collect(configuration: configuration)

        if result.snapshot?.cpuPercent == nil,
           snapshot == nil,
           !hasCompletedInitialCPUSample,
           result.connectionState == .online {
            do {
                try await Task.sleep(for: .seconds(1))
                result = await collector.collect(configuration: configuration)
                hasCompletedInitialCPUSample = true
            } catch {
                isRefreshing = false
                return
            }
        }

        apply(result)
        isRefreshing = false
    }

    func refreshAll() async {
        await refreshNow()
        await refreshDiagnosticsNow()
    }

    func refreshDiagnosticsNow() async {
        guard configuration.isValid, !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        diagnosticsError = nil

        let result = await diagnosticsCollector.collect(configuration: configuration)
        if let newDiagnostics = result.diagnostics {
            diagnostics = newDiagnostics
        } else {
            diagnosticsError = Self.failureMessage(result.failure)
        }
        isRefreshingDiagnostics = false
    }

    func saveConfiguration(_ newValue: ServerConfiguration) throws {
        guard newValue.isValid else {
            throw AppStateError.invalidConfiguration(newValue.validationIssues)
        }

        let terminalConfiguration: TerminalSSHConfiguration
        do {
            terminalConfiguration = try Self.makeTerminalConfiguration(from: newValue)
        } catch {
            throw AppStateError.invalidTerminalConfiguration(error.localizedDescription)
        }

        let oldID = configuration.id
        configuration = newValue
        terminalWorkspace.updateConfiguration(terminalConfiguration)
        fileBrowser.updateConfiguration(newValue)
        snapshot = nil
        diagnostics = nil
        diagnosticsError = nil
        hasCompletedInitialCPUSample = false
        hasRecordedInitialSnapshotSummary = false
        clearHistories()

        let encoded = try JSONEncoder().encode(newValue)
        defaults.set(encoded, forKey: Self.configurationKey)

        Task {
            await collector.reset(serverID: oldID)
            await refreshNow()
            await refreshDiagnosticsNow()
        }
    }

    func openTerminal(elevated: Bool) {
        guard configuration.isValid else {
            navigate(to: .settings)
            lastError = "Terminal üçün əvvəlcə SSH ayarlarını tamamla."
            return
        }

        do {
            let terminalConfiguration = try Self.makeTerminalConfiguration(from: configuration)
            terminalWorkspace.updateConfiguration(terminalConfiguration)
            _ = try terminalWorkspace.createTab(
                configuration: terminalConfiguration,
                elevated: elevated
            )
            navigate(to: .terminal)
            activities.insert(
                ActivityEntry(
                    title: elevated ? "Elevated terminal açıldı" : "Terminal açıldı",
                    detail: "\(configuration.user) · \(DisplayFormatting.maskedHost(configuration.host))",
                    kind: elevated ? .warning : .terminal
                ),
                at: 0
            )
        } catch {
            lastError = error.localizedDescription
            navigate(to: .settings)
        }
    }

    func inspectService(_ name: String) {
        openTerminal(elevated: false)
        activities.insert(
            ActivityEntry(
                title: "Servis yoxlaması istəndi",
                detail: "\(name) · komanda terminalda istifadəçi tərəfindən yazılmalıdır",
                kind: .information
            ),
            at: 0
        )
    }

    func navigate(to destination: AppDestination) {
        guard destination != selectedDestination else { return }
        navigationBackStack.append(selectedDestination)
        navigationForwardStack.removeAll()
        selectedDestination = destination
    }

    func navigateBack() {
        guard let destination = navigationBackStack.popLast() else { return }
        navigationForwardStack.append(selectedDestination)
        selectedDestination = destination
    }

    func navigateForward() {
        guard let destination = navigationForwardStack.popLast() else { return }
        navigationBackStack.append(selectedDestination)
        selectedDestination = destination
    }

    var canNavigateBack: Bool {
        !navigationBackStack.isEmpty
    }

    var canNavigateForward: Bool {
        !navigationForwardStack.isEmpty
    }

    func chooseIdentityFile() -> String? {
        chooseFile(
            prompt: "SSH private key faylını seç",
            initialDirectory: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".ssh", isDirectory: true)
        )
    }

    func chooseKnownHostsFile() -> String? {
        chooseFile(
            prompt: "known_hosts faylını seç",
            initialDirectory: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".ssh", isDirectory: true)
        )
    }

    var connectionLabel: String {
        switch connectionState {
        case .connecting: "Qoşulur"
        case .online: "Online"
        case .degraded: "Qismən online"
        case .offline: configuration.isValid ? "Offline" : "Qurulmayıb"
        case .authFailed: "Auth xətası"
        case .hostKeyMismatch: "Host key dəyişib"
        case .protocolMismatch: "Protocol xətası"
        case .cancelled: "Dayandırılıb"
        }
    }

    var connectionDetail: String {
        switch connectionState {
        case .online: "Bağlı"
        case .connecting: "Yoxlanılır"
        case .degraded: "Qismən"
        case .authFailed: "Key rədd edildi"
        case .hostKeyMismatch: "Bloklandı"
        default: "Bağlı deyil"
        }
    }

    var connectionTint: Color {
        switch connectionState {
        case .online: VPSTheme.green
        case .connecting: VPSTheme.blue
        case .degraded, .cancelled: VPSTheme.yellow
        case .offline: VPSTheme.secondaryText
        case .authFailed, .hostKeyMismatch, .protocolMismatch: VPSTheme.red
        }
    }

    var connectionSymbol: String {
        switch connectionState {
        case .online: "lock.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .degraded: "exclamationmark.lock"
        case .offline, .cancelled: "lock.open"
        case .authFailed, .hostKeyMismatch, .protocolMismatch: "lock.trianglebadge.exclamationmark"
        }
    }

    var maskedEndpoint: String {
        guard configuration.isValid else { return "ssh://—" }
        return "ssh://\(configuration.user)@\(DisplayFormatting.maskedHost(configuration.host))"
    }

    var operatingSystemLabel: String {
        diagnostics?.platform.prettyName ?? "Linux"
    }

    var updateSummary: String {
        guard let updates = diagnostics?.updates else { return "Yoxlanılır" }
        guard updates.availability == .available, let pending = updates.pending else {
            return updates.availability == .invalid ? "Cache anlaşılmadı" : "Cache yoxdur"
        }
        if pending == 0 { return "Yeniləmə yoxdur" }
        let security = updates.security ?? 0
        return security > 0 ? "\(pending) pending · \(security) security" : "\(pending) pending"
    }

    var failedUnitsSummary: String {
        guard let diagnostics else { return "Yoxlanılır" }
        guard diagnostics.failedUnitsAvailability == .available else { return "Dəstəklənmir" }
        return diagnostics.failedUnitsTotal == 0 ? "Problem yoxdur" : "\(diagnostics.failedUnitsTotal) failed"
    }

    var listenersSummary: String {
        guard let diagnostics else { return "Yoxlanılır" }
        guard diagnostics.listenersAvailability == .available else { return "Dəstəklənmir" }
        return "\(diagnostics.listenersTotal) listening"
    }

    var rebootSummary: String {
        guard let diagnostics else { return "Yoxlanılır" }
        return diagnostics.rebootRequired ? "Restart lazımdır" : "Lazım deyil"
    }

    var healthScore: Double {
        guard let snapshot, connectionState == .online || connectionState == .degraded else {
            return 0
        }

        var score = 100.0
        if let memory = snapshot.memoryUsedPercent, memory > 85 {
            score -= min((memory - 85) * 1.5, 25)
        }
        if let disk = snapshot.rootDiskPercent, disk > 80 {
            score -= min((disk - 80) * 1.5, 25)
        }
        if let cpu = snapshot.cpuPercent, cpu > 85 {
            score -= min((cpu - 85), 15)
        }
        score -= Double(snapshot.services.filter { $0.state == .failed }.count) * 12
        if connectionState == .degraded {
            score -= 20
        }
        return max(0, min(100, score))
    }

    var healthLabel: String {
        switch healthScore {
        case 90...: "Əla"
        case 70..<90: "Yaxşı"
        case 45..<70: "Diqqət"
        default: snapshot == nil ? "—" : "Riskli"
        }
    }

    var healthDescription: String {
        switch healthScore {
        case 90...: "Bütün əsas göstəricilər normaldır"
        case 70..<90: "Sistem stabildir"
        case 45..<70: "Bəzi göstəriciləri yoxla"
        default: snapshot == nil ? "Məlumat gözlənilir" : "Müdaxilə lazım ola bilər"
        }
    }

    var healthTint: Color {
        switch healthScore {
        case 90...: VPSTheme.green
        case 70..<90: VPSTheme.blue
        case 45..<70: VPSTheme.yellow
        default: snapshot == nil ? VPSTheme.secondaryText : VPSTheme.red
        }
    }

    var cpuPrimary: String {
        DisplayFormatting.percent(snapshot?.cpuPercent)
    }

    var cpuSecondary: String {
        snapshot?.cpuPercent == nil ? "İkinci nümunə gözlənilir" : "real-time delta"
    }

    var memoryPercent: Double? {
        snapshot?.memoryUsedPercent
    }

    var memoryPrimary: String {
        guard let snapshot,
              let used = snapshot.memoryUsedBytes,
              let total = snapshot.memoryTotalBytes else {
            return "—"
        }
        return "\(DisplayFormatting.bytes(used)) / \(DisplayFormatting.bytes(total))"
    }

    var memorySecondary: String {
        DisplayFormatting.percent(memoryPercent)
    }

    var diskPercent: Double? {
        snapshot?.rootDiskPercent
    }

    var diskPrimary: String {
        guard let snapshot,
              let used = snapshot.rootDiskUsedBytes,
              let total = snapshot.rootDiskTotalBytes else {
            return "—"
        }
        return "\(DisplayFormatting.bytes(used)) / \(DisplayFormatting.bytes(total))"
    }

    var diskSecondary: String {
        DisplayFormatting.percent(diskPercent)
    }

    var swapPercent: Double? {
        guard let snapshot,
              let used = snapshot.swapUsedBytes,
              let total = snapshot.swapTotalBytes,
              total > 0 else {
            return nil
        }
        return Double(used) / Double(total) * 100
    }

    var swapPrimary: String {
        guard let snapshot,
              let used = snapshot.swapUsedBytes,
              let total = snapshot.swapTotalBytes else {
            return "—"
        }
        return "\(DisplayFormatting.bytes(used)) / \(DisplayFormatting.bytes(total))"
    }

    var swapSecondary: String {
        DisplayFormatting.percent(swapPercent)
    }

    var uptimePrimary: String {
        DisplayFormatting.uptime(snapshot?.uptimeSeconds).primary
    }

    var uptimeSecondary: String {
        DisplayFormatting.uptime(snapshot?.uptimeSeconds).secondary
    }

    var loadPrimary: String {
        guard let load = snapshot?.loadAverage else { return "—" }
        return String(format: "%.2f", load.oneMinute)
    }

    var loadSecondary: String {
        guard let load = snapshot?.loadAverage else { return "Məlumat yoxdur" }
        return String(format: "1d %.2f  5d %.2f  15d %.2f", load.oneMinute, load.fiveMinutes, load.fifteenMinutes)
    }

    var serviceRows: [ServiceRow] {
        let preferredOrder = ["ssh", "docker", "fail2ban", "ufw"]
        let metrics = snapshot?.services ?? []
        let indexed = Dictionary(uniqueKeysWithValues: metrics.map { ($0.name, $0) })
        return preferredOrder.map { name in
            let metric = indexed[name]
            return ServiceRow(
                name: name,
                displayName: serviceDisplayName(name),
                status: metric?.state.rawValue ?? "unknown",
                healthy: metric?.state == .active,
                systemImage: serviceSystemImage(name)
            )
        }
    }

    func serviceLabel(named name: String) -> String {
        guard let service = snapshot?.services.first(where: { $0.name == name }) else {
            return "Məlumat yoxdur"
        }
        return service.state == .active ? "Aktiv" : service.state.rawValue
    }

    func serviceIsHealthy(named name: String) -> Bool {
        snapshot?.services.first(where: { $0.name == name })?.state == .active
    }

    var dockerServiceActive: Bool {
        serviceIsHealthy(named: "docker")
    }

    var dockerSocketAvailable: Bool {
        snapshot?.dockerSocketAccess == .available
    }

    var dockerAccessLabel: String {
        switch snapshot?.dockerSocketAccess {
        case .available: "Native access"
        case .permissionLocked: "Permission locked"
        case .unsupported: "Docker yoxdur"
        case .unknown, .none: "Yoxlanılmayıb"
        }
    }

    var dockerVersion: String {
        snapshot?.dockerCLIVersion ?? "Yoxlanılmayıb"
    }

    private var refreshInterval: Duration {
        if !sceneIsActive {
            return .seconds(60)
        }
        return selectedDestination == .overview
            ? MetricsCollector.visibleRefreshInterval
            : MetricsCollector.backgroundRefreshInterval
    }

    private var diagnosticsRefreshInterval: Duration {
        sceneIsActive
            ? DiagnosticsCollector.activeRefreshInterval
            : DiagnosticsCollector.backgroundRefreshInterval
    }

    private func refreshIfAppropriate() async {
        guard configuration.isValid else { return }
        if sceneIsActive || snapshot == nil {
            await refreshNow()
        }
    }

    private func refreshDiagnosticsIfAppropriate() async {
        guard configuration.isValid else { return }
        if sceneIsActive || diagnostics == nil {
            await refreshDiagnosticsNow()
        }
    }

    private func apply(_ result: MetricsCollectionResult) {
        let previousState = connectionState
        connectionState = result.connectionState
        metricState = result.metricState

        if let newSnapshot = result.snapshot {
            snapshot = newSnapshot
            appendHistory(newSnapshot)
            lastError = nil
            recordInitialSnapshotSummaryIfNeeded(newSnapshot)
        } else if snapshot != nil {
            metricState = .stale
            lastError = Self.failureMessage(result.failure)
        } else {
            lastError = Self.failureMessage(result.failure)
        }

        if result.connectionState != lastRecordedConnectionState {
            recordConnectionTransition(
                from: previousState,
                to: result.connectionState,
                failure: result.failure
            )
            lastRecordedConnectionState = result.connectionState
        }
    }

    private func appendHistory(_ snapshot: ServerSnapshot) {
        append(snapshot.cpuPercent, to: &cpuHistory)
        append(snapshot.memoryUsedPercent, to: &memoryHistory)
        append(snapshot.rootDiskPercent, to: &diskHistory)
        append(swapPercent, to: &swapHistory)
        append(snapshot.loadAverage?.oneMinute, to: &loadHistory)
    }

    private func append(_ value: Double?, to history: inout [Double]) {
        guard let value, value.isFinite else { return }
        history.append(value)
        if history.count > Self.maximumHistoryPoints {
            history.removeFirst(history.count - Self.maximumHistoryPoints)
        }
    }

    private func clearHistories() {
        cpuHistory.removeAll()
        memoryHistory.removeAll()
        diskHistory.removeAll()
        swapHistory.removeAll()
        loadHistory.removeAll()
    }

    private func recordConnectionTransition(
        from oldState: ConnectionState,
        to newState: ConnectionState,
        failure: MetricsCollectionFailure?
    ) {
        switch newState {
        case .online:
            activities.insert(
                ActivityEntry(
                    title: "SSH bağlantısı uğurlu",
                    detail: "\(configuration.user)@\(DisplayFormatting.maskedHost(configuration.host))",
                    kind: .success
                ),
                at: 0
            )
        case .hostKeyMismatch:
            activities.insert(
                ActivityEntry(
                    title: "Host key uyğunsuzluğu",
                    detail: "Bağlantı fail-closed rejimində bloklandı",
                    kind: .warning
                ),
                at: 0
            )
        case .authFailed:
            activities.insert(
                ActivityEntry(
                    title: "SSH authentication uğursuzdur",
                    detail: Self.failureMessage(failure),
                    kind: .warning
                ),
                at: 0
            )
        case .degraded:
            activities.insert(
                ActivityEntry(
                    title: "Metriklər qismən alındı",
                    detail: "Bəzi read-only göstəricilər əlçatan deyil",
                    kind: .information
                ),
                at: 0
            )
        case .connecting, .offline, .protocolMismatch, .cancelled:
            if oldState == .online && newState == .offline {
                activities.insert(
                    ActivityEntry(
                        title: "VPS bağlantısı kəsildi",
                        detail: Self.failureMessage(failure),
                        kind: .warning
                    ),
                    at: 0
                )
            }
        }
        if activities.count > 100 {
            activities.removeLast(activities.count - 100)
        }
    }

    private func recordInitialSnapshotSummaryIfNeeded(_ snapshot: ServerSnapshot) {
        guard !hasRecordedInitialSnapshotSummary else { return }
        hasRecordedInitialSnapshotSummary = true

        let checks: [ActivityEntry] = [
            ActivityEntry(
                title: "Docker Engine yoxlandı",
                detail: serviceLabel(named: "docker"),
                kind: dockerServiceActive ? .success : .warning
            ),
            ActivityEntry(
                title: "Fail2ban status yoxlandı",
                detail: serviceLabel(named: "fail2ban"),
                kind: serviceIsHealthy(named: "fail2ban") ? .success : .warning
            ),
            ActivityEntry(
                title: "UFW status yoxlandı",
                detail: serviceLabel(named: "ufw"),
                kind: serviceIsHealthy(named: "ufw") ? .success : .warning
            ),
            ActivityEntry(
                title: "Sistem göstəriciləri yeniləndi",
                detail: "CPU, RAM, disk, swap və network",
                kind: .information
            )
        ]
        activities.insert(contentsOf: checks, at: 0)
    }

    private func chooseFile(prompt: String, initialDirectory: URL) -> String? {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.prompt = "Seç"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = initialDirectory
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.standardizedFileURL.path
    }

    private func serviceDisplayName(_ name: String) -> String {
        switch name {
        case "ssh": "OpenSSH"
        case "docker": "Docker Engine"
        case "fail2ban": "Fail2ban"
        case "ufw": "UFW Firewall"
        default: name
        }
    }

    private func serviceSystemImage(_ name: String) -> String {
        switch name {
        case "ssh": "key.horizontal"
        case "docker": "shippingbox"
        case "fail2ban": "hand.raised"
        case "ufw": "shield"
        default: "gearshape"
        }
    }

    private static func loadConfiguration(defaults: UserDefaults) -> ServerConfiguration {
        if let data = defaults.data(forKey: configurationKey),
           let configuration = try? JSONDecoder().decode(ServerConfiguration.self, from: data) {
            return configuration
        }

        let environment = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return ServerConfiguration(
            displayName: environment["VPS_CONTROL_NAME"] ?? "Jarvis VPS",
            host: environment["VPS_CONTROL_HOST"] ?? "",
            user: environment["VPS_CONTROL_USER"] ?? "jarvis",
            port: UInt16(environment["VPS_CONTROL_PORT"] ?? "") ?? 22,
            identityFilePath: environment["VPS_CONTROL_IDENTITY_FILE"] ?? "",
            knownHostsFilePath: environment["VPS_CONTROL_KNOWN_HOSTS"]
                ?? home.appendingPathComponent(".ssh/known_hosts").standardizedFileURL.path,
            multiplexingEnabled: true
        )
    }

    private static func makeTerminalConfiguration(
        from configuration: ServerConfiguration
    ) throws -> TerminalSSHConfiguration {
        var controlPathURL: URL?
        if configuration.multiplexingEnabled {
            let directory = SSHInvocationBuilder.defaultControlSocketDirectory()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            controlPathURL = directory.appendingPathComponent("%C")
        }

        return try TerminalSSHConfiguration(
            displayName: configuration.displayNameOrFallback,
            host: configuration.host,
            port: configuration.port,
            username: configuration.user,
            identityFileURL: URL(fileURLWithPath: configuration.identityFilePath),
            knownHostsFileURL: URL(fileURLWithPath: configuration.knownHostsFilePath),
            controlPathURL: controlPathURL
        ).validated()
    }

    private static func failureMessage(_ failure: MetricsCollectionFailure?) -> String {
        switch failure {
        case .invalidConfiguration: "Server ayarları düzgün deyil."
        case .localSSHUnavailable: "macOS sistem SSH proqramı tapılmadı."
        case .identityFileUnavailable: "SSH key faylı tapılmadı."
        case .identityFilePermissions: "SSH key icazələri çox açıqdır; 600 istifadə et."
        case .knownHostsUnavailable: "known_hosts faylı tapılmadı."
        case .hostKeyMismatch: "Server host key əvvəlki qeyd ilə uyğun deyil."
        case .authenticationFailed: "SSH key authentication rədd edildi."
        case .connectionFailed: "VPS-ə şəbəkə bağlantısı qurulmadı."
        case .remoteCommandFailed: "Read-only remote collector tamamlanmadı."
        case .timeout: "SSH sorğusu vaxt limitini keçdi."
        case .cancelled: "Sorğu dayandırıldı."
        case .protocolMismatch: "Metrik protokolu uyğun deyil."
        case .malformedResponse: "Server qismən və ya səhv formatlı cavab verdi."
        case .none: "Naməlum bağlantı xətası."
        }
    }
}

extension ServerConfiguration {
    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.init(
            displayName: "Jarvis VPS",
            host: "",
            user: "jarvis",
            identityFilePath: "",
            knownHostsFilePath: home
                .appendingPathComponent(".ssh/known_hosts")
                .standardizedFileURL.path
        )
    }

    var displayNameOrFallback: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "VPS" : trimmed
    }
}

enum AppStateError: LocalizedError {
    case invalidConfiguration([ServerConfigurationValidationIssue])
    case invalidTerminalConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let issues):
            let labels = issues.map(\.localizedLabel).joined(separator: ", ")
            return "Bu sahələri yoxla: \(labels)."
        case .invalidTerminalConfiguration(let message):
            return "Terminal ayarı düzgün deyil: \(message)"
        }
    }
}

private extension ServerConfigurationValidationIssue {
    var localizedLabel: String {
        switch self {
        case .missingDisplayName: "server adı"
        case .invalidHost: "host"
        case .invalidUser: "SSH user"
        case .invalidPort: "port"
        case .invalidIdentityFilePath: "SSH key path"
        case .invalidKnownHostsFilePath: "known_hosts path"
        }
    }
}
