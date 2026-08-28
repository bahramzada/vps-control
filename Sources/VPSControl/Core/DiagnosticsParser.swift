import Foundation

enum DiagnosticsParserError: Error, Equatable {
    case emptyPayload
    case payloadTooLarge
    case missingHeader
    case unsupportedVersion
    case malformedRecord
    case duplicateRecord
    case missingRequiredRecord
    case inconsistentSummary
    case missingEndMarker
}

struct DiagnosticsParser: Sendable {
    private static let maximumPayloadBytes = 65_536

    func parse(_ data: Data) throws -> ServerDiagnostics {
        guard !data.isEmpty else { throw DiagnosticsParserError.emptyPayload }
        guard data.count <= Self.maximumPayloadBytes else { throw DiagnosticsParserError.payloadTooLarge }
        guard let payload = String(data: data, encoding: .utf8) else {
            throw DiagnosticsParserError.malformedRecord
        }

        let lines = payload.split(separator: "\n", omittingEmptySubsequences: true)
        guard let first = lines.first else { throw DiagnosticsParserError.emptyPayload }
        guard first.hasPrefix("VPSD/") else { throw DiagnosticsParserError.missingHeader }
        guard first == "VPSD/1" else { throw DiagnosticsParserError.unsupportedVersion }

        var collectedAt: Date?
        var platform: PlatformMetric?
        var updates: PackageUpdateMetric?
        var rebootRequired: Bool?
        var failedSummary: (DiagnosticsAvailability, Int, Bool)?
        var failedUnits: [FailedUnitMetric] = []
        var listenerSummary: (DiagnosticsAvailability, Int, Bool)?
        var listeners: [ListenerMetric] = []
        var sawEnd = false

        for line in lines.dropFirst() {
            guard !sawEnd else { throw DiagnosticsParserError.malformedRecord }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let record = fields.first else { throw DiagnosticsParserError.malformedRecord }

            switch record {
            case "time":
                guard collectedAt == nil, fields.count == 2,
                      let epoch = Double(fields[1]), epoch.isFinite, epoch >= 0 else {
                    throw collectedAt == nil ? DiagnosticsParserError.malformedRecord : .duplicateRecord
                }
                collectedAt = Date(timeIntervalSince1970: epoch)

            case "platform":
                guard platform == nil else { throw DiagnosticsParserError.duplicateRecord }
                guard fields.count == 7,
                      Self.isIdentifier(fields[1]),
                      Self.isSafeText(fields[2], maximum: 64),
                      Self.isSafeText(fields[3], maximum: 200),
                      Self.isSafeText(fields[4], maximum: 200),
                      Self.isSafeText(fields[5], maximum: 200),
                      Self.isSafeText(fields[6], maximum: 64) else {
                    throw DiagnosticsParserError.malformedRecord
                }
                platform = PlatformMetric(
                    osID: fields[1],
                    versionID: fields[2],
                    prettyName: fields[3],
                    hostname: fields[4],
                    kernelRelease: fields[5],
                    architecture: fields[6]
                )

            case "updates":
                guard updates == nil else { throw DiagnosticsParserError.duplicateRecord }
                guard fields.count == 5,
                      let availability = DiagnosticsAvailability(rawValue: fields[1]),
                      let cacheEpoch = Double(fields[4]), cacheEpoch.isFinite, cacheEpoch >= 0 else {
                    throw DiagnosticsParserError.malformedRecord
                }
                let pending = Self.optionalUInt(fields[2])
                let security = Self.optionalUInt(fields[3])
                guard fields[2] == "-" || pending != nil,
                      fields[3] == "-" || security != nil,
                      availability != .available || (pending != nil && security != nil) else {
                    throw DiagnosticsParserError.malformedRecord
                }
                updates = PackageUpdateMetric(
                    availability: availability,
                    pending: pending,
                    security: security,
                    cacheUpdatedAt: cacheEpoch > 0 ? Date(timeIntervalSince1970: cacheEpoch) : nil
                )

            case "reboot_required":
                guard rebootRequired == nil, fields.count == 2,
                      fields[1] == "0" || fields[1] == "1" else {
                    throw rebootRequired == nil ? DiagnosticsParserError.malformedRecord : .duplicateRecord
                }
                rebootRequired = fields[1] == "1"

            case "failed_units":
                guard failedSummary == nil else { throw DiagnosticsParserError.duplicateRecord }
                guard fields.count == 4,
                      let availability = DiagnosticsAvailability(rawValue: fields[1]),
                      let total = Int(fields[2]), total >= 0, total <= 1_000_000,
                      let truncated = Self.boolean(fields[3]) else {
                    throw DiagnosticsParserError.malformedRecord
                }
                failedSummary = (availability, total, truncated)

            case "failed_unit":
                guard fields.count == 4,
                      failedUnits.count < RemoteDiagnosticsCollectorScript.maximumFailedUnits,
                      Self.isUnitName(fields[1]),
                      Self.isIdentifier(fields[2]),
                      Self.isIdentifier(fields[3]) else {
                    throw DiagnosticsParserError.malformedRecord
                }
                failedUnits.append(FailedUnitMetric(
                    name: fields[1],
                    activeState: fields[2],
                    subState: fields[3]
                ))

            case "listeners":
                guard listenerSummary == nil else { throw DiagnosticsParserError.duplicateRecord }
                guard fields.count == 4,
                      let availability = DiagnosticsAvailability(rawValue: fields[1]),
                      let total = Int(fields[2]), total >= 0, total <= 1_000_000,
                      let truncated = Self.boolean(fields[3]) else {
                    throw DiagnosticsParserError.malformedRecord
                }
                listenerSummary = (availability, total, truncated)

            case "listener":
                guard fields.count == 6,
                      listeners.count < RemoteDiagnosticsCollectorScript.maximumListeners,
                      let transport = ListenerTransport(rawValue: fields[1]),
                      let family = ListenerFamily(rawValue: fields[2]),
                      let scope = ListenerScope(rawValue: fields[3]),
                      Self.isAddress(fields[4]),
                      let port = UInt16(fields[5]), port > 0 else {
                    throw DiagnosticsParserError.malformedRecord
                }
                listeners.append(ListenerMetric(
                    transport: transport,
                    family: family,
                    scope: scope,
                    address: fields[4],
                    port: port
                ))

            case "end":
                guard fields.count == 1 else { throw DiagnosticsParserError.malformedRecord }
                sawEnd = true

            default:
                throw DiagnosticsParserError.malformedRecord
            }
        }

        guard sawEnd else { throw DiagnosticsParserError.missingEndMarker }
        guard let collectedAt, let platform, let updates, let rebootRequired,
              let failedSummary, let listenerSummary else {
            throw DiagnosticsParserError.missingRequiredRecord
        }
        try Self.validate(
            availability: failedSummary.0,
            total: failedSummary.1,
            truncated: failedSummary.2,
            detailCount: failedUnits.count
        )
        try Self.validate(
            availability: listenerSummary.0,
            total: listenerSummary.1,
            truncated: listenerSummary.2,
            detailCount: listeners.count
        )

        return ServerDiagnostics(
            collectedAt: collectedAt,
            platform: platform,
            updates: updates,
            rebootRequired: rebootRequired,
            failedUnitsAvailability: failedSummary.0,
            failedUnits: failedUnits,
            failedUnitsTotal: failedSummary.1,
            failedUnitsTruncated: failedSummary.2,
            listenersAvailability: listenerSummary.0,
            listeners: listeners,
            listenersTotal: listenerSummary.1,
            listenersTruncated: listenerSummary.2
        )
    }

    private static func validate(
        availability: DiagnosticsAvailability,
        total: Int,
        truncated: Bool,
        detailCount: Int
    ) throws {
        guard availability == .available else {
            guard total == 0, detailCount == 0, !truncated else {
                throw DiagnosticsParserError.inconsistentSummary
            }
            return
        }
        guard detailCount <= total,
              truncated ? detailCount < total : detailCount == total else {
            throw DiagnosticsParserError.inconsistentSummary
        }
    }

    private static func boolean(_ value: String) -> Bool? {
        switch value {
        case "0": false
        case "1": true
        default: nil
        }
    }

    private static func optionalUInt(_ value: String) -> UInt? {
        value == "-" ? nil : UInt(value)
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-@").contains($0)
        }
    }

    private static func isUnitName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_.@\\-").contains($0)
        }
    }

    private static func isAddress(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:._-%").contains($0)
        }
    }

    private static func isSafeText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.count <= maximum && value.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && $0.value != 0x7F
        }
    }
}
