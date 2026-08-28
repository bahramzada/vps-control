import Foundation

struct SSHInvocation: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let standardInput: Data
    let timeout: Duration
    let controlSocketDirectory: URL?
    let environment: [String: String]
}

enum SSHInvocationError: Error, Equatable, LocalizedError {
    case invalidConfiguration([ServerConfigurationValidationIssue])
    case sshExecutableUnavailable
    case identityFileMissing
    case identityFileNotRegular
    case identityFilePermissionsTooOpen
    case knownHostsFileMissing
    case knownHostsFileNotRegular
    case unsafeControlSocketDirectory
    case invalidTimeout
    case invalidRemotePath

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Server configuration is invalid."
        case .sshExecutableUnavailable:
            return "The system SSH executable is unavailable."
        case .identityFileMissing:
            return "The selected SSH identity file does not exist."
        case .identityFileNotRegular:
            return "The selected SSH identity path is not a regular file."
        case .identityFilePermissionsTooOpen:
            return "The SSH identity file permissions are too open."
        case .knownHostsFileMissing:
            return "The selected known_hosts file does not exist."
        case .knownHostsFileNotRegular:
            return "The selected known_hosts path is not a regular file."
        case .unsafeControlSocketDirectory:
            return "The SSH control socket directory is not inside the local temporary directory."
        case .invalidTimeout:
            return "The SSH timeout must be positive."
        case .invalidRemotePath:
            return "The remote path must be an absolute UTF-8 path without control characters."
        }
    }
}

protocol SSHFileSystemChecking: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
    func fileAttributes(atPath path: String) throws -> [FileAttributeKey: Any]
}

struct FoundationSSHFileSystem: SSHFileSystemChecking, @unchecked Sendable {
    func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    func fileAttributes(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }
}

struct SSHInvocationBuilder: Sendable {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

    static func defaultTemporaryDirectory() -> URL {
        URL(
            fileURLWithPath: "/private/tmp/vpsc-\(getuid())",
            isDirectory: true
        ).standardizedFileURL
    }

    static func defaultControlSocketDirectory() -> URL {
        defaultTemporaryDirectory()
            .appendingPathComponent("com.vps-control.ssh", isDirectory: true)
            .standardizedFileURL
    }

    private let fileSystem: any SSHFileSystemChecking
    private let temporaryDirectory: URL

    init(
        fileSystem: any SSHFileSystemChecking = FoundationSSHFileSystem(),
        temporaryDirectory: URL = SSHInvocationBuilder.defaultTemporaryDirectory()
    ) {
        self.fileSystem = fileSystem
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
    }

    func makeReadOnlyCollectorInvocation(
        configuration: ServerConfiguration,
        script: String = RemoteMetricsCollectorScript.source,
        timeout: Duration = .seconds(12)
    ) throws -> SSHInvocation {
        let issues = configuration.validationIssues
        guard issues.isEmpty else {
            throw SSHInvocationError.invalidConfiguration(issues)
        }
        guard timeout > .zero else {
            throw SSHInvocationError.invalidTimeout
        }
        guard fileSystem.isExecutableFile(atPath: Self.executableURL.path) else {
            throw SSHInvocationError.sshExecutableUnavailable
        }

        try validateIdentityFile(path: configuration.identityFilePath)
        try validateKnownHostsFile(path: configuration.knownHostsFilePath)

        var arguments = [
            "-F", "/dev/null",
            "-T",
            "-p", String(configuration.port),
            "-l", configuration.user,
            "-i", configuration.identityFilePath,
            "-o", "IdentitiesOnly=yes",
            "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no",
            "-o", "ChallengeResponseAuthentication=no",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(configuration.knownHostsFilePath)",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "UpdateHostKeys=no",
            "-o", "ConnectTimeout=8",
            "-o", "ConnectionAttempts=1",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "ClearAllForwardings=yes",
            "-o", "LogLevel=ERROR"
        ]

        var socketDirectory: URL?
        if configuration.multiplexingEnabled {
            let directory = temporaryDirectory
                .appendingPathComponent("com.vps-control.ssh", isDirectory: true)
                .standardizedFileURL
            let safePrefix = temporaryDirectory.path.hasSuffix("/")
                ? temporaryDirectory.path
                : temporaryDirectory.path + "/"
            guard directory.path.hasPrefix(safePrefix) else {
                throw SSHInvocationError.unsafeControlSocketDirectory
            }
            socketDirectory = directory
            arguments += [
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=60",
                "-o", "ControlPath=\(directory.path)/%C"
            ]
        } else {
            arguments += ["-o", "ControlMaster=no"]
        }

        arguments += [configuration.host, "/usr/bin/bash", "-s", "--"]

        return SSHInvocation(
            executableURL: Self.executableURL,
            arguments: arguments,
            standardInput: Data(script.utf8),
            timeout: timeout,
            controlSocketDirectory: socketDirectory,
            environment: minimalEnvironment()
        )
    }

    func makeReadOnlyFileListingInvocation(
        configuration: ServerConfiguration,
        path: String?,
        script: String = RemoteFileListingScript.source,
        timeout: Duration = .seconds(8)
    ) throws -> SSHInvocation {
        let encodedPath: String
        if let path {
            let bytes = Array(path.utf8)
            guard path.hasPrefix("/"),
                  !path.contains("\0"),
                  !path.contains("\n"),
                  !path.contains("\r"),
                  !bytes.isEmpty,
                  bytes.count <= 4_096 else {
                throw SSHInvocationError.invalidRemotePath
            }
            encodedPath = bytes.map { String(format: "%02x", $0) }.joined()
        } else {
            encodedPath = ""
        }

        let base = try makeReadOnlyCollectorInvocation(
            configuration: configuration,
            script: "",
            timeout: timeout
        )
        var arguments = base.arguments
        guard arguments.count >= 4 else {
            throw SSHInvocationError.invalidConfiguration(configuration.validationIssues)
        }
        arguments.removeLast(4)
        arguments += [
            configuration.host,
            "/usr/bin/bash",
            "-c",
            Self.shellQuoted(script),
            "vps-control-files",
            encodedPath
        ]

        return SSHInvocation(
            executableURL: base.executableURL,
            arguments: arguments,
            standardInput: Data(),
            timeout: timeout,
            controlSocketDirectory: base.controlSocketDirectory,
            environment: base.environment
        )
    }

    private func minimalEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        for key in ["LANG", "LC_CTYPE", "SSH_AUTH_SOCK"] {
            if let value = source[key], !value.contains("\0") {
                environment[key] = value
            }
        }
        return environment
    }

    private func validateIdentityFile(path: String) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileSystem.fileAttributes(atPath: path)
        } catch {
            throw SSHInvocationError.identityFileMissing
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw SSHInvocationError.identityFileNotRegular
        }
        if let permissions = attributes[.posixPermissions] as? NSNumber,
           permissions.intValue & 0o077 != 0 {
            throw SSHInvocationError.identityFilePermissionsTooOpen
        }
    }

    private func validateKnownHostsFile(path: String) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileSystem.fileAttributes(atPath: path)
        } catch {
            throw SSHInvocationError.knownHostsFileMissing
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw SSHInvocationError.knownHostsFileNotRegular
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
