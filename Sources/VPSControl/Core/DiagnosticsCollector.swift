import Foundation

actor DiagnosticsCollector {
    static let activeRefreshInterval: Duration = .seconds(300)
    static let backgroundRefreshInterval: Duration = .seconds(1_800)

    private let invocationBuilder: SSHInvocationBuilder
    private let runner: any RemoteCommandRunning
    private let parser: DiagnosticsParser

    init(
        invocationBuilder: SSHInvocationBuilder = SSHInvocationBuilder(),
        runner: any RemoteCommandRunning = SSHProcessRunner(),
        parser: DiagnosticsParser = DiagnosticsParser()
    ) {
        self.invocationBuilder = invocationBuilder
        self.runner = runner
        self.parser = parser
    }

    func collect(
        configuration: ServerConfiguration,
        timeout: Duration = .seconds(12)
    ) async -> DiagnosticsCollectionResult {
        let invocation: SSHInvocation
        do {
            invocation = try invocationBuilder.makeReadOnlyCollectorInvocation(
                configuration: configuration,
                script: RemoteDiagnosticsCollectorScript.source,
                timeout: timeout
            )
        } catch let error as SSHInvocationError {
            return DiagnosticsCollectionResult(
                diagnostics: nil,
                failure: SSHFailureClassifier.classify(invocationError: error).failure
            )
        } catch {
            return DiagnosticsCollectionResult(diagnostics: nil, failure: .invalidConfiguration)
        }

        do {
            let output = try await runner.run(invocation)
            guard output.exitCode == 0 else {
                return DiagnosticsCollectionResult(
                    diagnostics: nil,
                    failure: SSHFailureClassifier.classify(
                        exitCode: output.exitCode,
                        standardError: output.standardError
                    ).failure
                )
            }
            do {
                return DiagnosticsCollectionResult(
                    diagnostics: try parser.parse(output.standardOutput),
                    failure: nil
                )
            } catch DiagnosticsParserError.unsupportedVersion,
                    DiagnosticsParserError.missingHeader {
                return DiagnosticsCollectionResult(diagnostics: nil, failure: .protocolMismatch)
            } catch {
                return DiagnosticsCollectionResult(diagnostics: nil, failure: .malformedResponse)
            }
        } catch RemoteCommandRunnerError.timeout {
            return DiagnosticsCollectionResult(diagnostics: nil, failure: .timeout)
        } catch RemoteCommandRunnerError.cancelled, is CancellationError {
            return DiagnosticsCollectionResult(diagnostics: nil, failure: .cancelled)
        } catch {
            return DiagnosticsCollectionResult(diagnostics: nil, failure: .connectionFailed)
        }
    }
}
