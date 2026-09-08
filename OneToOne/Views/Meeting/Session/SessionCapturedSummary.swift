import Foundation

/// Le bloc `CAPTURÉ CETTE SÉANCE` du pied de la colonne droite (capture
/// `1b-mode-seance.png` : `4 ACTIONS · 1 DÉCISION · 2 RISQUES`, le 2 en ambre).
///
/// « Cette séance » est la partie difficile, et c'est pour elle que le calcul
/// est ici et non dans la vue : la réunion porte **tout** son historique, y
/// compris ce qui a été saisi la veille en préparation ou repris d'une réunion
/// antérieure. Compter `meeting.tasks.count` afficherait 12 actions là où la
/// séance en a produit 4, et un compteur qui compte autre chose que ce qu'il
/// annonce est pire qu'absent.
///
/// L'origine du temps est `Meeting.recordingStartedAt` quand l'enregistrement
/// tourne — c'est l'instant que tout le reste du mode séance prend pour zéro
/// (`MeetingPlayhead`) —, sinon l'instant d'ouverture du mode.
enum SessionCapturedSummary {

    /// Les trois compteurs de la capture.
    struct Compteurs: Sendable, Equatable {
        var actions: Int = 0
        var decisions: Int = 0
        var risques: Int = 0

        /// Vrai quand la séance n'a encore rien produit : la vue affiche alors
        /// trois zéros et non un bloc vide — « jamais un écran vide », et un
        /// zéro assumé est une information.
        var estVide: Bool { actions == 0 && decisions == 0 && risques == 0 }
    }

    /// L'origine du temps de la séance (spec du lot : `recordingStartedAt` ou
    /// l'ouverture du mode).
    ///
    /// `recordingStartedAt` **même s'il est antérieur** à l'ouverture du mode :
    /// on passe souvent en plein écran une fois la séance lancée, et les notes
    /// des cinq premières minutes appartiennent bien à cette séance.
    static func debutDeSeance(recordingStartedAt: Date?, ouvertureDuMode: Date) -> Date {
        guard let recordingStartedAt else { return ouvertureDuMode }
        return min(recordingStartedAt, ouvertureDuMode)
    }

    /// Compte les éléments dont l'horodatage est postérieur ou égal à `depuis`.
    ///
    /// Un horodatage `nil` **ne compte pas** : `ActionTask.createdAt` est
    /// optionnel pour rester compatible avec les lignes antérieures à son
    /// introduction, et ces lignes-là sont précisément celles qui n'ont pas été
    /// créées pendant la séance en cours.
    static func compte(_ dates: [Date?], depuis: Date) -> Int {
        dates.reduce(into: 0) { total, date in
            guard let date, date >= depuis else { return }
            total += 1
        }
    }

    /// Les trois compteurs, depuis les horodatages bruts. Couche pure : la
    /// commodité qui lit la réunion est juste en dessous.
    static func compteurs(actions: [Date?],
                          decisions: [Date?],
                          risques: [Date?],
                          depuis: Date) -> Compteurs {
        Compteurs(actions: compte(actions, depuis: depuis),
                  decisions: compte(decisions, depuis: depuis),
                  risques: compte(risques, depuis: depuis))
    }

    /// Les trois compteurs d'une réunion.
    ///
    /// Les décisions sont les `MeetingNote(kind: .decision)` — la colonne de
    /// notes est le seul chemin par lequel une décision est prise en séance
    /// depuis le lot 2 ; `Meeting.decisions` (un tableau de chaînes rempli par
    /// la génération du rapport) n'est pas horodaté et ne peut donc pas dire
    /// « cette séance ». Les risques sont les `ProjectAlert` non résolues
    /// rattachées à la réunion.
    @MainActor
    static func compteurs(meeting: Meeting, depuis: Date) -> Compteurs {
        let notes = meeting.timedNotes
        return compteurs(
            actions: meeting.tasks.map(\.createdAt),
            decisions: notes.filter { $0.kind == .decision }.map { $0.createdAt as Date? },
            risques: meeting.meetingAlerts.filter { !$0.isResolved }.map { $0.date as Date? },
            depuis: depuis
        )
    }

    /// Le libellé d'un compteur, au singulier près (capture : `1 DÉCISION`,
    /// `2 RISQUES`).
    static func libelle(_ compte: Int, singulier: String, pluriel: String) -> String {
        compte == 1 ? singulier : pluriel
    }
}
