import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case overview
    case docker
    case services
    case files
    case terminal
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "İcmal"
        case .docker: "Docker"
        case .services: "Servislər"
        case .files: "Fayllar"
        case .terminal: "Terminal"
        case .activity: "Fəaliyyət"
        case .settings: "Ayarlar"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .docker: "shippingbox"
        case .services: "gearshape"
        case .files: "folder"
        case .terminal: "terminal"
        case .activity: "waveform.path.ecg"
        case .settings: "slider.horizontal.3"
        }
    }

    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .overview: "1"
        case .docker: "2"
        case .services: "3"
        case .files: "4"
        case .terminal: "5"
        case .activity: "6"
        case .settings: ","
        }
    }
}
