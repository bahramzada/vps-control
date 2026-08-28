import Foundation
import XCTest
@testable import VPSControl

final class SSHFailureClassifierTests: XCTestCase {
    func testClassifiesHostKeyMismatchAsFailClosed() {
        let result = SSHFailureClassifier.classify(
            exitCode: 255,
            standardError: Data("WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!".utf8)
        )

        XCTAssertEqual(result.connectionState, .hostKeyMismatch)
        XCTAssertEqual(result.failure, .hostKeyMismatch)
    }

    func testClassifiesPublicKeyAuthenticationFailure() {
        let result = SSHFailureClassifier.classify(
            exitCode: 255,
            standardError: Data("Permission denied (publickey).".utf8)
        )

        XCTAssertEqual(result.connectionState, .authFailed)
        XCTAssertEqual(result.failure, .authenticationFailed)
    }

    func testClassifiesTimeoutAndGenericDisconnectSeparately() {
        let timeout = SSHFailureClassifier.classify(
            exitCode: 255,
            standardError: Data("ssh: connect to host redacted port 22: Operation timed out".utf8)
        )
        let disconnect = SSHFailureClassifier.classify(
            exitCode: 255,
            standardError: Data("Connection reset by peer".utf8)
        )

        XCTAssertEqual(timeout.metricState, .timeout)
        XCTAssertEqual(timeout.failure, .timeout)
        XCTAssertEqual(disconnect.connectionState, .offline)
        XCTAssertEqual(disconnect.failure, .connectionFailed)
    }
}
