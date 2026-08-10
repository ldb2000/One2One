import Foundation

/// Portée des réunions qui comptent comme « réellement tenues ».
///
/// Une note est un `Meeting` de kind `.note` — une réunion avec soi-même. Elle
/// ne représente aucun temps passé, ne doit pas noircir la heatmap d'activité,
/// ni apparaître dans la liste des réunions d'un collaborateur (elle a sa
/// propre section). Trois appelants partagent donc cette règle : le calcul des
/// stats du jour et les deux montages de `MeetingHeatmapView`.
enum MeetingStatsScope {

    /// Ne conserve que les réunions réellement tenues, dans l'ordre d'entrée.
    static func held(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter { $0.kind != .note }
    }
}
