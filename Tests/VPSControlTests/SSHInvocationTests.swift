import Foundation
import XCTest
@testable import VPSControl

final class SSHInvocationTests: XCTestCase {
    func testBuildsStrictReadOnlyInvocationWithSeparateArguments() throws {
        let fileSystem = SSHTestFileSystem(
            executableAvailable: true,
            attributes: [
                "/Users/test/.ssh/key": [
                    .type: FileAttributeType.typeRegular,
                    .posixPermissions: NSNumber(value: 0o600)
                ],
                "/Users/test/.ssh/known_hosts": [
                    .type: FileAttributeType.typeRegular,
                    .posixPermissions: NSNumber(value: 0o644)
                ]
            ]
        )
        let builder = SSHInvocationBuilder(
            fileSystem: fileSystem,
            temporaryDirectory: URL(fileURLWithPath: "/private/tmp/tests", isDirectory: true)
        )
        let configuration = ServerConfiguration(
            displayName: "Test server",
            host: "example.test",
            user: "jarvis",
            port: 2222,
            identityFilePath: "/Users/test/.ssh/key",
            knownHostsFilePath: "/Users/test/.ssh/known_hosts"
        )

        let invocation = try builder.makeReadOnlyCollectorInvocation(configuration: configuration)

        XCTAssertEqual(invocation.executableURL.path, "/usr/bin/ssh")
        XCTAssertTrue(Set(invocation.environment.keys).isSubset(of: [
            "HOME", "USER", "LOGNAME", "PATH", "LANG", "LC_CTYPE", "SSH_AUTH_SOCK"
        ]))
        XCTAssertTrue(invocation.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(invocation.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(invocation.arguments.contains("ClearAllForwardings=yes"))
        XCTAssertTrue(invocation.arguments.contains("ControlMaster=auto"))
        XCTAssertTrue(invocation.arguments.contains("ControlPath=/private/tmp/tests/com.vps-control.ssh/%C"))
        XCTAssertEqual(Array(invocation.arguments.suffix(4)), ["example.test", "/usr/bin/bash", "-s", "--"])
        XCTAssertEqual(invocation.arguments[invocation.arguments.firstIndex(of: "-l")! + 1], "jarvis")
        XCTAssertFalse(invocation.arguments.contains("jarvis@example.test"))
        XCTAssertFalse(String(decoding: invocation.standardInput, as: UTF8.self).contains("example.test"))
    }

    func testRejectsOptionLikeHostAndRelativePaths() {
        let configuration = ServerConfiguration(
            host: "-oProxyCommand=bad",
            user: "jarvis",
            identityFilePath: "~/.ssh/key",
            knownHostsFilePath: "relative/known_hosts"
        )

        XCTAssertFalse(configuration.isValid)
        XCTAssertEqual(
            Set(configuration.validationIssues),
            Set([.invalidHost, .invalidIdentityFilePath, .invalidKnownHostsFilePath])
        )
    }

    func testRejectsPrivateKeyWithGroupOrWorldPermissions() {
        let fileSystem = SSHTestFileSystem(
            executableAvailable: true,
            attributes: [
                "/Users/test/.ssh/key": [
                    .type: FileAttributeType.typeRegular,
                    .posixPermissions: NSNumber(value: 0o644)
                ],
                "/Users/test/.ssh/known_hosts": [
                    .type: FileAttributeType.typeRegular
                ]
            ]
        )
        let builder = SSHInvocationBuilder(fileSystem: fileSystem)
        let configuration = ServerConfiguration(
            host: "example.test",
            user: "jarvis",
            identityFilePath: "/Users/test/.ssh/key",
            knownHostsFilePath: "/Users/test/.ssh/known_hosts"
        )

        XCTAssertThrowsError(try builder.makeReadOnlyCollectorInvocation(configuration: configuration)) { error in
            XCTAssertEqual(error as? SSHInvocationError, .identityFilePermissionsTooOpen)
        }
    }

    func testFileListingInvocationHexEncodesRemotePathAndKeepsStrictPolicy() throws {
        let fileSystem = SSHTestFileSystem(
            executableAvailable: true,
            attributes: [
                "/Users/test/.ssh/key": [
                    .type: FileAttributeType.typeRegular,
                    .posixPermissions: NSNumber(value: 0o600)
                ],
                "/Users/test/.ssh/known_hosts": [
                    .type: FileAttributeType.typeRegular,
                    .posixPermissions: NSNumber(value: 0o644)
                ]
            ]
        )
        let builder = SSHInvocationBuilder(
            fileSystem: fileSystem,
            temporaryDirectory: URL(fileURLWithPath: "/private/tmp/tests", isDirectory: true)
        )
        let configuration = ServerConfiguration(
            host: "example.test",
            user: "jarvis",
            identityFilePath: "/Users/test/.ssh/key",
            knownHostsFilePath: "/Users/test/.ssh/known_hosts"
        )
        let unsafeLookingPath = "/home/jarvis/My Folder;touch /tmp/should-not-run"

        let invocation = try builder.makeReadOnlyFileListingInvocation(
            configuration: configuration,
            path: unsafeLookingPath,
            script: "printf '%s' safe"
        )

        XCTAssertTrue(invocation.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(invocation.arguments.contains("ClearAllForwardings=yes"))
        XCTAssertTrue(invocation.arguments.contains("ControlMaster=auto"))
        XCTAssertEqual(invocation.standardInput, Data())
        XCTAssertEqual(Array(invocation.arguments.suffix(6).prefix(4)), [
            "example.test", "/usr/bin/bash", "-c", "'printf '\"'\"'%s'\"'\"' safe'"
        ])

        let encodedPath = try XCTUnwrap(invocation.arguments.last)
        XCTAssertFalse(invocation.arguments.contains(unsafeLookingPath))
        XCTAssertTrue(encodedPath.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(
            Data(hexString: encodedPath).flatMap { String(data: $0, encoding: .utf8) },
            unsafeLookingPath
        )
    }

    func testFileListingInvocationRejectsRelativeAndControlCharacterPaths() {
        let fileSystem = SSHTestFileSystem(
            executableAvailable: true,
            attributes: [
                "/Users/test/.ssh/key": [
                    .type: FileAttributeType.typeRegular,
                    .posixPermissions: NSNumber(value: 0o600)
                ],
                "/Users/test/.ssh/known_hosts": [
                    .type: FileAttributeType.typeRegular
                ]
            ]
        )
        let builder = SSHInvocationBuilder(fileSystem: fileSystem)
        let configuration = ServerConfiguration(
            host: "example.test",
            user: "jarvis",
            identityFilePath: "/Users/test/.ssh/key",
            knownHostsFilePath: "/Users/test/.ssh/known_hosts"
        )

        for path in ["home/jarvis", "/home/jarvis\n/etc", "/home/jarvis\r/etc"] {
            XCTAssertThrowsError(
                try builder.makeReadOnlyFileListingInvocation(
                    configuration: configuration,
                    path: path
                )
            ) { error in
                XCTAssertEqual(error as? SSHInvocationError, .invalidRemotePath)
            }
        }
    }

    func testConfigurationRoundTripsThroughJSONForUserDefaultsStorage() throws {
        let original = ServerConfiguration(
            displayName: "Personal VPS",
            host: "server.example",
            user: "operator",
            port: 22,
            identityFilePath: "/Users/test/.ssh/id_ed25519",
            knownHostsFilePath: "/Users/test/.ssh/known_hosts"
        )

        let decoded = try JSONDecoder().decode(
            ServerConfiguration.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

private final class SSHTestFileSystem: SSHFileSystemChecking, @unchecked Sendable {
    let executableAvailable: Bool
    let attributes: [String: [FileAttributeKey: Any]]

    init(executableAvailable: Bool, attributes: [String: [FileAttributeKey: Any]]) {
        self.executableAvailable = executableAvailable
        self.attributes = attributes
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executableAvailable && path == "/usr/bin/ssh"
    }

    func fileAttributes(atPath path: String) throws -> [FileAttributeKey: Any] {
        guard let value = attributes[path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return value
    }
}
