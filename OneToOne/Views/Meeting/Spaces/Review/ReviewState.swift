import Foundation
import Observation
import SwiftData

/// L'état d'écran du **mode Relire** — le poste de pilotage de la capture
/// `1c-poste-de-pilotage.png` (spec §2.7, décision D0 du programme).
///
/// Un objet à part et non six propriétés de plus sur `MeetingScreenModel` :
/// c'est l'état d'une disposition, il naît et meurt avec elle, et
/// `MeetingScreenModel` en porte **une seule ligne**. Rien n'est persisté — la
/// section lue, le repli du tableau et la ligne sélectionnée sont des positions
/// du moment, et retrouver trois jours plus tard un tableau replié sur une
/// autre séance ne rendrait service à personne.
@MainActor
@Observable
final class ReviewState {

    /// Les entrées de la nav latérale de 190 px (spec §2.7). Valeurs brutes
    /// stables, sans persistance pour l'instant : ce sont aussi les ancres de
    /// défilement de la colonne principale.
    enum Section: String, CaseIterable, Sendable {
        case synthese
        case notes
        case transcription
        case actions
        case rapport
        case documents
        case assistant

        /// Libellé de l'entrée, sans son compteur (capture 1c).
        var libelle: String {
            switch self {
            case .synthese:      return "Synthèse"
            case .notes:         return "Notes"
            case .transcription: return "Transcription"
            case .actions:       return "Actions"
            case .rapport:       return "Rapport"
            case .documents:     return "Documents"
            case .assistant:     return "Assistant"
            }
        }

        /// Symbole de l'entrée, dans l'esprit des pictogrammes de la capture.
        var symbole: String {
            switch self {
            case .synthese:      return "square.grid.2x2.fill"
            case .notes:         return "pencil"
            case .transcription: return "text.alignleft"
            case .actions:       return "checkmark.square"
            case .rapport:       return "diamond.fill"
            case .documents:     return "square"
            case .assistant:     return "sparkle"
            }
        }

        /// L'espace vers lequel l'entrée mène, `nil` quand elle reste dans le
        /// poste de pilotage (`Rapport` et `Documents` mènent aux espaces
        /// Rapport et Ressources, spec §2.7 et périmètre du lot 5).
        var changeDEspace: MeetingScreenModel.Space? {
            switch self {
            case .rapport:   return .report
            case .documents: return .resources
            case .synthese, .notes, .transcription, .actions, .assistant: return nil
            }
        }

        /// Le mode vers lequel l'entrée mène, `nil` quand elle reste en Relire.
        ///
        /// `Notes` et `Transcription` ramènent en **En séance**, et c'est là
        /// tout le sens de « transcription repliée » (spec §2.2) : elle n'est
        /// pas absente du poste de pilotage, elle est **à un clic**. Le mode
        /// Relire n'a pas de carte de notes — la synthèse et les décisions
        /// *sont* leur lecture —, donc une entrée qui ne ferait que déplacer un
        /// défilement ne mènerait nulle part, et son compteur mentirait.
        var changeDeMode: MeetingScreenModel.Mode? {
            switch self {
            case .notes, .transcription: return .live
            case .synthese, .actions, .rapport, .documents, .assistant: return nil
            }
        }
    }

    /// Ce qu'une demande de focus désigne.
    enum Cible: Equatable, Sendable {
        /// Le champ d'assignation de la première action sans responsable
        /// (spec §2.2, colonne « Focus clavier » du mode Relire).
        case responsablePremiereActionNonAssignee
    }

    /// Une demande de focus **jetonnée**.
    ///
    /// Un jeton et non un simple booléen ni une valeur nue : deux générations de
    /// rapport de suite doivent toutes deux replacer le curseur, or la seconde
    /// écriture d'une valeur identique ne notifie personne — c'est le même
    /// raisonnement que `MeetingScreenModel.noteComposerFocusToken`.
    struct DemandeDeFocus: Equatable, Sendable {
        var cible: Cible
        var jeton: Int
    }

    // MARK: - État

    /// L'entrée active de la nav latérale.
    var section: Section = .synthese

    /// Le tableau d'actions est déplié (« tout afficher »).
    var toutAfficher = false

    /// La vue du tableau : `Tableau` (`liste`) · `Eisenhower` · `Calendrier`.
    ///
    /// Distincte de `MeetingScreenModel.railViewMode` : le rail et le tableau
    /// dense ne sont pas la même surface, et mémoriser « Eisenhower » dans le
    /// rail parce qu'on l'a ouvert une fois en relecture serait un effet de
    /// bord.
    var vue: ActionsViewMode = .liste

    /// La ligne sélectionnée du tableau, pour la navigation `↑↓`.
    var ligneSelectionnee: PersistentIdentifier?

    /// La demande de focus en attente, `nil` quand il n'y en a pas.
    private(set) var focusRequest: DemandeDeFocus?

    private var jeton = 0

    // MARK: - Focus

    /// Demande le focus sur `cible`. Deux appels de suite sont deux demandes.
    func demanderFocus(_ cible: Cible) {
        jeton += 1
        focusRequest = DemandeDeFocus(cible: cible, jeton: jeton)
    }

    /// Consomme la demande en cours. Appelé par la surface qui a pris le
    /// clavier : une demande servie qui reste posée se rejouerait à chaque
    /// rendu et volerait le curseur.
    func focusServi() {
        focusRequest = nil
    }

    // MARK: - Transition post-rapport

    /// Ce qui se passe **après une génération de rapport** (spec §2.7, périmètre
    /// du lot 5 point 6 : « passage automatique en mode Relire […] focus =
    /// champ d'assignation de la première action non assignée »).
    ///
    /// Remplace le `screen.space = .report` que le lot 1 posait : un rapport
    /// tout juste écrit n'a pas besoin d'être relu ligne à ligne, il a besoin
    /// que les actions qu'il vient d'extraire trouvent un responsable. L'espace
    /// Rapport reste à un clic, dans la nav latérale.
    ///
    /// Fonction et non méthode de `MeetingScreenModel` : ce modèle-là ne reçoit
    /// qu'**une ligne** de ce lot, et une transition vérifiable sans vue vaut
    /// mieux qu'une transition écrite dans un `MainActor.run` de
    /// `MeetingView`.
    static func apresGenerationDuRapport(_ screen: MeetingScreenModel) {
        screen.space = .meeting
        screen.mode = .review
        screen.review.section = .synthese
        screen.review.demanderFocus(.responsablePremiereActionNonAssignee)
    }
}
