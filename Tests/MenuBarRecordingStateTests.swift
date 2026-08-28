import Testing
import Foundation
@testable import OneToOne

/// L'icône de barre de menus est le seul signal permanent qu'un enregistrement
/// tourne. Se tromper de symbole, c'est laisser l'utilisateur enregistrer sans
/// le savoir.
@Suite("MenuBarController — symbole d'état")
struct MenuBarRecordingStateTests {

    @Test("Au repos, l'icône reste celle de l'agenda")
    func idleKeepsCalendarSymbol() {
        #expect(MenuBarController.statusSymbol(isRecording: false, pulseOn: false) == "calendar.badge.clock")
        #expect(MenuBarController.statusSymbol(isRecording: false, pulseOn: true) == "calendar.badge.clock")
    }

    @Test("En enregistrement, le pulse alterne entre disque plein et disque cerclé")
    func recordingPulses() {
        #expect(MenuBarController.statusSymbol(isRecording: true, pulseOn: true) == "record.circle.fill")
        #expect(MenuBarController.statusSymbol(isRecording: true, pulseOn: false) == "record.circle")
    }
}
