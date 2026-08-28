import Darwin
import Foundation

struct RemoteCommandResult: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

enum RemoteCommandRunnerError: Error, Equatable {
    case timeout
    case cancelled
    case launchFailed
    case localPreparationFailed
}

protocol RemoteCommandRunning: Sendable {
    func run(_ invocation: SSHInvocation) async throws -> RemoteCommandResult
}

struct SSHProcessRunner: RemoteCommandRunning, Sendable {
    func run(_ invocation: SSHInvocation) async throws -> RemoteCommandResult {
        try prepareControlSocketDirectory(invocation.controlSocketDirectory)

        do {
            return try await withThrowingTaskGroup(of: RemoteCommandResult.self) { group in
                group.addTask {
                    try await execute(invocation)
                }
                group.addTask {
                    try await Task.sleep(for: invocation.timeout)
                    try Task.checkCancellation()
                    throw RemoteCommandRunnerError.timeout
                }

                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw RemoteCommandRunnerError.cancelled
                }
                return first
            }
        } catch is CancellationError {
            throw RemoteCommandRunnerError.cancelled
        }
    }

    private func prepareControlSocketDirectory(_ directory: URL?) throws {
        guard let directory else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw RemoteCommandRunnerError.localPreparationFailed
        }
    }

    private func execute(_ invocation: SSHInvocation) async throws -> RemoteCommandResult {
        let execution = SSHProcessExecution(invocation: invocation)
        return try await withTaskCancellationHandler {
            try await execution.start()
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class SSHProcessExecution: @unchecked Sendable {
    private let invocation: SSHInvocation
    private let process = Process()
    private let standardInputPipe = Pipe()
    private let standardOutputPipe = Pipe()
    private let standardErrorPipe = Pipe()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RemoteCommandResult, Error>?
    private var cancelled = false
    private var completed = false

    init(invocation: SSHInvocation) {
        self.invocation = invocation
    }

    func start() async throws -> RemoteCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: RemoteCommandRunnerError.cancelled)
                return
            }
            self.continuation = continuation
            lock.unlock()

            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            process.standardInput = standardInputPipe
            process.standardOutput = standardOutputPipe
            process.standardError = standardErrorPipe
            process.terminationHandler = { [weak self] process in
                self?.finish(
                    .success(RemoteCommandResult(
                        exitCode: process.terminationStatus,
                        standardOutput: self?.standardOutputPipe.fileHandleForReading.readDataToEndOfFile() ?? Data(),
                        standardError: self?.standardErrorPipe.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    ))
                )
            }

            lock.lock()
            let shouldAbortBeforeLaunch = cancelled
            lock.unlock()
            if shouldAbortBeforeLaunch {
                finish(.failure(RemoteCommandRunnerError.cancelled))
                return
            }

            do {
                try process.run()
                standardInputPipe.fileHandleForWriting.write(invocation.standardInput)
                try? standardInputPipe.fileHandleForWriting.close()

                lock.lock()
                let shouldCancel = cancelled
                lock.unlock()
                if shouldCancel {
                    terminateProcess()
                }
            } catch {
                try? standardInputPipe.fileHandleForWriting.close()
                finish(.failure(RemoteCommandRunnerError.launchFailed))
            }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let isCompleted = completed
        lock.unlock()

        guard !isCompleted else {
            return
        }
        if process.isRunning {
            terminateProcess()
        }
    }

    private func terminateProcess() {
        process.terminate()
        let processIdentifier = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak process] in
            guard let process, process.isRunning else {
                return
            }
            kill(processIdentifier, SIGKILL)
        }
    }

    private func finish(_ result: Result<RemoteCommandResult, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let wasCancelled = cancelled
        lock.unlock()

        guard let continuation else {
            return
        }
        if wasCancelled {
            continuation.resume(throwing: RemoteCommandRunnerError.cancelled)
        } else {
            continuation.resume(with: result)
        }
    }
}
