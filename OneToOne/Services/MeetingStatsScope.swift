import Foundation

/// Portée des réunions qui comptent comme « réellement tenues ».
///
/// Une note est un `Meeting` de kind `.note` — une réunion avec soi-même. Elle
/// ne représente aucun temps passé, ne doit donc noircir aucune heatmap, ne
/// compter dans aucune statistique, n'alimenter aucun contexte de prompt IA et
/// n'apparaître dans aucune liste ou recherche de réunions (elle a ses propres
/// écrans).
///
/// **La règle, pas la liste** : toute vue ou tout service qui présente des
/// réunions « tenues » passe par ici. Ne pas énumérer les appelants — deux
/// tentatives d'inventaire dans ce fichier ont été démenties par le code
/// suivant, chaque fois parce qu'un site avait été ajouté sans mettre à jour
/// la phrase. `grep MeetingStatsScope` donne la liste à jour, gratuitement.
enum MeetingStatsScope {

    /// Ne conserve que les réunions réellement tenues, dans l'ordre d'entrée.
    static func held(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter { $0.kind != .note }
    }
}
