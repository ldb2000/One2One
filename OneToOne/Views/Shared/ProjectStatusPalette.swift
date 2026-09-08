import Foundation

/// Tri par `Project.status` ("Red", "Yellow", "Green", "Unknown").
///
/// Le lot 19 lui retire sa fonction `color(_:)` : ses deux seuls appelants
/// étaient l'ancienne fiche collaborateur et la sidebar configurable, tous deux
/// supprimés. Il ne reste que le tri, employé par `ReportTemplating`.
enum ProjectStatusPalette {

    /// Tri par statut (Red=0, Yellow=1, Green=2, tout autre/Unknown=3) puis,
    /// à statut égal, par nom en ordre alphabétique insensible à la casse.
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
