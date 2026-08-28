import Foundation

actor MetricsCollector {
    static let visibleRefreshInterval: Duration = .seconds(15)
    static let backgroundRefreshInterval: Duration = .seconds(60)

    private let client: SSHClient

    init(client: SSHClient = SSHClient()) {
        self.client = client
    }

    func collect(
        configuration: ServerConfiguration,
        timeout: Duration = .seconds(12)
    ) async -> MetricsCollectionResult {
        await client.collect(configuration: configuration, timeout: timeout)
    }

    func reset(serverID: UUID) async {
        await client.forgetPreviousSample(for: serverID)
    }
}
