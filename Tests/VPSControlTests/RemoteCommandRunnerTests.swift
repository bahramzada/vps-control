import Foundation
import XCTest
@testable import VPSControl

final class RemoteCommandRunnerTests: XCTestCase {
    func testTerminatesProcessAtTimeout() async {
        let invocation = SSHInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            standardInput: Data(),
            timeout: .milliseconds(20),
            controlSocketDirectory: nil,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        do {
            _ = try await SSHProcessRunner().run(invocation)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? RemoteCommandRunnerError, .timeout)
        }
    }

    func testTaskCancellationTerminatesProcess() async {
        let invocation = SSHInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            standardInput: Data(),
            timeout: .seconds(5),
            controlSocketDirectory: nil,
            environment: ["PATH": "/usr/bin:/bin"]
        )
        let task = Task {
            try await SSHProcessRunner().run(invocation)
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? RemoteCommandRunnerError, .cancelled)
        }
    }
}
