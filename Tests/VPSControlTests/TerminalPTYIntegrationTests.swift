import SwiftTerm
import XCTest
@testable import VPSControl

@MainActor
final class TerminalPTYIntegrationTests: XCTestCase {
    func testPTYRoundTripResizeAndTermination() async {
        let receivedEcho = expectation(description: "PTY returned terminal input")
        let view = TerminalProbeView(frame: .init(x: 0, y: 0, width: 900, height: 520))
        var didReceiveEcho = false
        view.onText = { text in
            if !didReceiveEcho, text.contains("vps-control-pty-check") {
                didReceiveEcho = true
                receivedEcho.fulfill()
            }
        }

        view.startProcess(executable: "/bin/cat")
        XCTAssertTrue(view.process.running)

        view.resize(cols: 100, rows: 32)
        XCTAssertEqual(view.getTerminal().cols, 100)
        XCTAssertEqual(view.getTerminal().rows, 32)

        view.send(txt: "vps-control-pty-check\r")
        await fulfillment(of: [receivedEcho], timeout: 2)

        view.terminate()
        XCTAssertFalse(view.process.running)
    }
}

@MainActor
private final class TerminalProbeView: LocalProcessTerminalView {
    var onText: ((String) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        if let text = String(bytes: slice, encoding: .utf8) {
            onText?(text)
        }
    }
}
