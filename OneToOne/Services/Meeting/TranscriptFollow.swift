import Foundation

/// Le défilement lié de la colonne de transcription (spec §2.4 : « bascule
/// `Suivre` ; si active, la transcription suit la tête de lecture. Toute
/// interaction manuelle la désactive et affiche `Reprendre le suivi` »).
///
/// Machine à états d'un seul bit, sortie de la vue pour une raison précise : le
/// piège n'est pas la désactivation, c'est la **réactivation involontaire**.
/// Ni l'avancée de la tête de lecture, ni l'arrivée de nouveaux segments live
/// ne doivent réarmer le suivi — sinon le lecteur qui remonte relire un passage
/// se voit ramené en bas à chaque seconde d'audio.
///
/// L'état lui-même vit dans `MeetingScreenModel.follow` : ce type ne le
/// duplique pas, il dit seulement comment il évolue.
enum TranscriptFollow {

    /// Ce qui peut arriver à la colonne.
    enum Event: Sendable {
        /// L'utilisateur a fait défiler, cliqué un segment, sélectionné du texte.
        case manualScroll
        /// Il a pressé `Reprendre le suivi`.
        case resumeRequested
        /// La tête de lecture a bougé (lecture, séance, clic sur la frise).
        case playheadMoved
        /// La transcription live a produit de nouveaux segments.
        case segmentsAppended
    }

    /// État suivant. `manualScroll` coupe, `resumeRequested` réarme, le reste
    /// laisse l'état tel quel.
    static func next(following: Bool, on event: Event) -> Bool {
        switch event {
        case .manualScroll:    return false
        case .resumeRequested: return true
        case .playheadMoved, .segmentsAppended: return following
        }
    }

    /// Libellé du bouton, exactement celui de la spec.
    static func label(following: Bool) -> String {
        following ? "Suivre" : "Reprendre le suivi"
    }

    /// Index du segment sur lequel se caler : le **dernier commencé** avant
    /// `t`. `nil` avant le premier segment — se caler sur le premier dès la
    /// première seconde ferait sauter la colonne alors que la parole ne
    /// commence qu'à 3:51.
    ///
    /// Tolère une liste non triée : une réattribution de tours de parole peut
    /// désordonner `orderIndex` par rapport au temps.
    static func target(startTimes: [Double], t: Double) -> Int? {
        var meilleur: (index: Int, debut: Double)?
        for (index, debut) in startTimes.enumerated() where debut <= t {
            if meilleur == nil || debut > meilleur!.debut {
                meilleur = (index, debut)
            }
        }
        return meilleur?.index
    }
}
