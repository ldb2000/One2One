import AppKit
import SwiftData
import SwiftUI

/// Le point d'entrée de la pastille flottante côté écran de réunion (spec §5.4).
///
/// Un modificateur posé **une seule fois**, sur `MeetingSpaceView`, exactement comme le
/// lot 4 y pose son modificateur de plein écran : c'est le seul endroit de l'application
/// qui tienne à la fois la réunion, son `MeetingScreenModel` et le coordinateur de capture
/// du lot 7. La pastille vit dans un `NSPanel` — sans environnement SwiftUI, sans
/// `@Query`, sans le `@StateObject` de `MeetingView` — et n'a aucun autre moyen de les
/// atteindre. `FocusedValues`, qu'utilise le menu Réunion, ne convient pas : la pastille
/// sert précisément quand One2One n'a **pas** le focus.
///
/// Il n'ajoute rien à l'écran : il inscrit la réunion dans `ActiveMeetingRegistry` à
/// l'entrée en mode En séance, et la retire à la sortie.
private struct SessionPillHostModifier: ViewModifier {

    let meeting: Meeting
    let screen: MeetingScreenModel
    let capture: CaptureSessionCoordinator?
    /// Vrai en mode En séance : hors séance, il n'y a ni chrono ni capture à piloter.
    let estEligible: Bool

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .onAppear { declarer() }
            .onChange(of: estEligible) { _, _ in declarer() }
            .onDisappear {
                ActiveMeetingRegistry.shared.unregister(meetingStableID: meeting.ensuredStableID)
                SessionPillPanelController.shared.refresh()
            }
    }

    private func declarer() {
        let registre = ActiveMeetingRegistry.shared
        guard estEligible, let capture else {
            registre.unregister(meetingStableID: meeting.ensuredStableID)
            SessionPillPanelController.shared.refresh()
            return
        }
        // Idempotent par réunion : `onAppear` et `onChange` se déclenchent plusieurs
        // fois pour un même écran, et `register` remplace la poignée. L'instant d'entrée
        // en séance est celui de la **première** inscription : le réenregistrement ne
        // doit pas faire passer une réunion devant une autre à chaque rendu.
        let entree = registre.handles.first { $0.meetingStableID == meeting.ensuredStableID }?.enteredAt
        registre.register(ActiveMeetingHandle(meeting: meeting,
                                              screen: screen,
                                              context: context,
                                              enteredAt: entree ?? Date()) { capture })
        let controleur = SessionPillPanelController.shared
        controleur.openSourceSelector = { poignee in
            // Le seul chemin qui ramène dans l'application : sans source configurée, la
            // pastille n'a rien à capturer, et le sélecteur vit dans la fenêtre.
            NSApp.activate(ignoringOtherApps: true)
            poignee.screen.capture.showPopover = true
        }
        controleur.start()
    }
}

extension View {
    /// Branche la pastille flottante sur cet écran de réunion (spec §5.4).
    ///
    /// Une seule pose dans l'application : deux poses inscriraient deux poignées pour la
    /// même réunion — la seconde gagnerait, avec le contexte de la première.
    func sessionPill(meeting: Meeting,
                     screen: MeetingScreenModel,
                     capture: CaptureSessionCoordinator?,
                     estEligible: Bool) -> some View {
        modifier(SessionPillHostModifier(meeting: meeting,
                                         screen: screen,
                                         capture: capture,
                                         estEligible: estEligible))
    }
}
