import Foundation

enum TerminalPrivilegeState: Equatable, Sendable {
    case standard
    case elevating
    case elevated
    case uncertain

    var isHighRisk: Bool {
        self != .standard
    }

    var label: String {
        switch self {
        case .standard:
            return "jarvis"
        case .elevating:
            return "sudo keçidi"
        case .elevated:
            return "sudo aktiv"
        case .uncertain:
            return "sudo ola bilər"
        }
    }
}

enum TerminalPasteWarning: Hashable, Sendable {
    case privilegedSession
    case multipleLines(lineCount: Int)
    case trailingReturn
    case controlCharacters
    case largePayload(byteCount: Int)

    var message: String {
        switch self {
        case .privilegedSession:
            return "Terminal sudo rejimindədir və əmrlər yüksək səlahiyyətlə işləyə bilər."
        case let .multipleLines(lineCount):
            return "Mətn \(lineCount) sətirdir və bir neçə əmri ardıcıl işlədə bilər."
        case .trailingReturn:
            return "Mətn Enter ilə bitir və yapışdırılan kimi işləyə bilər."
        case .controlCharacters:
            return "Mətndə görünməyən control character mövcuddur."
        case let .largePayload(byteCount):
            return "Yapışdırılacaq məlumat böyükdür (\(byteCount) bayt)."
        }
    }
}

enum TerminalPasteDecision: Equatable, Sendable {
    case allow
    case confirm(warnings: [TerminalPasteWarning])
    case block(reason: String)
}

enum TerminalPastePolicy {
    static let largePayloadThreshold = 4_096

    static func evaluate(
        _ text: String,
        privilegeState: TerminalPrivilegeState,
        isConnected: Bool
    ) -> TerminalPasteDecision {
        guard isConnected else {
            return .block(reason: "Terminal bağlı deyil.")
        }
        guard !text.isEmpty else {
            return .block(reason: "Clipboard boşdur.")
        }

        var warnings: [TerminalPasteWarning] = []
        if privilegeState.isHighRisk {
            warnings.append(.privilegedSession)
        }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lineCount = normalized.split(separator: "\n", omittingEmptySubsequences: false).count
        if lineCount > 1 {
            warnings.append(.multipleLines(lineCount: lineCount))
        }

        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            warnings.append(.trailingReturn)
        }

        let hasUnexpectedControl = text.unicodeScalars.contains { scalar in
            let value = scalar.value
            if value == 0x09 || value == 0x0A || value == 0x0D {
                return false
            }
            return value < 0x20 || (value >= 0x7F && value <= 0x9F)
        }
        if hasUnexpectedControl {
            warnings.append(.controlCharacters)
        }

        let byteCount = text.lengthOfBytes(using: .utf8)
        if byteCount > largePayloadThreshold {
            warnings.append(.largePayload(byteCount: byteCount))
        }

        return warnings.isEmpty ? .allow : .confirm(warnings: warnings)
    }
}
