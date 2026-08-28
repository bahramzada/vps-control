import XCTest
@testable import VPSControl

@MainActor
final class TerminalWorkspaceModelTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var configuration: TerminalSSHConfiguration!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryDirectory.path)
        let keyURL = temporaryDirectory.appendingPathComponent("id_test")
        let knownHostsURL = temporaryDirectory.appendingPathComponent("known_hosts")
        XCTAssertTrue(FileManager.default.createFile(atPath: keyURL.path, contents: Data("key".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: knownHostsURL.path, contents: Data("host".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        configuration = TerminalSSHConfiguration(
            host: "127.0.0.1",
            identityFileURL: keyURL,
            knownHostsFileURL: knownHostsURL
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCreatesAtMostSixTabs() throws {
        let workspace = TerminalWorkspaceModel(configuration: configuration)
        for _ in 0..<TerminalWorkspaceModel.maximumTabCount {
            try workspace.createTab()
        }

        XCTAssertEqual(workspace.tabs.count, 6)
        XCTAssertThrowsError(try workspace.createTab()) { error in
            XCTAssertEqual(error as? TerminalWorkspaceError, .tabLimitReached(limit: 6))
        }
    }

    func testCloseTerminatesAndSelectsNeighbor() throws {
        let workspace = TerminalWorkspaceModel(configuration: configuration)
        let first = try workspace.createTab()
        let second = try workspace.createTab(elevated: true)

        workspace.selectedTabID = first.id
        workspace.closeTab(id: first.id)

        XCTAssertEqual(workspace.tabs.map(\.id), [second.id])
        XCTAssertEqual(workspace.selectedTabID, second.id)
        XCTAssertEqual(first.connectionState, .disconnected(exitCode: nil))
    }

    func testRequiresConfiguration() {
        let workspace = TerminalWorkspaceModel()

        XCTAssertThrowsError(try workspace.createTab()) { error in
            XCTAssertEqual(error as? TerminalWorkspaceError, .missingConfiguration)
        }
    }

    func testHighRiskTabRequiresExplicitCloseConfirmation() throws {
        let workspace = TerminalWorkspaceModel(configuration: configuration)
        let tab = try workspace.createTab(elevated: true)

        XCTAssertFalse(workspace.closeTab(id: tab.id))
        XCTAssertEqual(workspace.tabs.map(\.id), [tab.id])
        XCTAssertTrue(workspace.closeTab(id: tab.id, confirmedHighRisk: true))
        XCTAssertTrue(workspace.tabs.isEmpty)
    }

    func testRemoteTitleMarksTabConnected() throws {
        let tab = TerminalTabModel(configuration: configuration, requestsElevation: false)

        tab.session.onTitleChange?("jarvis@jarvis: ~")

        XCTAssertEqual(tab.title, "jarvis@jarvis: ~")
        XCTAssertEqual(tab.connectionState, .connected)
    }
}
