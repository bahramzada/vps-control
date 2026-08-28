import Foundation

protocol RemoteDirectoryBrowsing: Sendable {
    func listDirectory(
        configuration: ServerConfiguration,
        path: String?,
        timeout: Duration
    ) async throws -> RemoteDirectoryListing
}

actor RemoteFileBrowser: RemoteDirectoryBrowsing {
    private let invocationBuilder: SSHInvocationBuilder
    private let runner: any RemoteCommandRunning
    private let parser: RemoteFileListingParser

    init(
        invocationBuilder: SSHInvocationBuilder = SSHInvocationBuilder(),
        runner: any RemoteCommandRunning = SSHProcessRunner(),
        parser: RemoteFileListingParser = RemoteFileListingParser()
    ) {
        self.invocationBuilder = invocationBuilder
        self.runner = runner
        self.parser = parser
    }

    func listDirectory(
        configuration: ServerConfiguration,
        path: String?,
        timeout: Duration = .seconds(8)
    ) async throws -> RemoteDirectoryListing {
        let invocation: SSHInvocation
        do {
            invocation = try invocationBuilder.makeReadOnlyFileListingInvocation(
                configuration: configuration,
                path: path,
                timeout: timeout
            )
        } catch SSHInvocationError.invalidRemotePath {
            throw RemoteFileBrowserError.invalidPath
        } catch {
            throw RemoteFileBrowserError.invalidConfiguration
        }

        do {
            let output = try await runner.run(invocation)
            guard output.exitCode == 0 else {
                let classification = SSHFailureClassifier.classify(
                    exitCode: output.exitCode,
                    standardError: output.standardError
                )
                throw Self.browserError(for: classification.failure)
            }

            do {
                return try parser.parse(output.standardOutput)
            } catch let error as RemoteFileListingParserError {
                switch error {
                case let .remote(browserError):
                    throw browserError
                case .unsupportedVersion, .missingHeader:
                    throw RemoteFileBrowserError.protocolMismatch
                case .emptyPayload, .malformedRecord, .missingPath, .missingEndMarker:
                    throw RemoteFileBrowserError.malformedResponse
                }
            }
        } catch RemoteCommandRunnerError.timeout {
            throw RemoteFileBrowserError.timeout
        } catch RemoteCommandRunnerError.cancelled, is CancellationError {
            throw RemoteFileBrowserError.cancelled
        } catch let error as RemoteFileBrowserError {
            throw error
        } catch {
            throw RemoteFileBrowserError.connectionFailed
        }
    }

    private static func browserError(for failure: MetricsCollectionFailure) -> RemoteFileBrowserError {
        switch failure {
        case .hostKeyMismatch, .knownHostsUnavailable:
            return .hostKeyMismatch
        case .authenticationFailed, .identityFileUnavailable, .identityFilePermissions:
            return .authenticationFailed
        case .timeout:
            return .timeout
        case .cancelled:
            return .cancelled
        case .invalidConfiguration, .localSSHUnavailable:
            return .invalidConfiguration
        case .connectionFailed, .remoteCommandFailed, .protocolMismatch, .malformedResponse:
            return .connectionFailed
        }
    }
}
