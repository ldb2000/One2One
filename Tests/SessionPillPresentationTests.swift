import CoreGraphics
import Testing
@testable import OneToOne

/// Quand la pastille flottante est à l'écran, et de quelle hauteur.
///
/// Deux règles de pilotage, tenues dans des fonctions pures et non dans le contrôleur de
/// panneau : dans Teams-Capture, les défauts qui ont survécu jusqu'à l'usage réel étaient
/// tous dans la couche sans tests (programme §2.5). Ici la pastille apparaît **et**
/// disparaît sur des conditions qu'aucun geste manuel ne peut couvrir toutes.
@Suite("SessionPillPresentation")
struct SessionPillPresentationTests {

    private func conditions(active: Bool = true,
                            fullscreen: Bool = false,
                            recording: Bool = false) -> SessionPillConditions {
        SessionPillConditions(hasActiveMeeting: active,
                              isSessionFullscreen: fullscreen,
                              isRecording: recording)
    }

    @Test("« jamais » ne montre rien, quoi qu'il se passe")
    func neverStaysHidden() {
        for fullscreen in [true, false] {
            for recording in [true, false] {
                for appActive in [true, false] {
                    #expect(shouldPresentPill(
                        mode: .never,
                        conditions: conditions(fullscreen: fullscreen, recording: recording),
                        isAppActive: appActive) == false)
                }
            }
        }
    }

    @Test("sans réunion active, aucun mode ne montre la pastille")
    func noActiveMeetingNoPill() {
        for mode in SessionPillMode.allCases {
            #expect(shouldPresentPill(mode: mode,
                                      conditions: conditions(active: false, recording: true),
                                      isAppActive: false) == false)
        }
    }

    @Test("« séance seulement » : plein écran de séance, ou enregistrement hors premier plan")
    func sessionOnly() {
        // Le plein écran de séance suffit, même si OneToOne est au premier plan : c'est
        // précisément le mode où la fenêtre couvre l'écran et où la pastille sert.
        #expect(shouldPresentPill(mode: .sessionOnly,
                                  conditions: conditions(fullscreen: true),
                                  isAppActive: true))
        // Un enregistrement pendant que l'utilisateur est dans Teams : la pastille est
        // la seule surface visible.
        #expect(shouldPresentPill(mode: .sessionOnly,
                                  conditions: conditions(recording: true),
                                  isAppActive: false))
        // Le même enregistrement avec OneToOne devant : la barre du haut dit déjà tout,
        // et une pastille par-dessus sa propre fenêtre est du bruit.
        #expect(shouldPresentPill(mode: .sessionOnly,
                                  conditions: conditions(recording: true),
                                  isAppActive: true) == false)
        // Réunion ouverte, rien qui tourne, application en arrière-plan : rien à dire.
        #expect(shouldPresentPill(mode: .sessionOnly,
                                  conditions: conditions(),
                                  isAppActive: false) == false)
    }

    @Test("« toujours » montre la pastille dès qu'une réunion est active")
    func always() {
        for appActive in [true, false] {
            #expect(shouldPresentPill(mode: .always,
                                      conditions: conditions(),
                                      isAppActive: appActive))
        }
    }

    @Test("la clôture de la séance et l'arrêt de l'enregistrement masquent la pastille")
    func hidesWhenSessionEnds() {
        let pendant = conditions(fullscreen: true, recording: true)
        #expect(shouldPresentPill(mode: .sessionOnly, conditions: pendant, isAppActive: false))
        // Séance close, enregistrement arrêté : la réunion reste ouverte, la pastille non.
        let apres = conditions(fullscreen: false, recording: false)
        #expect(shouldPresentPill(mode: .sessionOnly, conditions: apres, isAppActive: false) == false)
    }

    @Test("les trois modes portent un libellé français distinct et un brut stable")
    func modeLabels() {
        #expect(SessionPillMode.allCases.map(\.rawValue) == ["always", "sessionOnly", "never"])
        #expect(Set(SessionPillMode.allCases.map(\.label)).count == 3)
        #expect(SessionPillMode.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(SessionPillMode(rawValue: "toujours") == nil)
    }

    // MARK: - Hauteur du panneau

    @Test("au repos, le panneau fait exactement la hauteur de la pastille")
    func heightAtRest() {
        #expect(sessionPillPanelHeight(hasConfirmation: false, isEditingNote: false)
                == One2OneToken.pillHeight)
    }

    @Test("la confirmation et le champ de note agrandissent le panneau, et se cumulent")
    func heightGrows() {
        let confirmation = sessionPillPanelHeight(hasConfirmation: true, isEditingNote: false)
        let note = sessionPillPanelHeight(hasConfirmation: false, isEditingNote: true)
        let deux = sessionPillPanelHeight(hasConfirmation: true, isEditingNote: true)

        // Les attendus sont typés `CGFloat` explicitement : une somme de jetons laissée
        // à l'inférence devient un `Double`, et `#expect` compare alors deux types
        // distincts que Swift ne rapproche que par conversion implicite — l'égalité est
        // fausse dans la macro alors qu'elle est vraie dans le code.
        let attenduConfirmation: CGFloat = One2OneToken.pillHeight + One2OneToken.pillConfirmationHeight
        let attenduNote: CGFloat = One2OneToken.pillHeight + One2OneToken.pillNoteHeight
        let attenduLesDeux: CGFloat = attenduConfirmation + One2OneToken.pillNoteHeight

        #expect(confirmation == attenduConfirmation)
        #expect(note == attenduNote)
        // Le cumul, et non le maximum : capturer pendant qu'un champ de note est déplié
        // dessine les deux, et un panneau qui ne suivrait que le plus grand couperait
        // l'autre — c'est le défaut corrigé dans Teams-Capture (carte invisible sous une
        // fenêtre de 40 px).
        #expect(deux == attenduLesDeux)
        #expect(deux > confirmation)
        #expect(deux > note)
    }
}
