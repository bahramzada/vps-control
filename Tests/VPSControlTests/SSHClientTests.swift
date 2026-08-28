import Foundation
import XCTest
@testable import VPSControl

final class SSHClientTests: XCTestCase {
    func testComputesCPUNetworkRatesLocallyFromTwoSmallSnapshots() async throws {
        let runner = SSHSequenceRunner(outputs: [
            Self.snapshot(time: 1_000, cpu: [100, 0, 50, 850, 0, 0, 0, 0], rx: 1_000, tx: 2_000),
            Self.snapshot(time: 1_010, cpu: [140, 0, 70, 940, 0, 0, 0, 0], rx: 1_500, tx: 2_800)
        ])
        let builder = SSHInvocationBuilder(fileSystem: SSHClientTestFileSystem())
        let client = SSHClient(invocationBuilder: builder, runner: runner)
        let configuration = ServerConfiguration(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            host: "example.test",
            user: "jarvis",
            identityFilePath: "/Users/test/.ssh/key",
            knownHostsFilePath: "/Users/test/.ssh/known_hosts",
            multiplexingEnabled: false
        )

        let first = await client.collect(configuration: configuration)
        let second = await client.collect(configuration: configuration)

        XCTAssertEqual(first.connectionState, .online)
        XCTAssertNil(first.snapshot?.cpuPercent)
        XCTAssertEqual(second.snapshot?.cpuPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(second.snapshot?.networks.first?.receivedBytesPerSecond ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(second.snapshot?.networks.first?.transmittedBytesPerSecond ?? -1, 80, accuracy: 0.001)
    }

    private static func snapshot(
        time: Int,
        cpu: [UInt64],
        rx: UInt64,
        tx: UInt64
    ) -> Data {
        Data("""
        VPSC/1
        boot\t62753482-0000-4000-8000-000000000001
        time\t\(time)
        cpu\t\(cpu.map(String.init).joined(separator: "\t"))
        load\t0.10\t0.05\t0.01\t1/100
        uptime\t500
        mem\t8000\t6000\t2000\t2000
        disk\t/\t10000\t1000\t9000\t10%
        default_net\tens3
        net\tens3\t\(rx)\t\(tx)
        docker_socket_access\tpermission_locked
        end
        """.utf8)
    }
}
private actor SSHSequenceRunner: RemoteCommandRunning {
    private var outputs: [Data]

    init(outputs: [Data]) {
        self.outputs = outputs
    }

    func run(_ invocation: SSHInvocation) async throws -> RemoteCommandResult {
        guard !outputs.isEmpty else {
            throw RemoteCommandRunnerError.launchFailed
        }
        return RemoteCommandResult(
            exitCode: 0,
            standardOutput: outputs.removeFirst(),
            standardError: Data()
        )
    }
}

private struct SSHClientTestFileSystem: SSHFileSystemChecking, @unchecked Sendable {
    func isExecutableFile(atPath path: String) -> Bool {
        path == "/usr/bin/ssh"
    }

    func fileAttributes(atPath path: String) throws -> [FileAttributeKey: Any] {
        switch path {
        case "/Users/test/.ssh/key":
            return [
                .type: FileAttributeType.typeRegular,
                .posixPermissions: NSNumber(value: 0o600)
            ]
        case "/Users/test/.ssh/known_hosts":
            return [.type: FileAttributeType.typeRegular]
        default:
            throw CocoaError(.fileNoSuchFile)
        }
    }
}
