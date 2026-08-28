import Foundation

struct ServerConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var displayName: String
    var host: String
    var user: String
    var port: UInt16
    var identityFilePath: String
    var knownHostsFilePath: String
    var multiplexingEnabled: Bool

    init(
        id: UUID = UUID(),
        displayName: String = "Server",
        host: String,
        user: String,
        port: UInt16 = 22,
        identityFilePath: String,
        knownHostsFilePath: String,
        multiplexingEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.user = user
        self.port = port
        self.identityFilePath = identityFilePath
        self.knownHostsFilePath = knownHostsFilePath
        self.multiplexingEnabled = multiplexingEnabled
    }

    var isValid: Bool {
        validationIssues.isEmpty
    }

    var validationIssues: [ServerConfigurationValidationIssue] {
        var issues: [ServerConfigurationValidationIssue] = []

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingDisplayName)
        }
        if !Self.isValidHost(host) {
            issues.append(.invalidHost)
        }
        if !Self.isValidUser(user) {
            issues.append(.invalidUser)
        }
        if port == 0 {
            issues.append(.invalidPort)
        }
        if !Self.isSafeAbsolutePath(identityFilePath) {
            issues.append(.invalidIdentityFilePath)
        }
        if !Self.isSafeAbsolutePath(knownHostsFilePath) {
            issues.append(.invalidKnownHostsFilePath)
        }

        return issues
    }

    private static func isValidHost(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 253,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.hasPrefix("-"),
              !value.contains("@") else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isValidUser(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 64,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.hasPrefix("-") else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeAbsolutePath(_ value: String) -> Bool {
        guard value.hasPrefix("/"),
              !value.contains("\0"),
              !value.contains("\n"),
              !value.contains("\r") else {
            return false
        }
        return URL(fileURLWithPath: value).standardizedFileURL.path == value
    }
}
enum ServerConfigurationValidationIssue: String, Codable, Equatable, Sendable {
    case missingDisplayName
    case invalidHost
    case invalidUser
    case invalidPort
    case invalidIdentityFilePath
    case invalidKnownHostsFilePath
}
