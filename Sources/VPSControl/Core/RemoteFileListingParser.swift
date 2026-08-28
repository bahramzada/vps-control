import Foundation

enum RemoteFileListingParserError: Error, Equatable {
    case emptyPayload
    case missingHeader
    case unsupportedVersion
    case malformedRecord
    case missingPath
    case missingEndMarker
    case remote(RemoteFileBrowserError)
}

struct RemoteFileListingParser: Sendable {
    func parse(_ data: Data) throws -> RemoteDirectoryListing {
        guard !data.isEmpty else {
            throw RemoteFileListingParserError.emptyPayload
        }

        var tokens = data.split(separator: 0, omittingEmptySubsequences: false)
        if tokens.last?.isEmpty == true {
            tokens.removeLast()
        }
        guard !tokens.isEmpty else {
            throw RemoteFileListingParserError.emptyPayload
        }

        func string(_ index: Int) -> String {
            String(decoding: tokens[index], as: UTF8.self)
        }

        let header = string(0)
        guard header.hasPrefix("VPSF/") else {
            throw RemoteFileListingParserError.missingHeader
        }
        guard header == "VPSF/1" else {
            throw RemoteFileListingParserError.unsupportedVersion
        }

        var index = 1
        var canonicalPath: String?
        var entries: [RemoteFileEntry] = []
        var truncated = false
        var sawEnd = false

        while index < tokens.count {
            let record = string(index)
            index += 1

            switch record {
            case "path":
                guard canonicalPath == nil, index < tokens.count else {
                    throw RemoteFileListingParserError.malformedRecord
                }
                let value = string(index)
                index += 1
                guard Self.isValidAbsolutePath(value) else {
                    throw RemoteFileListingParserError.malformedRecord
                }
                canonicalPath = value

            case "entry":
                guard index + 6 < tokens.count,
                      let path = canonicalPath else {
                    throw RemoteFileListingParserError.malformedRecord
                }
                let name = string(index)
                let kind = RemoteFileKind(findType: string(index + 1))
                let sizeText = string(index + 2)
                let modifiedText = string(index + 3)
                let permissions = string(index + 4)
                let owner = string(index + 5)
                let group = string(index + 6)
                index += 7

                guard Self.isValidName(name),
                      let size = UInt64(sizeText),
                      let timestamp = Double(modifiedText), timestamp.isFinite, timestamp >= 0,
                      Self.isValidPermissions(permissions),
                      Self.isValidIdentity(owner),
                      Self.isValidIdentity(group),
                      entries.count < RemoteFileListingScript.maximumEntries else {
                    throw RemoteFileListingParserError.malformedRecord
                }

                entries.append(RemoteFileEntry(
                    name: name,
                    path: Self.childPath(parent: path, name: name),
                    kind: kind,
                    sizeBytes: size,
                    modifiedAt: Date(timeIntervalSince1970: timestamp),
                    permissions: permissions,
                    owner: owner,
                    group: group
                ))

            case "truncated":
                guard index < tokens.count else {
                    throw RemoteFileListingParserError.malformedRecord
                }
                let value = string(index)
                index += 1
                guard value == "0" || value == "1" else {
                    throw RemoteFileListingParserError.malformedRecord
                }
                truncated = value == "1"

            case "error":
                guard index < tokens.count else {
                    throw RemoteFileListingParserError.malformedRecord
                }
                let code = string(index)
                index += 1
                throw RemoteFileListingParserError.remote(Self.remoteError(code))

            case "end":
                sawEnd = true
                index = tokens.count

            default:
                throw RemoteFileListingParserError.malformedRecord
            }
        }

        guard sawEnd else {
            throw RemoteFileListingParserError.missingEndMarker
        }
        guard let canonicalPath else {
            throw RemoteFileListingParserError.missingPath
        }

        let sortedEntries = entries.sorted { left, right in
            if left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        return RemoteDirectoryListing(
            path: canonicalPath,
            entries: sortedEntries,
            isTruncated: truncated
        )
    }

    private static func childPath(parent: String, name: String) -> String {
        parent == "/" ? "/\(name)" : "\(parent)/\(name)"
    }

    private static func isValidAbsolutePath(_ value: String) -> Bool {
        value.hasPrefix("/") && value.count <= 4_096 && !value.contains("\0") && !value.contains("\n")
    }

    private static func isValidName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.count <= 255 && !value.contains("/") && !value.contains("\0")
    }

    private static func isValidPermissions(_ value: String) -> Bool {
        value.count == 10 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "bcdlps- rwxStT").contains($0)
        }
    }

    private static func isValidIdentity(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && !value.contains("\0") && !value.contains("\n")
    }

    private static func remoteError(_ code: String) -> RemoteFileBrowserError {
        switch code {
        case "invalid_path": .invalidPath
        case "not_found": .notFound
        case "not_directory": .notDirectory
        case "permission_denied": .permissionDenied
        default: .malformedResponse
        }
    }
}
