import XCTest
@testable import VPSControl

@MainActor
final class TerminalSessionSecurityTests: XCTestCase {
    func testPTYEnvironmentWhitelistsOnlyExpectedValues() {
        let environment = TerminalSession.sanitizedEnvironment(
            inherited: [
                "LANG": "az_AZ.UTF-8",
                "LC_ALL": "C",
                "SSH_AUTH_SOCK": "/private/tmp/agent.sock",
                "API_TOKEN": "must-not-leak",
                "AWS_SECRET_ACCESS_KEY": "must-not-leak"
            ],
            username: "raul",
            homeDirectory: "/Users/raul",
            isSocket: { $0 == "/private/tmp/agent.sock" }
        )

        XCTAssertTrue(environment.contains("HOME=/Users/raul"))
        XCTAssertTrue(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        XCTAssertTrue(environment.contains("LANG=az_AZ.UTF-8"))
        XCTAssertTrue(environment.contains("SSH_AUTH_SOCK=/private/tmp/agent.sock"))
        XCTAssertFalse(environment.contains { $0.contains("API_TOKEN") })
        XCTAssertFalse(environment.contains { $0.contains("AWS_SECRET_ACCESS_KEY") })
    }

    func testRejectsUntrustedLocaleAndNonSocketAgentPath() {
        let environment = TerminalSession.sanitizedEnvironment(
            inherited: [
                "LANG": "az_AZ.UTF-8\nSECRET=value",
                "SSH_AUTH_SOCK": "/private/tmp/not-a-socket"
            ],
            username: "raul",
            homeDirectory: "/Users/raul",
            isSocket: { _ in false }
        )

        XCTAssertFalse(environment.contains { $0.hasPrefix("LANG=") })
        XCTAssertFalse(environment.contains { $0.hasPrefix("SSH_AUTH_SOCK=") })
    }
}
