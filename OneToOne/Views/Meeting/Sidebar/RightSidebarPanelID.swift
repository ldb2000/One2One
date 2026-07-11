import Foundation
import SwiftUI

/// Identifiants des cartes configurables du dashboard réunion (onglet
/// « Vue d'ensemble »). L'ordre des `allCases` détermine le layout par défaut.
enum RightSidebarPanelID: String, CaseIterable, Codable, Identifiable {
    case presence
    case transcription
    case summary
    case actions
    case capture
    case projects
    case managerAgenda

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .presence:      return "Présence"
        case .transcription: return "Transcription"
        case .summary:       return "Résumé"
        case .actions:       return "Actions"
        case .capture:       return "Capture"
        case .projects:      return "Projets affectés"
        case .managerAgenda: return "Agenda manager"
        }
    }

    /// Taille par défaut (colonnes, lignes) dans la grille du dashboard.
    /// Colonnes ∈ 1…3 (max 3 par rangée) ; lignes ∈ 1…3.
    var defaultSpan: (cols: Int, rows: Int) {
        switch self {
        case .presence:      return (1, 1)
        case .transcription: return (2, 1)
        case .summary:       return (1, 2)
        case .actions:       return (1, 2)
        case .capture:       return (1, 1)
        case .projects:      return (1, 1)
        case .managerAgenda: return (1, 1)
        }
    }

    var systemImage: String {
        switch self {
        case .presence:      return "person.3.fill"
        case .transcription: return "waveform"
        case .summary:       return "text.line.first.and.arrowtriangle.forward"
        case .actions:       return "checklist"
        case .capture:       return "camera"
        case .projects:      return "folder.fill"
        case .managerAgenda: return "list.bullet.rectangle"
        }
    }
}
