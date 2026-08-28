import Foundation
import XCTest
@testable import VPSControl

final class RemoteFileListingParserTests: XCTestCase {
    func testParsesMetadataAndSortsDirectoriesBeforeFiles() throws {
        let payload = nulPayload([
            "VPSF/1",
            "path", "/home/jarvis",
            "entry", ".bashrc", "f", "42", "1760000000.25", "-rw-r--r--", "jarvis", "jarvis",
            "entry", "Projects", "d", "4096", "1760000001", "drwxr-xr-x", "jarvis", "jarvis",
            "truncated", "0",
            "end"
        ])

        let listing = try RemoteFileListingParser().parse(payload)

        XCTAssertEqual(listing.path, "/home/jarvis")
        XCTAssertEqual(listing.parentPath, "/home")
        XCTAssertEqual(listing.entries.map(\.name), ["Projects", ".bashrc"])
        XCTAssertEqual(listing.entries.first?.path, "/home/jarvis/Projects")
        XCTAssertEqual(listing.entries.first?.kind, .directory)
        XCTAssertEqual(listing.entries.last?.sizeBytes, 42)
        XCTAssertEqual(listing.entries.last?.permissions, "-rw-r--r--")
        XCTAssertFalse(listing.isTruncated)
    }

    func testParsesRootChildPathWithoutDoubleSlash() throws {
        let payload = nulPayload([
            "VPSF/1",
            "path", "/",
            "entry", "etc", "d", "4096", "1760000000", "drwxr-xr-x", "root", "root",
            "truncated", "1",
            "end"
        ])

        let listing = try RemoteFileListingParser().parse(payload)

        XCTAssertNil(listing.parentPath)
        XCTAssertEqual(listing.entries.first?.path, "/etc")
        XCTAssertTrue(listing.isTruncated)
    }

    func testMapsTypedRemoteError() {
        let payload = nulPayload(["VPSF/1", "error", "permission_denied", "end"])

        XCTAssertThrowsError(try RemoteFileListingParser().parse(payload)) { error in
            XCTAssertEqual(
                error as? RemoteFileListingParserError,
                .remote(.permissionDenied)
            )
        }
    }

    func testRejectsTraversalNameAndMissingEndMarker() {
        let traversalPayload = nulPayload([
            "VPSF/1",
            "path", "/home/jarvis",
            "entry", "..", "d", "4096", "1760000000", "drwxr-xr-x", "jarvis", "jarvis",
            "end"
        ])
        let incompletePayload = nulPayload(["VPSF/1", "path", "/home/jarvis"])

        XCTAssertThrowsError(try RemoteFileListingParser().parse(traversalPayload)) { error in
            XCTAssertEqual(error as? RemoteFileListingParserError, .malformedRecord)
        }
        XCTAssertThrowsError(try RemoteFileListingParser().parse(incompletePayload)) { error in
            XCTAssertEqual(error as? RemoteFileListingParserError, .missingEndMarker)
        }
    }

    private func nulPayload(_ fields: [String]) -> Data {
        Data((fields.joined(separator: "\0") + "\0").utf8)
    }
}
