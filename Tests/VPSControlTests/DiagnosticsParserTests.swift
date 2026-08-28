import Foundation
import XCTest
@testable import VPSControl

final class DiagnosticsParserTests: XCTestCase {
    func testParsesCompleteDiagnosticsPayload() throws {
        let diagnostics = try DiagnosticsParser().parse(Data(completePayload.utf8))

        XCTAssertEqual(diagnostics.platform.osID, "ubuntu")
        XCTAssertEqual(diagnostics.platform.versionID, "24.04")
        XCTAssertEqual(diagnostics.platform.prettyName, "Ubuntu 24.04.4 LTS")
        XCTAssertEqual(diagnostics.updates.availability, .available)
        XCTAssertEqual(diagnostics.updates.pending, 5)
        XCTAssertEqual(diagnostics.updates.security, 2)
        XCTAssertTrue(diagnostics.rebootRequired)
        XCTAssertEqual(diagnostics.failedUnitsTotal, 1)
        XCTAssertEqual(diagnostics.failedUnits.first?.name, "example.service")
        XCTAssertEqual(diagnostics.listenersTotal, 2)
        XCTAssertEqual(diagnostics.listeners.map(\.port), [22, 53])
        XCTAssertEqual(diagnostics.listeners.first?.scope, .wildcard)
    }

    func testParsesUnavailableSummariesWithoutInventingZeroDetails() throws {
        let payload = """
        VPSD/1
        time\t1760000000
        platform\tlinux\tunknown\tLinux\tserver\t6.8.0\tx86_64
        updates\tunavailable\t-\t-\t0
        reboot_required\t0
        failed_units\tunsupported\t0\t0
        listeners\tunsupported\t0\t0
        end
        """

        let diagnostics = try DiagnosticsParser().parse(Data(payload.utf8))

        XCTAssertEqual(diagnostics.updates.availability, .unavailable)
        XCTAssertNil(diagnostics.updates.pending)
        XCTAssertEqual(diagnostics.failedUnitsAvailability, .unsupported)
        XCTAssertEqual(diagnostics.listenersAvailability, .unsupported)
    }

    func testRejectsInconsistentSummaryAndOutOfRangePort() {
        let inconsistent = completePayload.replacingOccurrences(
            of: "failed_units\tavailable\t1\t0",
            with: "failed_units\tavailable\t2\t0"
        )
        let invalidPort = completePayload.replacingOccurrences(
            of: "listener\ttcp\tv4\twildcard\t0.0.0.0\t22",
            with: "listener\ttcp\tv4\twildcard\t0.0.0.0\t70000"
        )

        XCTAssertThrowsError(try DiagnosticsParser().parse(Data(inconsistent.utf8))) { error in
            XCTAssertEqual(error as? DiagnosticsParserError, .inconsistentSummary)
        }
        XCTAssertThrowsError(try DiagnosticsParser().parse(Data(invalidPort.utf8))) { error in
            XCTAssertEqual(error as? DiagnosticsParserError, .malformedRecord)
        }
    }

    func testRejectsDuplicateAndControlCharacterRecords() {
        let duplicate = completePayload.replacingOccurrences(
            of: "reboot_required\t1",
            with: "reboot_required\t1\nreboot_required\t0"
        )
        let controlCharacter = completePayload.replacingOccurrences(
            of: "Ubuntu 24.04.4 LTS",
            with: "Ubuntu\u{7} 24.04.4 LTS"
        )
        let trailingRecord = completePayload + "\ntime\t1760000001\n"

        XCTAssertThrowsError(try DiagnosticsParser().parse(Data(duplicate.utf8))) { error in
            XCTAssertEqual(error as? DiagnosticsParserError, .duplicateRecord)
        }
        XCTAssertThrowsError(try DiagnosticsParser().parse(Data(controlCharacter.utf8))) { error in
            XCTAssertEqual(error as? DiagnosticsParserError, .malformedRecord)
        }
        XCTAssertThrowsError(try DiagnosticsParser().parse(Data(trailingRecord.utf8))) { error in
            XCTAssertEqual(error as? DiagnosticsParserError, .malformedRecord)
        }
    }

    func testCollectorScriptDoesNotRunPackageMutationOrExposeProcesses() {
        let source = RemoteDiagnosticsCollectorScript.source.lowercased()

        XCTAssertFalse(source.contains("sudo"))
        XCTAssertFalse(source.contains("apt-get"))
        XCTAssertFalse(source.contains("apt update"))
        XCTAssertFalse(source.contains("apt-check"))
        XCTAssertFalse(source.contains("ss -p"))
        XCTAssertFalse(source.contains("process cmd"))
        XCTAssertTrue(source.contains("/var/lib/update-notifier/updates-available"))
        XCTAssertTrue(source.contains("ss -h -lnut"))
    }

    private var completePayload: String {
        """
        VPSD/1
        time\t1760000000
        platform\tubuntu\t24.04\tUbuntu 24.04.4 LTS\tjarvis\t6.8.0-138-generic\tx86_64
        updates\tavailable\t5\t2\t1759999900
        reboot_required\t1
        failed_units\tavailable\t1\t0
        failed_unit\texample.service\tfailed\tfailed
        listeners\tavailable\t2\t0
        listener\ttcp\tv4\twildcard\t0.0.0.0\t22
        listener\tudp\tv4\tloopback\t127.0.0.53%lo\t53
        end
        """
    }
}
