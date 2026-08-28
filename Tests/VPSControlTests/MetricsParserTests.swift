import Foundation
import XCTest
@testable import VPSControl

final class MetricsParserTests: XCTestCase {
    private let parser = MetricsParser()

    func testParsesCompleteVersionOneSnapshot() throws {
        let payload = """
        VPSC/1
        boot\t62753482-0000-4000-8000-000000000001
        time\t1787938045
        cpu\t100\t2\t30\t800\t4\t1\t3\t0
        load\t0.08\t0.02\t0.01\t2/209
        uptime\t5141.52
        mem\t8083540\t7476484\t2097148\t2097000
        disk\t/\t61285326848\t5108469760\t56160079872\t9%
        default_net\tens3
        net\tens3\t1000\t2000
        net\tdocker0\t28\t306
        service\tssh\tactive
        service\tdocker\tactive
        service\tfail2ban\tactive
        docker_cli\tDocker version 29.7.2
        docker_socket_access\tpermission_locked
        end
        """

        let result = try parser.parse(payload)

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.snapshot.loadAverage?.oneMinute, 0.08)
        XCTAssertEqual(result.snapshot.memoryTotalBytes, 8_083_540)
        XCTAssertEqual(result.snapshot.rootDiskPercent, 9)
        XCTAssertEqual(result.snapshot.networks.count, 2)
        XCTAssertEqual(result.snapshot.networks.first?.interface, "ens3")
        XCTAssertEqual(result.snapshot.networks.first?.isDefault, true)
        XCTAssertEqual(result.snapshot.services.first?.state, .active)
        XCTAssertEqual(result.snapshot.dockerSocketAccess, .permissionLocked)
    }

    func testUnknownRecordIsIgnoredWithoutReflectingPayload() throws {
        let payload = """
        VPSC/1
        future_secret_record\tdo-not-echo-this-value
        uptime\t10
        end
        """

        let result = try parser.parse(payload)

        XCTAssertEqual(result.snapshot.uptimeSeconds, 10)
        let unknownWarning = try XCTUnwrap(
            result.warnings.first(where: { $0.reason == .unknownRecord })
        )
        XCTAssertEqual(unknownWarning.record, "future_secret_record")
        XCTAssertFalse(String(describing: unknownWarning).contains("do-not-echo"))
    }

    func testMalformedAndPartialPayloadReturnsUsableSnapshotWithWarnings() throws {
        let payload = """
        VPSC/1
        uptime\t120.5
        mem\tnot-a-number\t20\t0\t0
        disk\t/\t100\t150\t0\t150%
        """

        let result = try parser.parse(payload)

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.snapshot.uptimeSeconds, 120.5)
        XCTAssertNil(result.snapshot.memoryTotalBytes)
        XCTAssertTrue(result.warnings.map(\.reason).contains(.invalidValue))
        XCTAssertTrue(result.warnings.map(\.reason).contains(.missingEndMarker))
        XCTAssertTrue(result.warnings.contains(where: {
            $0.record == "cpu" && $0.reason == .missingRecord
        }))
    }

    func testRejectsMissingAndUnsupportedProtocolHeaders() {
        XCTAssertThrowsError(try parser.parse("uptime\t10\nend\n")) { error in
            XCTAssertEqual(error as? MetricsParserError, .missingHeader)
        }
        XCTAssertThrowsError(try parser.parse("VPSC/2\nuptime\t10\nend\n")) { error in
            XCTAssertEqual(error as? MetricsParserError, .unsupportedVersion)
        }
    }
}
