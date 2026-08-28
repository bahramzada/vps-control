import Foundation

enum DisplayFormatting {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func fileSize(_ value: UInt64) -> String {
        fileSizeFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func uptime(_ seconds: Double?) -> (primary: String, secondary: String) {
        guard let seconds, seconds >= 0, seconds.isFinite else {
            return ("—", "Məlumat yoxdur")
        }
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return ("\(days)g \(hours)s", "\(days) gün, \(hours) saat")
        }
        if hours > 0 {
            return ("\(hours)s \(minutes)d", "\(hours) saat, \(minutes) dəqiqə")
        }
        return ("\(minutes)d", "\(minutes) dəqiqə")
    }

    static func maskedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "ssh://—" }

        if trimmed.contains(".") {
            let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            if components.count == 4 {
                return "\(components[0]).***.***.\(components[3])"
            }
        }

        guard trimmed.count > 5 else { return String(repeating: "•", count: trimmed.count) }
        return "\(trimmed.prefix(2))•••\(trimmed.suffix(2))"
    }
}
