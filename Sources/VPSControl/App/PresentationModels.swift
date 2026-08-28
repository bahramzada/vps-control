import Foundation
import SwiftUI

struct ActivityEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case information
        case warning
        case terminal
    }

    let id: UUID
    let title: String
    let detail: String
    let date: Date
    let kind: Kind

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        date: Date = .now,
        kind: Kind
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.date = date
        self.kind = kind
    }

    var systemImage: String {
        switch kind {
        case .success: "checkmark"
        case .information: "info"
        case .warning: "exclamationmark"
        case .terminal: "terminal"
        }
    }

    var tint: Color {
        switch kind {
        case .success: VPSTheme.green
        case .information: VPSTheme.blue
        case .warning: VPSTheme.yellow
        case .terminal: VPSTheme.secondaryText
        }
    }
}

struct ServiceRow: Identifiable, Equatable {
    let name: String
    let displayName: String
    let status: String
    let healthy: Bool
    let systemImage: String

    var id: String { name }
}
