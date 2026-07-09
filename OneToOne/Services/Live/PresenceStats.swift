import Foundation

/// Compteurs de présence dérivés des statuts des participants d'une réunion.
struct PresenceStats {
    let present: Int
    let refused: Int
    let pending: Int
    let total: Int

    /// Pourcentage de présents sur le total, arrondi ; 0 si aucun participant.
    var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(present) / Double(total) * 100).rounded())
    }

    static func compute(statuses: [MeetingAttendanceStatus]) -> PresenceStats {
        PresenceStats(
            present: statuses.filter { $0 == .present }.count,
            refused: statuses.filter { $0 == .refused }.count,
            pending: statuses.filter { $0 == .pending }.count,
            total: statuses.count)
    }
}
