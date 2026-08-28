import Foundation

enum ConnectionState: String, Codable, Equatable, Sendable {
    case connecting
    case online
    case degraded
    case offline
    case authFailed
    case hostKeyMismatch
    case protocolMismatch
    case cancelled
}

enum MetricState: Equatable, Sendable {
    case loading
    case fresh
    case partial([MetricParseWarning])
    case stale
    case unsupported
    case permissionLocked
    case timeout
    case parseError
    case offline
    case cancelled
}

struct MetricParseWarning: Equatable, Sendable {
    let line: Int
    let record: String
    let reason: MetricParseWarningReason
}

enum MetricParseWarningReason: String, Equatable, Sendable {
    case unknownRecord
    case malformedRecord
    case invalidValue
    case duplicateRecord
    case missingRecord
    case missingEndMarker
}

struct CPUTimeCounters: Equatable, Sendable {
    let user: UInt64
    let nice: UInt64
    let system: UInt64
    let idle: UInt64
    let ioWait: UInt64
    let irq: UInt64
    let softIRQ: UInt64
    let steal: UInt64

    var total: UInt64 {
        user &+ nice &+ system &+ idle &+ ioWait &+ irq &+ softIRQ &+ steal
    }

    var idleTotal: UInt64 {
        idle &+ ioWait
    }
}

struct LoadAverage: Equatable, Sendable {
    let oneMinute: Double
    let fiveMinutes: Double
    let fifteenMinutes: Double
    let runnableProcesses: Int?
    let totalProcesses: Int?
}

struct NetworkMetric: Equatable, Identifiable, Sendable {
    var id: String { interface }

    let interface: String
    let receivedBytes: UInt64
    let transmittedBytes: UInt64
    var receivedBytesPerSecond: Double?
    var transmittedBytesPerSecond: Double?
    let isDefault: Bool
}

struct ServiceMetric: Equatable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    let state: RemoteServiceState
}

enum RemoteServiceState: String, Codable, Equatable, Sendable {
    case active
    case inactive
    case failed
    case activating
    case deactivating
    case reloading
    case unknown

    init(remoteValue: String) {
        self = Self(rawValue: remoteValue) ?? .unknown
    }
}

enum DockerSocketAccess: String, Codable, Equatable, Sendable {
    case available
    case permissionLocked = "permission_locked"
    case unsupported
    case unknown

    init(remoteValue: String) {
        self = Self(rawValue: remoteValue) ?? .unknown
    }
}

struct ServerSnapshot: Equatable, Sendable {
    var cpuPercent: Double?
    var cpuCounters: CPUTimeCounters?
    var memoryTotalBytes: UInt64?
    var memoryAvailableBytes: UInt64?
    var swapTotalBytes: UInt64?
    var swapFreeBytes: UInt64?
    var rootDiskTotalBytes: UInt64?
    var rootDiskUsedBytes: UInt64?
    var rootDiskAvailableBytes: UInt64?
    var rootDiskPercent: Double?
    var loadAverage: LoadAverage?
    var uptimeSeconds: Double?
    var networks: [NetworkMetric]
    var services: [ServiceMetric]
    var collectedAt: Date
    var bootID: String?
    var defaultNetworkInterface: String?
    var dockerCLIVersion: String?
    var dockerSocketAccess: DockerSocketAccess

    init(
        cpuPercent: Double? = nil,
        cpuCounters: CPUTimeCounters? = nil,
        memoryTotalBytes: UInt64? = nil,
        memoryAvailableBytes: UInt64? = nil,
        swapTotalBytes: UInt64? = nil,
        swapFreeBytes: UInt64? = nil,
        rootDiskTotalBytes: UInt64? = nil,
        rootDiskUsedBytes: UInt64? = nil,
        rootDiskAvailableBytes: UInt64? = nil,
        rootDiskPercent: Double? = nil,
        loadAverage: LoadAverage? = nil,
        uptimeSeconds: Double? = nil,
        networks: [NetworkMetric] = [],
        services: [ServiceMetric] = [],
        collectedAt: Date = Date(),
        bootID: String? = nil,
        defaultNetworkInterface: String? = nil,
        dockerCLIVersion: String? = nil,
        dockerSocketAccess: DockerSocketAccess = .unknown
    ) {
        self.cpuPercent = cpuPercent
        self.cpuCounters = cpuCounters
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryAvailableBytes = memoryAvailableBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapFreeBytes = swapFreeBytes
        self.rootDiskTotalBytes = rootDiskTotalBytes
        self.rootDiskUsedBytes = rootDiskUsedBytes
        self.rootDiskAvailableBytes = rootDiskAvailableBytes
        self.rootDiskPercent = rootDiskPercent
        self.loadAverage = loadAverage
        self.uptimeSeconds = uptimeSeconds
        self.networks = networks
        self.services = services
        self.collectedAt = collectedAt
        self.bootID = bootID
        self.defaultNetworkInterface = defaultNetworkInterface
        self.dockerCLIVersion = dockerCLIVersion
        self.dockerSocketAccess = dockerSocketAccess
    }

    var memoryUsedBytes: UInt64? {
        guard let total = memoryTotalBytes,
              let available = memoryAvailableBytes,
              total >= available else {
            return nil
        }
        return total - available
    }

    var memoryUsedPercent: Double? {
        guard let used = memoryUsedBytes,
              let total = memoryTotalBytes,
              total > 0 else {
            return nil
        }
        return Double(used) / Double(total) * 100
    }

    var swapUsedBytes: UInt64? {
        guard let total = swapTotalBytes,
              let free = swapFreeBytes,
              total >= free else {
            return nil
        }
        return total - free
    }
}

enum MetricsCollectionFailure: String, Equatable, Sendable {
    case invalidConfiguration
    case localSSHUnavailable
    case identityFileUnavailable
    case identityFilePermissions
    case knownHostsUnavailable
    case hostKeyMismatch
    case authenticationFailed
    case connectionFailed
    case remoteCommandFailed
    case timeout
    case cancelled
    case protocolMismatch
    case malformedResponse
}

struct MetricsCollectionResult: Equatable, Sendable {
    let snapshot: ServerSnapshot?
    let connectionState: ConnectionState
    let metricState: MetricState
    let failure: MetricsCollectionFailure?
}
