import CoreGraphics
import Foundation

/// Quand la pastille flottante s'affiche. Réglage de l'utilisateur (spec §5.4).
///
/// Trois cas et pas un de plus : le mode par défaut suit la séance, parce que c'est le
/// moment où la pastille sert ; « toujours » est pour ceux qui pilotent la capture sans
/// jamais revenir dans la fenêtre ; « jamais » existe parce qu'une fenêtre qui se pose
/// par-dessus toutes les autres doit pouvoir être refusée.
enum SessionPillMode: String, CaseIterable, Sendable {
    case always
    case sessionOnly
    case never

    var label: String {
        switch self {
        case .always: return "Toujours visible"
        case .sessionOnly: return "Pendant la séance seulement"
        case .never: return "Jamais"
        }
    }

    /// Ce que le réglage explique sous son libellé.
    var explanation: String {
        switch self {
        case .always:
            return "La pastille reste à l'écran dès qu'une réunion est ouverte en séance."
        case .sessionOnly:
            return "La pastille apparaît en mode séance plein écran, ou quand un enregistrement tourne alors que One2One n'est pas au premier plan."
        case .never:
            return "Aucune fenêtre flottante. ⌘⇧S et ⌘⇧N restent actifs."
        }
    }
}

/// Ce dont la décision d'affichage dépend, côté application.
///
/// Un type et non trois paramètres libres : les trois booléens sont lus par le
/// contrôleur de panneau **et** par les tests, et une liste d'arguments positionnels de
/// booléens est exactement la forme qui s'inverse silencieusement.
struct SessionPillConditions: Equatable, Sendable {
    /// Une réunion est active (elle enregistre, ou elle est la dernière ouverte en
    /// séance) — cf. `ActiveMeetingRegistry`.
    var hasActiveMeeting: Bool
    /// Cette réunion est en mode séance plein écran (lot 4).
    var isSessionFullscreen: Bool
    /// Un enregistrement audio tourne pour cette réunion.
    var isRecording: Bool

    init(hasActiveMeeting: Bool = false,
         isSessionFullscreen: Bool = false,
         isRecording: Bool = false) {
        self.hasActiveMeeting = hasActiveMeeting
        self.isSessionFullscreen = isSessionFullscreen
        self.isRecording = isRecording
    }
}

/// La pastille doit-elle être à l'écran ?
///
/// Fonction pure, hors du contrôleur de panneau : c'est une règle de pilotage, et les
/// règles de pilotage laissées dans la couche AppKit/SwiftUI sont exactement celles qui
/// ont survécu jusqu'à l'usage réel dans Teams-Capture (programme §2.5).
///
/// Sans réunion active, **aucun** mode ne montre la pastille : elle n'aurait ni chrono,
/// ni source, ni compteur — trois mensonges plutôt qu'une absence.
func shouldPresentPill(mode: SessionPillMode,
                       conditions: SessionPillConditions,
                       isAppActive: Bool) -> Bool {
    guard conditions.hasActiveMeeting else { return false }
    switch mode {
    case .never:
        return false
    case .always:
        return true
    case .sessionOnly:
        // Le plein écran de séance, ou un enregistrement pendant que l'utilisateur
        // travaille ailleurs (Teams). Enregistrement **et** One2One au premier plan : la
        // barre du haut porte déjà l'état, la pastille ne serait qu'un doublon posé sur
        // sa propre fenêtre.
        return conditions.isSessionFullscreen || (conditions.isRecording && !isAppActive)
    }
}

/// La hauteur du panneau, confirmation et champ de note compris.
///
/// Tenue ici et non dans la vue pour la raison mesurée dans Teams-Capture : la vue
/// dessine dans les bornes que la fenêtre lui donne, et une carte dessinée sous une
/// pastille de 40 px dans une fenêtre de 40 px est **invisible**, coupée par le bord.
/// Seul le contrôleur peut agrandir la fenêtre, et il doit l'agrandir d'exactement
/// autant.
///
/// Les deux hauteurs se **cumulent** : capturer alors qu'un champ de note est déplié
/// dessine les deux.
func sessionPillPanelHeight(hasConfirmation: Bool, isEditingNote: Bool) -> CGFloat {
    One2OneToken.pillHeight
        + (isEditingNote ? One2OneToken.pillNoteHeight : 0)
        + (hasConfirmation ? One2OneToken.pillConfirmationHeight : 0)
}
