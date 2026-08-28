import XCTest
@testable import VPSControl

final class TerminalPastePolicyTests: XCTestCase {
    func testAllowsSingleLinePasteInStandardConnectedTerminal() {
        XCTAssertEqual(
            TerminalPastePolicy.evaluate("docker ps", privilegeState: .standard, isConnected: true),
            .allow
        )
    }

    func testWarnsForMultilinePasteThatExecutesImmediately() {
        let decision = TerminalPastePolicy.evaluate(
            "docker ps\nsystemctl status ssh\n",
            privilegeState: .standard,
            isConnected: true
        )

        guard case let .confirm(warnings) = decision else {
            return XCTFail("Expected confirmation")
        }
        XCTAssertTrue(warnings.contains(.multipleLines(lineCount: 3)))
        XCTAssertTrue(warnings.contains(.trailingReturn))
    }

    func testWarnsForEveryPasteInPrivilegedTerminal() {
        let decision = TerminalPastePolicy.evaluate(
            "id",
            privilegeState: .elevating,
            isConnected: true
        )

        XCTAssertEqual(decision, .confirm(warnings: [.privilegedSession]))
    }

    func testBlocksPasteWhenDisconnected() {
        XCTAssertEqual(
            TerminalPastePolicy.evaluate("id", privilegeState: .standard, isConnected: false),
            .block(reason: "Terminal bağlı deyil.")
        )
    }

    func testWarnsForControlCharactersAndLargePayload() {
        let payload = String(repeating: "a", count: TerminalPastePolicy.largePayloadThreshold + 1) + "\u{1B}"
        let decision = TerminalPastePolicy.evaluate(payload, privilegeState: .standard, isConnected: true)

        guard case let .confirm(warnings) = decision else {
            return XCTFail("Expected confirmation")
        }
        XCTAssertTrue(warnings.contains(.controlCharacters))
        XCTAssertTrue(warnings.contains(.largePayload(byteCount: payload.lengthOfBytes(using: .utf8))))
    }
}
