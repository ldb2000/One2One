import Foundation
import SwiftData

/// Portée des réunions qui comptent comme « réellement tenues ».
///
/// Une note est un `Meeting` de kind `.note` — une réunion avec soi-même. Elle
/// ne représente **aucun temps passé** : elle ne doit noircir aucune heatmap,
/// ne compter dans aucune statistique ni aucun décompte, et ne pas figurer
/// dans les listes de réunions tenues (elle a ses propres écrans).
///
/// **Ce que la règle ne dit pas** : une note reste du contenu, et le contenu
/// se cherche. C'est délibéré, et hors de cette portée — `ChatbotView` injecte
/// les dernières notes dans le contexte de prompt et sa commande `/cherche`
/// expose un filtre `type:…|note` ; `SpotlightIndexService` indexe chaque note
/// créée. Filtrer ces chemins ici retirerait des fonctions livrées.
///
/// **La règle, pas la liste** : toute vue ou tout service qui présente ou
/// compte des réunions **tenues** passe par ici. Ne pas énumérer les appelants — deux
/// tentatives d'inventaire dans ce fichier ont été démenties par le code
/// suivant, chaque fois parce qu'un site avait été ajouté sans mettre à jour
/// la phrase. `grep MeetingStatsScope` donne la liste à jour, gratuitement.
enum MeetingStatsScope {

    /// Ne conserve que les réunions réellement tenues, dans l'ordre d'entrée.
    static func held(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter { $0.kind != .note }
    }

    /// La date de la dernière réunion **tenue et passée** de chaque projet.
    ///
    /// « Tenue » au sens de `held` (une note n'en est pas une) et **passée** :
    /// une réunion planifiée le mois prochain n'est pas la dernière réunion
    /// d'un projet, ni pour la colonne « Dernière réu. » du Portfolio, ni pour
    /// le motif « sans réunion depuis 30 j » de la vue « À risque ».
    ///
    /// Ici et non dans chacun de ses deux appelants : `SidebarProjectCounts` et
    /// `PortfolioBuilder` posaient la même question, et deux réponses qui
    /// divergent feraient afficher « il y a 3 j » sur un projet compté comme
    /// sans réunion.
    static func lastHeldByProject(_ meetings: [Meeting],
                                  today: Date) -> [PersistentIdentifier: Date] {
        var resultat: [PersistentIdentifier: Date] = [:]
        for reunion in held(meetings) {
            guard reunion.date <= today, let projet = reunion.project else { continue }
            let id = projet.persistentModelID
            if let connue = resultat[id], connue >= reunion.date { continue }
            resultat[id] = reunion.date
        }
        return resultat
    }
}
