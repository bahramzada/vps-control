import XCTest
@testable import VPSControl

final class TerminalSSHConfigurationTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var keyURL: URL!
    private var knownHostsURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryDirectory.path)
        keyURL = temporaryDirectory.appendingPathComponent("id_test")
        knownHostsURL = temporaryDirectory.appendingPathComponent("known_hosts")
        XCTAssertTrue(FileManager.default.createFile(atPath: keyURL.path, contents: Data("test-key".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: knownHostsURL.path, contents: Data("host-key".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSSHArgumentsUseStrictPublicKeyOnlyPolicy() throws {
        let command = try TerminalSSHCommandBuilder.makeCommand(configuration: configuration())

        XCTAssertEqual(command.executable, "/usr/bin/ssh")
        XCTAssertTrue(command.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(command.arguments.contains("PasswordAuthentication=no"))
        XCTAssertTrue(command.arguments.contains("KbdInteractiveAuthentication=no"))
        XCTAssertTrue(command.arguments.contains("PreferredAuthentications=publickey"))
        XCTAssertTrue(command.arguments.contains("ClearAllForwardings=yes"))
        XCTAssertFalse(command.arguments.contains("StrictHostKeyChecking=no"))
        XCTAssertEqual(command.arguments.suffix(3), ["-tt", "--", "jarvis@203.0.113.42"])
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("sudo"))
    }

    func testRejectsOptionInjectionAsHost() {
        var value = configuration()
        value.host = "-oProxyCommand=bad"

        XCTAssertThrowsError(try value.validated()) { error in
            XCTAssertEqual(error as? TerminalSSHValidationError, .invalidHost)
        }
    }

    func testRejectsWorldReadablePrivateKey() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: keyURL.path)

        XCTAssertThrowsError(try configuration().validated()) { error in
            XCTAssertEqual(error as? TerminalSSHValidationError, .identityFilePermissionsTooOpen)
        }
    }

    func testControlMasterArgumentsOnlyAppearWhenConfigured() throws {
        var value = configuration()
        value.controlPathURL = temporaryDirectory.appendingPathComponent("control-%C")

        let command = try TerminalSSHCommandBuilder.makeCommand(configuration: value)

        XCTAssertTrue(command.arguments.contains("ControlMaster=auto"))
        XCTAssertTrue(command.arguments.contains("ControlPersist=60"))
        XCTAssertTrue(command.arguments.contains("ControlPath=\(value.controlPathURL!.path)"))
    }

    func testRejectsWorldAccessibleControlSocketDirectory() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryDirectory.path)
        var value = configuration()
        value.controlPathURL = temporaryDirectory.appendingPathComponent("control-%C")

        XCTAssertThrowsError(try TerminalSSHCommandBuilder.makeCommand(configuration: value)) { error in
            XCTAssertEqual(error as? TerminalSSHValidationError, .controlPathDirectoryPermissionsTooOpen)
        }
    }

    private func configuration() -> TerminalSSHConfiguration {
        TerminalSSHConfiguration(
            host: "203.0.113.42",
            identityFileURL: keyURL,
            knownHostsFileURL: knownHostsURL
        )
    }
}
