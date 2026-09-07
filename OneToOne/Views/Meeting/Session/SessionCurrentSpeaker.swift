import Foundation

/// Le « `CP parle` » de la barre d'état du mode séance (capture
/// `1b-mode-seance.png`, spec §2.6 : « locuteur courant »).
///
/// D'où vient le locuteur ? Pas d'un signal temps réel : `LiveTranscriptionService`
/// ne publie **aucun** locuteur, la diarisation étant *batch* —
/// `LiveDiarizationAligner.alignToBlocks` s'exécute après le `stop()`, par
/// recouvrement de timestamps. Le seul locuteur connu à l'instant `t` est donc
/// celui du `TranscriptSegment` qui couvre `t` **et** dont le cluster a été
/// résolu en `Collaborator`.
///
/// Sans segment, ou avec un segment dont le locuteur n'est pas résolu, la
/// mention est **masquée** (spec §2.6 : « locuteur courant … sinon masqué ») :
/// afficher `S2 parle` ou `?? parle` dans une barre d'état est un bruit, pas
/// une information.
enum SessionCurrentSpeaker {

    /// Ce que la barre d'état a besoin de savoir : de qui il s'agit, et
    /// comment l'écrire.
    struct Locuteur: Sendable, Equatable {
        /// Nom complet, pour la pastille et l'accessibilité.
        let nom: String
        /// Jusqu'à deux initiales — la forme de la capture (`CP`).
        let initiales: String
        /// « CP parle ».
        var libelle: String { "\(initiales) parle" }
    }

    /// Jusqu'à deux initiales majuscules, sur les deux premiers mots du nom.
    /// Même règle qu'`AvatarCircle.initials`, transcrite ici parce qu'elle y
    /// est privée et qu'une barre d'état ne doit pas instancier une vue pour
    /// obtenir deux lettres.
    static func initiales(_ nom: String) -> String {
        nom.split(whereSeparator: { !$0.isLetter })
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    /// Le locuteur à l'instant `t` parmi des tours `(début, fin, nom)`.
    ///
    /// Couche pure : les bornes, le choix en cas de recouvrement et le rejet
    /// des tours sans nom sont la règle, et c'est elle qu'on teste. La
    /// commodité qui lit les `TranscriptSegment` est juste en dessous.
    ///
    /// Bornes : `début ≤ t < fin`. Le `<` sur la fin évite qu'un locuteur reste
    /// affiché pendant le silence qui suit son tour ; en cas de recouvrement
    /// (deux tours qui contiennent `t`), c'est **le plus récemment commencé**
    /// qui parle.
    static func locuteur(tours: [(debut: Double, fin: Double, nom: String?)],
                         t: Double) -> Locuteur? {
        let candidats = tours.filter { tour in
            guard let nom = tour.nom, !nom.trimmingCharacters(in: .whitespaces).isEmpty
            else { return false }
            return tour.debut <= t && t < tour.fin
        }
        guard let tour = candidats.max(by: { $0.debut < $1.debut }), let nom = tour.nom
        else { return nil }
        return Locuteur(nom: nom, initiales: initiales(nom))
    }

    /// Le locuteur à l'instant `t` dans une réunion.
    @MainActor
    static func locuteur(segments: [TranscriptSegment], t: Double) -> Locuteur? {
        locuteur(tours: segments.map { ($0.startSeconds, $0.endSeconds, $0.speaker?.name) },
                 t: t)
    }
}
