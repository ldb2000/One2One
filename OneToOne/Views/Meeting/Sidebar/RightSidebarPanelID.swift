import Foundation
import SwiftUI

/// Identifiants des panels configurables de la sidebar droite des réunions.
/// L'ordre des `allCases` détermine le layout par défaut.
enum RightSidebarPanelID: String, CaseIterable, Codable, Identifiable {
    case actions
    case projects
    case capture

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .actions:  return "Actions"
        case .projects: return "Projets affectés"
        case .capture:  return "Capture"
        }
    }

    var systemImage: String {
        switch self {
        case .actions:  return "checklist"
        case .projects: return "folder.fill"
        case .capture:  return "camera"
        }
    }
}
