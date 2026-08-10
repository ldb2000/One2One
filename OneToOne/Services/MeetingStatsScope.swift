import Foundation

/// Portée des réunions qui comptent comme « réellement tenues ».
///
/// Une note est un `Meeting` de kind `.note` — une réunion avec soi-même. Elle
/// ne représente aucun temps passé, ne doit pas noircir la heatmap d'activité,
/// ni apparaître dans la liste des réunions d'un collaborateur (elle a sa
/// propre section). Quatre appelants partagent donc cette règle : le calcul
/// des stats du jour, les deux montages de `MeetingHeatmapView`, et le
/// décompte hebdomadaire « Temps passé en réunions » de la barre latérale.
enum MeetingStatsScope {

    /// Ne conserve que les réunions réellement tenues, dans l'ordre d'entrée.
    static func held(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter { $0.kind != .note }
    }
}
