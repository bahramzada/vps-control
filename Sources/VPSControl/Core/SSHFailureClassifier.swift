import Foundation

struct SSHFailureClassification: Equatable, Sendable {
    let connectionState: ConnectionState
    let metricState: MetricState
    let failure: MetricsCollectionFailure
}

enum SSHFailureClassifier {
    static func classify(exitCode: Int32, standardError: Data) -> SSHFailureClassification {
        let message = String(data: standardError.prefix(8_192), encoding: .utf8)?.lowercased() ?? ""

        if message.contains("remote host identification has changed")
            || message.contains("host key verification failed")
            || message.contains("offending ") && message.contains("key") {
            return .init(
                connectionState: .hostKeyMismatch,
                metricState: .offline,
                failure: .hostKeyMismatch
            )
        }

        if message.contains("permission denied (publickey")
            || message.contains("no more authentication methods to try") {
            return .init(
                connectionState: .authFailed,
                metricState: .offline,
                failure: .authenticationFailed
            )
        }

        if exitCode == 255,
           message.contains("connection timed out") || message.contains("operation timed out") {
            return .init(
                connectionState: .offline,
                metricState: .timeout,
                failure: .timeout
            )
        }

        if exitCode == 255 {
            return .init(
                connectionState: .offline,
                metricState: .offline,
                failure: .connectionFailed
            )
        }

        return .init(
            connectionState: .degraded,
            metricState: .parseError,
            failure: .remoteCommandFailed
        )
    }

    static func classify(invocationError: SSHInvocationError) -> SSHFailureClassification {
        switch invocationError {
        case .invalidConfiguration, .invalidTimeout, .unsafeControlSocketDirectory, .invalidRemotePath:
            return .init(connectionState: .offline, metricState: .offline, failure: .invalidConfiguration)
        case .sshExecutableUnavailable:
            return .init(connectionState: .offline, metricState: .offline, failure: .localSSHUnavailable)
        case .identityFileMissing, .identityFileNotRegular:
            return .init(connectionState: .authFailed, metricState: .offline, failure: .identityFileUnavailable)
        case .identityFilePermissionsTooOpen:
            return .init(connectionState: .authFailed, metricState: .offline, failure: .identityFilePermissions)
        case .knownHostsFileMissing, .knownHostsFileNotRegular:
            return .init(connectionState: .hostKeyMismatch, metricState: .offline, failure: .knownHostsUnavailable)
        }
    }
}
