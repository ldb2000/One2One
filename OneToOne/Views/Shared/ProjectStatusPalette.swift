import SwiftUI

/// Couleurs et tri pour `Project.status` ("Red", "Yellow", "Green", "Unknown").
/// Extrait depuis CollaboratorDetailView pour partage avec ProjectsPanel
/// (sidebar configurable des réunions).
enum ProjectStatusPalette {

    /// Couleur SwiftUI pour un statut projet.
    static func color(_ status: String) -> Color {
        switch status {
        case "Red":     return .red
        case "Yellow":  return .orange
        case "Green":   return .green
        default:        return .gray
        }
    }

    /// Tri : Red → Yellow → Green → Unknown, puis alpha case-insensible.
    static func sortedByStatus(_ projects: [Project]) -> [Project] {
        let rank: [String: Int] = ["Red": 0, "Yellow": 1, "Green": 2, "Unknown": 3]
        return projects.sorted { a, b in
            let ra = rank[a.status] ?? 3
            let rb = rank[b.status] ?? 3
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
