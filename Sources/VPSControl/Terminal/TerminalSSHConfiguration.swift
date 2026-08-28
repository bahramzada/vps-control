import Foundation

struct TerminalSSHConfiguration: Equatable, Sendable {
    var displayName: String
    var host: String
    var port: UInt16
    var username: String
    var identityFileURL: URL
    var knownHostsFileURL: URL
    var controlPathURL: URL?

    init(
        displayName: String = "Jarvis VPS",
        host: String,
        port: UInt16 = 22,
        username: String = "jarvis",
        identityFileURL: URL,
        knownHostsFileURL: URL,
        controlPathURL: URL? = nil
    ) {
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        self.identityFileURL = identityFileURL
        self.knownHostsFileURL = knownHostsFileURL
        self.controlPathURL = controlPathURL
    }

    func validated(fileManager: FileManager = .default) throws -> TerminalSSHConfiguration {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            throw TerminalSSHValidationError.emptyDisplayName
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidHost(trimmedHost) else {
            throw TerminalSSHValidationError.invalidHost
        }

        guard port > 0 else {
            throw TerminalSSHValidationError.invalidPort
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidUsername(trimmedUsername) else {
            throw TerminalSSHValidationError.invalidUsername
        }

        let resolvedIdentity = try Self.validateRegularFile(
            identityFileURL,
            kind: .identity,
            fileManager: fileManager
        )
        try Self.validatePrivateKeyPermissions(resolvedIdentity, fileManager: fileManager)

        let resolvedKnownHosts = try Self.validateRegularFile(
            knownHostsFileURL,
            kind: .knownHosts,
            fileManager: fileManager
        )

        var resolvedControlPath: URL?
        if let controlPathURL {
            guard controlPathURL.isFileURL,
                  controlPathURL.path.hasPrefix("/"),
                  !controlPathURL.path.contains("\0"),
                  !controlPathURL.path.contains("\n"),
                  !controlPathURL.path.contains("\r") else {
                throw TerminalSSHValidationError.controlPathMustBeAbsolute
            }
            let parent = controlPathURL.deletingLastPathComponent().resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw TerminalSSHValidationError.controlPathDirectoryMissing
            }
            let parentAttributes = try fileManager.attributesOfItem(atPath: parent.path)
            guard let permissions = parentAttributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o077 == 0 else {
                throw TerminalSSHValidationError.controlPathDirectoryPermissionsTooOpen
            }
            resolvedControlPath = parent.appendingPathComponent(controlPathURL.lastPathComponent)
        }

        return TerminalSSHConfiguration(
            displayName: trimmedDisplayName,
            host: trimmedHost,
            port: port,
            username: trimmedUsername,
            identityFileURL: resolvedIdentity,
            knownHostsFileURL: resolvedKnownHosts,
            controlPathURL: resolvedControlPath
        )
    }

    private static func isValidHost(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253, !value.hasPrefix("-") else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]%")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("@")
            && !value.contains("..")
    }

    private static func isValidUsername(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, value.count <= 32 else {
            return false
        }
        let firstAllowed = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let remainingAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return firstAllowed.contains(first) && value.unicodeScalars.dropFirst().allSatisfy { remainingAllowed.contains($0) }
    }

    private enum FileKind {
        case identity
        case knownHosts
    }

    private static func validateRegularFile(
        _ url: URL,
        kind: FileKind,
        fileManager: FileManager
    ) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            switch kind {
            case .identity:
                throw TerminalSSHValidationError.identityFileMustBeAbsolute
            case .knownHosts:
                throw TerminalSSHValidationError.knownHostsFileMustBeAbsolute
            }
        }

        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            switch kind {
            case .identity:
                throw TerminalSSHValidationError.identityFileMissing
            case .knownHosts:
                throw TerminalSSHValidationError.knownHostsFileMissing
            }
        }
        let attributes = try fileManager.attributesOfItem(atPath: resolved.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            switch kind {
            case .identity:
                throw TerminalSSHValidationError.identityFileNotRegular
            case .knownHosts:
                throw TerminalSSHValidationError.knownHostsFileNotRegular
            }
        }
        guard fileManager.isReadableFile(atPath: resolved.path) else {
            switch kind {
            case .identity:
                throw TerminalSSHValidationError.identityFileUnreadable
            case .knownHosts:
                throw TerminalSSHValidationError.knownHostsFileUnreadable
            }
        }
        return resolved
    }

    private static func validatePrivateKeyPermissions(_ url: URL, fileManager: FileManager) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            throw TerminalSSHValidationError.identityFilePermissionsUnavailable
        }
        guard permissions.intValue & 0o077 == 0 else {
            throw TerminalSSHValidationError.identityFilePermissionsTooOpen
        }
    }
}

enum TerminalSSHValidationError: LocalizedError, Equatable {
    case emptyDisplayName
    case invalidHost
    case invalidPort
    case invalidUsername
    case identityFileMustBeAbsolute
    case identityFileMissing
    case identityFileNotRegular
    case identityFileUnreadable
    case identityFilePermissionsUnavailable
    case identityFilePermissionsTooOpen
    case knownHostsFileMustBeAbsolute
    case knownHostsFileMissing
    case knownHostsFileNotRegular
    case knownHostsFileUnreadable
    case controlPathMustBeAbsolute
    case controlPathDirectoryMissing
    case controlPathDirectoryPermissionsTooOpen

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            return "Server adı boş ola bilməz."
        case .invalidHost:
            return "SSH host etibarlı hostname və ya IP olmalıdır."
        case .invalidPort:
            return "SSH port 1–65535 aralığında olmalıdır."
        case .invalidUsername:
            return "SSH istifadəçi adı etibarlı deyil."
        case .identityFileMustBeAbsolute:
            return "SSH key üçün absolute local fayl yolu seçilməlidir."
        case .identityFileMissing:
            return "SSH private key faylı tapılmadı."
        case .identityFileNotRegular:
            return "SSH private key yolu regular fayl olmalıdır."
        case .identityFileUnreadable:
            return "SSH private key faylı oxuna bilmir."
        case .identityFilePermissionsUnavailable:
            return "SSH private key icazələri yoxlanıla bilmədi."
        case .identityFilePermissionsTooOpen:
            return "SSH private key yalnız cari istifadəçi üçün oxuna bilən olmalıdır (0600)."
        case .knownHostsFileMustBeAbsolute:
            return "known_hosts üçün absolute local fayl yolu seçilməlidir."
        case .knownHostsFileMissing:
            return "known_hosts faylı tapılmadı. Host açarı əvvəlcə etibarlı şəkildə əlavə edilməlidir."
        case .knownHostsFileNotRegular:
            return "known_hosts yolu regular fayl olmalıdır."
        case .knownHostsFileUnreadable:
            return "known_hosts faylı oxuna bilmir."
        case .controlPathMustBeAbsolute:
            return "SSH control socket üçün absolute local yol seçilməlidir."
        case .controlPathDirectoryMissing:
            return "SSH control socket qovluğu mövcud deyil."
        case .controlPathDirectoryPermissionsTooOpen:
            return "SSH control socket qovluğu yalnız cari istifadəçi üçün açıq olmalıdır (0700)."
        }
    }
}

struct TerminalSSHCommand: Equatable, Sendable {
    static let executable = "/usr/bin/ssh"

    let executable: String
    let arguments: [String]
}

enum TerminalSSHCommandBuilder {
    static func makeCommand(
        configuration: TerminalSSHConfiguration,
        fileManager: FileManager = .default
    ) throws -> TerminalSSHCommand {
        let configuration = try configuration.validated(fileManager: fileManager)
        var arguments = [
            "-F", "/dev/null",
            "-p", String(configuration.port),
            "-i", configuration.identityFileURL.path,
            "-o", "IdentitiesOnly=yes",
            "-o", "PubkeyAuthentication=yes",
            "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no",
            "-o", "ChallengeResponseAuthentication=no",
            "-o", "NumberOfPasswordPrompts=0",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(configuration.knownHostsFileURL.path)",
            "-o", "ForwardAgent=no",
            "-o", "ForwardX11=no",
            "-o", "ClearAllForwardings=yes",
            "-o", "PermitLocalCommand=no",
            "-o", "ConnectionAttempts=1",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3"
        ]

        if let controlPathURL = configuration.controlPathURL {
            arguments += [
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=60",
                "-o", "ControlPath=\(controlPathURL.path)"
            ]
        }

        arguments += [
            "-tt",
            "--",
            "\(configuration.username)@\(configuration.host)"
        ]

        return TerminalSSHCommand(executable: TerminalSSHCommand.executable, arguments: arguments)
    }
}
