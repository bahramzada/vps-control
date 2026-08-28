import Foundation

struct ParsedMetrics: Equatable, Sendable {
    var snapshot: ServerSnapshot
    let warnings: [MetricParseWarning]
    let isComplete: Bool
}

enum MetricsParserError: Error, Equatable {
    case emptyPayload
    case missingHeader
    case unsupportedVersion
}

struct MetricsParser: Sendable {
    func parse(_ data: Data) throws -> ParsedMetrics {
        guard let payload = String(data: data, encoding: .utf8), !payload.isEmpty else {
            throw MetricsParserError.emptyPayload
        }
        return try parse(payload)
    }

    func parse(_ payload: String) throws -> ParsedMetrics {
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstNonEmptyIndex = lines.firstIndex(where: { !$0.isEmpty }) else {
            throw MetricsParserError.emptyPayload
        }
        let header = lines[firstNonEmptyIndex]
        guard header.hasPrefix("VPSC/") else {
            throw MetricsParserError.missingHeader
        }
        guard header == "VPSC/1" else {
            throw MetricsParserError.unsupportedVersion
        }

        var snapshot = ServerSnapshot()
        var warnings: [MetricParseWarning] = []
        var seenRecords: Set<String> = []
        var sawEnd = false

        for index in lines.indices where index > firstNonEmptyIndex {
            let line = lines[index]
            if line.isEmpty {
                continue
            }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let record = sanitizedRecordName(fields[0])

            if record == "end" {
                sawEnd = true
                break
            }

            let allowsDuplicates = record == "net" || record == "service"
            if !allowsDuplicates && seenRecords.contains(record) {
                warnings.append(.init(line: index + 1, record: record, reason: .duplicateRecord))
                continue
            }

            let parsed: Bool
            switch record {
            case "boot":
                parsed = parseBoot(fields, into: &snapshot)
            case "time":
                parsed = parseTime(fields, into: &snapshot)
            case "cpu":
                parsed = parseCPU(fields, into: &snapshot)
            case "load":
                parsed = parseLoad(fields, into: &snapshot)
            case "uptime":
                parsed = parseUptime(fields, into: &snapshot)
            case "mem":
                parsed = parseMemory(fields, into: &snapshot)
            case "disk":
                parsed = parseDisk(fields, into: &snapshot)
            case "default_net":
                parsed = parseDefaultNetwork(fields, into: &snapshot)
            case "net":
                parsed = parseNetwork(fields, into: &snapshot)
            case "service":
                parsed = parseService(fields, into: &snapshot)
            case "docker_cli":
                parsed = parseDockerCLI(fields, into: &snapshot)
            case "docker_socket_access":
                parsed = parseDockerAccess(fields, into: &snapshot)
            default:
                warnings.append(.init(line: index + 1, record: record, reason: .unknownRecord))
                continue
            }

            if parsed {
                seenRecords.insert(record)
            } else {
                warnings.append(.init(line: index + 1, record: record, reason: .invalidValue))
            }
        }

        if !sawEnd {
            warnings.append(.init(line: lines.count, record: "end", reason: .missingEndMarker))
        }

        let requiredRecords = ["boot", "time", "cpu", "load", "uptime", "mem", "disk"]
        for requiredRecord in requiredRecords where !seenRecords.contains(requiredRecord) {
            warnings.append(.init(
                line: lines.count,
                record: requiredRecord,
                reason: .missingRecord
            ))
        }

        if let defaultInterface = snapshot.defaultNetworkInterface {
            snapshot.networks = snapshot.networks.map { metric in
                NetworkMetric(
                    interface: metric.interface,
                    receivedBytes: metric.receivedBytes,
                    transmittedBytes: metric.transmittedBytes,
                    receivedBytesPerSecond: metric.receivedBytesPerSecond,
                    transmittedBytesPerSecond: metric.transmittedBytesPerSecond,
                    isDefault: metric.interface == defaultInterface
                )
            }
        }

        return ParsedMetrics(snapshot: snapshot, warnings: warnings, isComplete: sawEnd && warnings.isEmpty)
    }

    private func parseBoot(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 2,
              UUID(uuidString: fields[1]) != nil else {
            return false
        }
        snapshot.bootID = fields[1].lowercased()
        return true
    }

    private func parseTime(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 2,
              let timestamp = TimeInterval(fields[1]),
              timestamp > 0 else {
            return false
        }
        snapshot.collectedAt = Date(timeIntervalSince1970: timestamp)
        return true
    }

    private func parseCPU(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 9 else {
            return false
        }
        let values = fields.dropFirst().compactMap(UInt64.init)
        guard values.count == 8 else {
            return false
        }
        snapshot.cpuCounters = CPUTimeCounters(
            user: values[0],
            nice: values[1],
            system: values[2],
            idle: values[3],
            ioWait: values[4],
            irq: values[5],
            softIRQ: values[6],
            steal: values[7]
        )
        return true
    }

    private func parseLoad(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 5,
              let one = Double(fields[1]),
              let five = Double(fields[2]),
              let fifteen = Double(fields[3]) else {
            return false
        }
        let processCounts = fields[4].split(separator: "/", maxSplits: 1).compactMap { Int($0) }
        snapshot.loadAverage = LoadAverage(
            oneMinute: one,
            fiveMinutes: five,
            fifteenMinutes: fifteen,
            runnableProcesses: processCounts.count == 2 ? processCounts[0] : nil,
            totalProcesses: processCounts.count == 2 ? processCounts[1] : nil
        )
        return true
    }

    private func parseUptime(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 2,
              let value = Double(fields[1]),
              value >= 0 else {
            return false
        }
        snapshot.uptimeSeconds = value
        return true
    }

    private func parseMemory(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 5,
              let total = UInt64(fields[1]),
              let available = UInt64(fields[2]),
              let swapTotal = UInt64(fields[3]),
              let swapFree = UInt64(fields[4]),
              available <= total,
              swapFree <= swapTotal else {
            return false
        }
        snapshot.memoryTotalBytes = total
        snapshot.memoryAvailableBytes = available
        snapshot.swapTotalBytes = swapTotal
        snapshot.swapFreeBytes = swapFree
        return true
    }

    private func parseDisk(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 6,
              fields[1] == "/",
              let total = UInt64(fields[2]),
              let used = UInt64(fields[3]),
              let available = UInt64(fields[4]),
              let percent = Double(fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "%"))),
              used <= total,
              available <= total,
              (0...100).contains(percent) else {
            return false
        }
        snapshot.rootDiskTotalBytes = total
        snapshot.rootDiskUsedBytes = used
        snapshot.rootDiskAvailableBytes = available
        snapshot.rootDiskPercent = percent
        return true
    }

    private func parseDefaultNetwork(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 2, Self.isValidIdentifier(fields[1]) else {
            return false
        }
        snapshot.defaultNetworkInterface = fields[1]
        return true
    }

    private func parseNetwork(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 4,
              Self.isValidIdentifier(fields[1]),
              let received = UInt64(fields[2]),
              let transmitted = UInt64(fields[3]) else {
            return false
        }
        snapshot.networks.append(NetworkMetric(
            interface: fields[1],
            receivedBytes: received,
            transmittedBytes: transmitted,
            receivedBytesPerSecond: nil,
            transmittedBytesPerSecond: nil,
            isDefault: false
        ))
        return true
    }

    private func parseService(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 3, Self.isValidIdentifier(fields[1]) else {
            return false
        }
        snapshot.services.append(ServiceMetric(name: fields[1], state: .init(remoteValue: fields[2])))
        return true
    }

    private func parseDockerCLI(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 2, !fields[1].isEmpty, fields[1].count <= 256 else {
            return false
        }
        snapshot.dockerCLIVersion = fields[1]
        return true
    }

    private func parseDockerAccess(_ fields: [String], into snapshot: inout ServerSnapshot) -> Bool {
        guard fields.count == 2 else {
            return false
        }
        snapshot.dockerSocketAccess = .init(remoteValue: fields[1])
        return snapshot.dockerSocketAccess != .unknown
    }

    private func sanitizedRecordName(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_").contains($0)
        }
        return String(String.UnicodeScalarView(allowed)).prefix(32).lowercased()
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.@:-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
