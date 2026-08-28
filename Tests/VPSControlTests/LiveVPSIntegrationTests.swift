import Foundation
import XCTest
@testable import VPSControl

final class LiveVPSIntegrationTests: XCTestCase {
    func testReadOnlyCollectorAgainstConfiguredVPS() async throws {
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
            displayName: "Live Test",
            host: host,
            user: environment["VPS_CONTROL_USER"] ?? "jarvis",
            port: UInt16(environment["VPS_CONTROL_PORT"] ?? "") ?? 22,
            identityFilePath: identityPath,
            knownHostsFilePath: knownHostsPath,
            multiplexingEnabled: true
        )

        let collector = MetricsCollector()
        let first = await collector.collect(configuration: configuration)
        XCTAssertEqual(first.connectionState, .online)
        XCTAssertNotNil(first.snapshot)
        XCTAssertGreaterThan(first.snapshot?.memoryTotalBytes ?? 0, 0)
        XCTAssertGreaterThan(first.snapshot?.rootDiskTotalBytes ?? 0, 0)
        XCTAssertEqual(
            first.snapshot?.services.first(where: { $0.name == "ssh" })?.state,
            .active
        )

        try await Task.sleep(for: .seconds(1))
        let second = await collector.collect(configuration: configuration)
        XCTAssertEqual(
            second.connectionState,
            .online,
            "failure=\(String(describing: second.failure)), metric=\(second.metricState)"
        )
        XCTAssertNotNil(second.snapshot?.cpuPercent)
        XCTAssertTrue((0...100).contains(second.snapshot?.cpuPercent ?? -1))
        XCTAssertTrue(
            second.snapshot?.networks.contains(where: { $0.isDefault }) == true
        )
    }

    func testReadOnlyFileBrowserAgainstConfiguredVPS() async throws {
        let configuration = try liveConfiguration()
        let listing = try await RemoteFileBrowser().listDirectory(
            configuration: configuration,
            path: nil,
            timeout: .seconds(8)
        )

        XCTAssertTrue(listing.path.hasPrefix("/"))
        XCTAssertLessThanOrEqual(listing.entries.count, RemoteFileListingScript.maximumEntries)
        XCTAssertTrue(listing.entries.allSatisfy { entry in
            entry.path.hasPrefix(listing.path == "/" ? "/" : listing.path + "/")
                && !entry.name.contains("/")
        })
    }

    func testSlowDiagnosticsAgainstConfiguredVPS() async throws {
        let configuration = try liveConfiguration()
        let result = await DiagnosticsCollector().collect(
            configuration: configuration,
            timeout: .seconds(12)
        )
        let diagnostics = try XCTUnwrap(
            result.diagnostics,
            "failure=\(String(describing: result.failure))"
        )

        XCTAssertEqual(diagnostics.platform.osID, "ubuntu")
        XCTAssertFalse(diagnostics.platform.prettyName.isEmpty)
        XCTAssertFalse(diagnostics.platform.kernelRelease.isEmpty)
        XCTAssertEqual(diagnostics.failedUnitsAvailability, .available)
        XCTAssertEqual(diagnostics.listenersAvailability, .available)
        XCTAssertTrue(diagnostics.listeners.contains { listener in
            listener.transport == .tcp
                && listener.port == 22
                && listener.scope == .wildcard
        })
    }

    private func liveConfiguration() throws -> ServerConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VPS_CONTROL_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set VPS_CONTROL_LIVE_TEST=1 and VPS_CONTROL_* variables to run.")
        }
        guard let host = environment["VPS_CONTROL_HOST"],
              let identityPath = environment["VPS_CONTROL_IDENTITY_FILE"],
              let knownHostsPath = environment["VPS_CONTROL_KNOWN_HOSTS"] else {
            throw XCTSkip("Live test environment is incomplete.")
        }

        return ServerConfiguration(
            displayName: "Live Test",
            host: host,
            user: environment["VPS_CONTROL_USER"] ?? "jarvis",
            port: UInt16(environment["VPS_CONTROL_PORT"] ?? "") ?? 22,
            identityFilePath: identityPath,
            knownHostsFilePath: knownHostsPath,
            multiplexingEnabled: true
        )
    }
}
