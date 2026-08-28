import Foundation

actor SSHClient {
    private let invocationBuilder: SSHInvocationBuilder
    private let runner: any RemoteCommandRunning
    private let parser: MetricsParser
    private var previousSnapshots: [UUID: ServerSnapshot] = [:]

    init(
        invocationBuilder: SSHInvocationBuilder = SSHInvocationBuilder(),
        runner: any RemoteCommandRunning = SSHProcessRunner(),
        parser: MetricsParser = MetricsParser()
    ) {
        self.invocationBuilder = invocationBuilder
        self.runner = runner
        self.parser = parser
    }

    func collect(
        configuration: ServerConfiguration,
        timeout: Duration = .seconds(12)
    ) async -> MetricsCollectionResult {
        let invocation: SSHInvocation
        do {
            invocation = try invocationBuilder.makeReadOnlyCollectorInvocation(
                configuration: configuration,
                timeout: timeout
            )
        } catch let error as SSHInvocationError {
            let classification = SSHFailureClassifier.classify(invocationError: error)
            return MetricsCollectionResult(
                snapshot: nil,
                connectionState: classification.connectionState,
                metricState: classification.metricState,
                failure: classification.failure
            )
        } catch {
            return MetricsCollectionResult(
                snapshot: nil,
                connectionState: .offline,
                metricState: .offline,
                failure: .invalidConfiguration
            )
        }

        do {
            let output = try await runner.run(invocation)
            guard output.exitCode == 0 else {
                let classification = SSHFailureClassifier.classify(
                    exitCode: output.exitCode,
                    standardError: output.standardError
                )
                return MetricsCollectionResult(
                    snapshot: nil,
                    connectionState: classification.connectionState,
                    metricState: classification.metricState,
                    failure: classification.failure
                )
            }

            do {
                let parsed = try parser.parse(output.standardOutput)
                var snapshot = parsed.snapshot
                applyRates(to: &snapshot, previous: previousSnapshots[configuration.id])
                previousSnapshots[configuration.id] = snapshot

                return MetricsCollectionResult(
                    snapshot: snapshot,
                    connectionState: parsed.isComplete ? .online : .degraded,
                    metricState: parsed.warnings.isEmpty ? .fresh : .partial(parsed.warnings),
                    failure: parsed.isComplete ? nil : .malformedResponse
                )
            } catch MetricsParserError.unsupportedVersion, MetricsParserError.missingHeader {
                return MetricsCollectionResult(
                    snapshot: nil,
                    connectionState: .protocolMismatch,
                    metricState: .parseError,
                    failure: .protocolMismatch
                )
            } catch {
                return MetricsCollectionResult(
                    snapshot: nil,
                    connectionState: .degraded,
                    metricState: .parseError,
                    failure: .malformedResponse
                )
            }
        } catch RemoteCommandRunnerError.timeout {
            return MetricsCollectionResult(
                snapshot: nil,
                connectionState: .offline,
                metricState: .timeout,
                failure: .timeout
            )
        } catch RemoteCommandRunnerError.cancelled, is CancellationError {
            return MetricsCollectionResult(
                snapshot: nil,
                connectionState: .cancelled,
                metricState: .cancelled,
                failure: .cancelled
            )
        } catch {
            return MetricsCollectionResult(
                snapshot: nil,
                connectionState: .offline,
                metricState: .offline,
                failure: .connectionFailed
            )
        }
    }

    func forgetPreviousSample(for serverID: UUID) {
        previousSnapshots.removeValue(forKey: serverID)
    }

    private func applyRates(to snapshot: inout ServerSnapshot, previous: ServerSnapshot?) {
        guard let previous,
              previous.bootID == snapshot.bootID,
              snapshot.collectedAt > previous.collectedAt else {
            return
        }

        if let currentCPU = snapshot.cpuCounters,
           let previousCPU = previous.cpuCounters,
           currentCPU.total >= previousCPU.total,
           currentCPU.idleTotal >= previousCPU.idleTotal {
            let totalDelta = currentCPU.total - previousCPU.total
            let idleDelta = currentCPU.idleTotal - previousCPU.idleTotal
            if totalDelta > 0, idleDelta <= totalDelta {
                snapshot.cpuPercent = Double(totalDelta - idleDelta) / Double(totalDelta) * 100
            }
        }

        let elapsed = snapshot.collectedAt.timeIntervalSince(previous.collectedAt)
        guard elapsed > 0 else {
            return
        }
        let previousByInterface = Dictionary(uniqueKeysWithValues: previous.networks.map { ($0.interface, $0) })
        snapshot.networks = snapshot.networks.map { current in
            guard let prior = previousByInterface[current.interface],
                  current.receivedBytes >= prior.receivedBytes,
                  current.transmittedBytes >= prior.transmittedBytes else {
                return current
            }
            return NetworkMetric(
                interface: current.interface,
                receivedBytes: current.receivedBytes,
                transmittedBytes: current.transmittedBytes,
                receivedBytesPerSecond: Double(current.receivedBytes - prior.receivedBytes) / elapsed,
                transmittedBytesPerSecond: Double(current.transmittedBytes - prior.transmittedBytes) / elapsed,
                isDefault: current.isDefault
            )
        }
    }
}
