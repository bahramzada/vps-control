import Foundation
import XCTest
@testable import VPSControl

final class SSHLiveSecurityMetricsTests: XCTestCase {
    func testConfiguredVPSSecurityAndDockerAccessAreReported() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VPS_CONTROL_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set VPS_CONTROL_LIVE_TEST=1 and VPS_CONTROL_* variables to run.")
        }
        guard let host = environment["VPS_CONTROL_HOST"],
              let identityPath = environment["VPS_CONTROL_IDENTITY_FILE"],
              let knownHostsPath = environment["VPS_CONTROL_KNOWN_HOSTS"] else {
            XCTFail("Live test environment is incomplete.")
            return
        }

        let configuration = ServerConfiguration(
            displayName: "Live Security Test",
            host: host,
            user: environment["VPS_CONTROL_USER"] ?? "jarvis",
            port: UInt16(environment["VPS_CONTROL_PORT"] ?? "") ?? 22,
            identityFilePath: identityPath,
            knownHostsFilePath: knownHostsPath,
            multiplexingEnabled: true
        )

        let result = await MetricsCollector().collect(configuration: configuration)
        let snapshot = try XCTUnwrap(result.snapshot)

        XCTAssertEqual(result.connectionState, .online)
        XCTAssertEqual(
            snapshot.services.first(where: { $0.name == "fail2ban" })?.state,
            .active
        )
        XCTAssertEqual(
            snapshot.services.first(where: { $0.name == "ufw" })?.state,
            .active
        )
        XCTAssertNotNil(snapshot.dockerCLIVersion)
        XCTAssertEqual(snapshot.dockerSocketAccess, .permissionLocked)
    }
}
