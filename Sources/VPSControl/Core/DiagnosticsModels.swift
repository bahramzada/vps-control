import Foundation

enum DiagnosticsAvailability: String, Equatable, Sendable {
    case available
    case unavailable
    case unsupported
    case invalid
}

struct PlatformMetric: Equatable, Sendable {
    let osID: String
    let versionID: String
    let prettyName: String
    let hostname: String
    let kernelRelease: String
    let architecture: String
}

struct PackageUpdateMetric: Equatable, Sendable {
    let availability: DiagnosticsAvailability
    let pending: UInt?
    let security: UInt?
    let cacheUpdatedAt: Date?
}

struct FailedUnitMetric: Identifiable, Equatable, Sendable {
    var id: String { name }

    let name: String
    let activeState: String
    let subState: String
}

enum ListenerTransport: String, Equatable, Sendable {
    case tcp
    case udp
}

enum ListenerFamily: String, Equatable, Sendable {
    case v4
    case v6
}

enum ListenerScope: String, Equatable, Sendable {
    case wildcard
    case loopback
    case specific
}

struct ListenerMetric: Identifiable, Equatable, Sendable {
    var id: String { "\(transport.rawValue)-\(family.rawValue)-\(address)-\(port)" }

    let transport: ListenerTransport
    let family: ListenerFamily
    let scope: ListenerScope
    let address: String
    let port: UInt16
}

struct ServerDiagnostics: Equatable, Sendable {
    let collectedAt: Date
    let platform: PlatformMetric
    let updates: PackageUpdateMetric
    let rebootRequired: Bool
    let failedUnitsAvailability: DiagnosticsAvailability
    let failedUnits: [FailedUnitMetric]
    let failedUnitsTotal: Int
    let failedUnitsTruncated: Bool
    let listenersAvailability: DiagnosticsAvailability
    let listeners: [ListenerMetric]
    let listenersTotal: Int
    let listenersTruncated: Bool
}

struct DiagnosticsCollectionResult: Equatable, Sendable {
    let diagnostics: ServerDiagnostics?
    let failure: MetricsCollectionFailure?
}
