import Foundation

enum RemoteFileKind: String, Codable, Equatable, Sendable {
    case directory
    case regular
    case symbolicLink
    case blockDevice
    case characterDevice
    case socket
    case pipe
    case unknown

    init(findType: String) {
        switch findType {
        case "d": self = .directory
        case "f": self = .regular
        case "l": self = .symbolicLink
        case "b": self = .blockDevice
        case "c": self = .characterDevice
        case "s": self = .socket
        case "p": self = .pipe
        default: self = .unknown
        }
    }
}

struct RemoteFileEntry: Identifiable, Equatable, Sendable {
    var id: String { path }

    let name: String
    let path: String
    let kind: RemoteFileKind
    let sizeBytes: UInt64
    let modifiedAt: Date
    let permissions: String
    let owner: String
    let group: String

    var isDirectory: Bool {
        kind == .directory
    }
}

struct RemoteDirectoryListing: Equatable, Sendable {
    let path: String
    let entries: [RemoteFileEntry]
    let isTruncated: Bool

    var parentPath: String? {
        guard path != "/" else { return nil }
        let parent = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        return parent.isEmpty ? "/" : parent
    }
}

enum RemoteFileBrowserError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration
    case invalidPath
    case notFound
    case notDirectory
    case permissionDenied
    case protocolMismatch
    case malformedResponse
    case authenticationFailed
    case hostKeyMismatch
    case timeout
    case cancelled
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "SSH ayarları etibarlı deyil."
        case .invalidPath:
            return "Remote path absolute və etibarlı olmalıdır."
        case .notFound:
            return "Remote qovluq tapılmadı."
        case .notDirectory:
            return "Seçilmiş remote path qovluq deyil."
        case .permissionDenied:
            return "jarvis istifadəçisinin bu qovluğu oxumaq icazəsi yoxdur."
        case .protocolMismatch:
            return "Fayl siyahısı protokol versiyası uyğun deyil."
        case .malformedResponse:
            return "Remote fayl siyahısı tam və ya etibarlı deyil."
        case .authenticationFailed:
            return "SSH key ilə authentication uğursuz oldu."
        case .hostKeyMismatch:
            return "SSH host key dəyişdiyi üçün bağlantı bloklandı."
        case .timeout:
            return "Remote fayl siyahısı vaxt limitini keçdi."
        case .cancelled:
            return "Fayl sorğusu dayandırıldı."
        case .connectionFailed:
            return "VPS ilə SSH bağlantısı qurulmadı."
        }
    }
}
