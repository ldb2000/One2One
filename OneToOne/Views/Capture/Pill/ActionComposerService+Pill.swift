import Foundation
import SwiftData

/// La création d'action depuis la pastille flottante.
///
/// Elle passe par `ActionComposerService.creer` du lot 3 et n'en refait pas le travail :
/// le plancher d'ordre, le responsable suggéré, la chaîne de citation et les défauts du
/// composeur y vivent, et une seconde implémentation divergerait au premier réglage.
///
/// Ce que cette extension ajoute est une précaution : `creer(from:)` lit
/// `screen.newTaskTitle` — le champ du rail — et le vide après création. Un titre à
/// moitié tapé dans le rail serait donc **consommé** par un clic sur
/// `＋ Action depuis la capture`, et l'action porterait ce titre au lieu de la ligne
/// d'OCR.
extension ActionComposerService {

    /// Crée l'action d'une capture sans toucher à la saisie en cours du rail.
    @discardableResult
    static func creerDepuisCapture(_ brouillon: ActionDraft,
                                   screen: MeetingScreenModel,
                                   meeting: Meeting,
                                   in context: ModelContext) -> ActionTask? {
        let titreDuRail = screen.newTaskTitle
        let brouillonEnAttente = screen.pendingActionDraft
        screen.newTaskTitle = ""
        screen.pendingActionDraft = brouillon

        let action = creer(from: screen, meeting: meeting, in: context)

        // Rien créé (titre vide) : on ne laisse pas le brouillon de la capture en
        // attente dans le rail, il y apparaîtrait comme une action proposée que
        // personne n'a demandée.
        if action == nil { screen.pendingActionDraft = brouillonEnAttente }
        screen.newTaskTitle = titreDuRail
        return action
    }
}
