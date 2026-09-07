import Foundation
import Testing
@testable import OneToOne

/// Les deux raccourcis globaux du lot 8 et la remontée de leur échec.
///
/// Aucun test n'enregistre de raccourci Carbon : `GlobalHotkeyService` touche
/// `RegisterEventHotKey`, qui parle au serveur de fenêtres. Ce qui est testable — et ce
/// qui casse — est la combinaison décrite et le message affiché.
@Suite("CaptureHotkeys")
@MainActor
struct CaptureHotkeysTests {

    @Test("⌘⇧S et ⌘⇧N sont bien commande + majuscule + la lettre de la spec §1.4")
    func specs() {
        #expect(CaptureHotkey.capture.spec.keyChar == "S")
        #expect(CaptureHotkey.capture.spec.modifiers == [.command, .shift])
        #expect(CaptureHotkey.note.spec.keyChar == "N")
        #expect(CaptureHotkey.note.spec.modifiers == [.command, .shift])
        #expect(CaptureHotkey.all.count == 2)
    }

    @Test("la notation affichée est celle de la spec, pas l'ordre canonique de HotkeySpec")
    func labelIsTheSpecNotation() {
        #expect(CaptureHotkey.capture.label == "⌘⇧S")
        #expect(CaptureHotkey.note.label == "⌘⇧N")
        // La sérialisation, elle, reste dans l'ordre canonique ⌃⌥⇧⌘ : c'est la clé de
        // `GlobalHotkeyService`, pas un libellé.
        #expect(CaptureHotkey.capture.spec.serialized == "⇧⌘S")
    }

    @Test("l'échec nomme le raccourci et l'application qui le détient")
    func failureMessage() {
        #expect(CaptureHotkey.capture.failureMessage
                == "⌘⇧S est déjà utilisé par une autre application.")
        #expect(CaptureHotkey.note.failureMessage
                == "⌘⇧N est déjà utilisé par une autre application.")
    }

    @Test("un échec est consigné, un succès l'efface — un message d'erreur ne reste pas")
    func failuresAreCleared() {
        let echecs = CaptureHotkeyFailures()
        #expect(echecs.message(for: .capture) == nil)

        echecs.record(.capture, succeeded: false)
        #expect(echecs.message(for: .capture) == CaptureHotkey.capture.failureMessage)
        // L'échec de l'un ne salit pas l'autre.
        #expect(echecs.message(for: .note) == nil)

        echecs.record(.capture, succeeded: true)
        #expect(echecs.message(for: .capture) == nil)
    }

    @Test("désactiver un raccourci n'est pas une panne : le message disparaît")
    func disablingForgetsTheFailure() {
        let echecs = CaptureHotkeyFailures()
        echecs.record(.note, succeeded: false)
        echecs.forget(.note)
        #expect(echecs.message(for: .note) == nil)
        #expect(echecs.failed.isEmpty)
    }
}
