import Testing
import SwiftUI
@testable import OneToOne

/// La signalétique 1:1 de la barre du haut (spec §3.1 : « badge de type `1:1`
/// en `accent/oneonone`, fond de barre `#f4f1f6` : c'est le seul type qui
/// change la couleur de la barre » ; §6.1 et D4 : « pilule `Je suis le
/// collaborateur` dans la barre, **obligatoire** »).
///
/// Le rôle doit être lisible en permanence (critère chantier 5 n° 1 : « on ne
/// peut pas confondre un 1:1 mené et un 1:1 subi »). C'est la seule raison pour
/// laquelle le lot 10, qui n'a aucun écran, touche une vue.
@Suite("Barre du haut — signalétique 1:1 (spec §3.1, §6.1, D4)")
struct MeetingTopChromeOneOnOneTests {

    @Test("Les deux types 1:1 portent le badge 1:1, les autres n'en portent pas")
    func badgeDeType() {
        #expect(MeetingTopChromeBar.typeBadge(for: .oneToOne) == "1:1")
        #expect(MeetingTopChromeBar.typeBadge(for: .manager) == "1:1")
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.typeBadge(for: kind) == nil)
        }
    }

    @Test("La pilule « Je suis le collaborateur » n'apparaît que pour le 1:1 manager")
    func pilulueDeRole() {
        #expect(MeetingTopChromeBar.collaboratorPillLabel(for: .manager) == "Je suis le collaborateur")
        #expect(MeetingTopChromeBar.collaboratorPillLabel(for: .oneToOne) == nil)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.collaboratorPillLabel(for: kind) == nil)
        }
    }

    @Test("La barre est teintée #f4f1f6 pour les deux types 1:1")
    func teinteDeBarre() {
        // Garde de la teinte posée au lot 1 : c'est le signal permanent que la
        // séance est privée, et rien d'autre dans l'app ne le dit.
        #expect(MeetingTopChromeBar.tint(for: .oneToOne) == One2OneToken.oneOnOneBg)
        #expect(MeetingTopChromeBar.tint(for: .manager) == One2OneToken.oneOnOneBg)
        // `#f4f1f6` = 244, 241, 246. Le littéral hexadécimal est privé à
        // `One2OneTokens.swift` (seul ce fichier nomme une couleur) : on
        // vérifie donc les composantes.
        let composantes = NSColor(One2OneToken.oneOnOneBg).usingColorSpace(.sRGB)
        #expect(Int(((composantes?.redComponent ?? 0) * 255).rounded()) == 244)
        #expect(Int(((composantes?.greenComponent ?? 0) * 255).rounded()) == 241)
        #expect(Int(((composantes?.blueComponent ?? 0) * 255).rounded()) == 246)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.tint(for: kind) == One2OneToken.bgApp)
        }
    }
}
