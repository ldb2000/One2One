import Testing
import SwiftUI
@testable import OneToOne

/// Le thème `.session` du mode séance plein écran, et la promesse que le lot 4
/// **ne touche pas au rendu clair**.
///
/// Le lot a rendu thématiques `TimedNotesColumn`, `NoteComposer`,
/// `TranscriptColumn`, `Chip` et `sectionLabel()` : ils lisent désormais
/// `theme.colors.*` là où ils lisaient `One2OneToken.*`. Ces tests fixent
/// l'équivalence en `.paper` — sans eux, une seule correspondance erronée
/// repeindrait discrètement l'espace Réunion en clair, et aucune autre suite
/// ne s'en apercevrait.
@Suite("Thème du mode séance")
struct SessionThemeTests {

    @Test("En clair, les couleurs du thème sont exactement les jetons d'avant")
    func paperIsUnchanged() {
        let c = One2OneTheme.paper.colors
        #expect(c.base == One2OneToken.bgApp)
        #expect(c.canvas == One2OneToken.bgCanvas)
        #expect(c.card == One2OneToken.surface)
        #expect(c.ink1 == One2OneToken.ink1)
        #expect(c.ink2 == One2OneToken.ink2)
        #expect(c.ink3 == One2OneToken.ink3)
        #expect(c.ink4 == One2OneToken.ink4)
        #expect(c.action == One2OneToken.action)
        #expect(c.report == One2OneToken.report)
        #expect(c.warn == One2OneToken.warn)
        #expect(c.ok == One2OneToken.ok)
        #expect(c.hair == One2OneToken.hair)
        #expect(c.cardBorder == One2OneToken.cardBorder)
        // Les sept champs ajoutés par le lot 4 : c'est là que la régression
        // silencieuse aurait lieu.
        #expect(c.surfaceAlt == One2OneToken.surfaceAlt)
        #expect(c.strongBorder == One2OneToken.strongBorder)
        #expect(c.inkMuted == One2OneToken.inkMuted)
        #expect(c.actionInk == One2OneToken.actionInk)
        #expect(c.actionBg == One2OneToken.actionBg)
        #expect(c.reportInk == One2OneToken.reportInk)
        #expect(c.warnInk == One2OneToken.warnInk)
    }

    @Test("En séance, tout est pris dans la palette dark/* de la spec §1.2")
    func sessionUsesDarkPalette() {
        let c = One2OneTheme.session.colors
        #expect(c.base == One2OneToken.darkBase)
        #expect(c.canvas == One2OneToken.darkTranscript)
        #expect(c.card == One2OneToken.darkCard)
        #expect(c.cardActive == One2OneToken.darkCardActive)
        #expect(c.pill == One2OneToken.darkPill)
        #expect(c.ink1 == One2OneToken.darkInk1)
        #expect(c.ink4 == One2OneToken.darkInk4)
        #expect(c.action == One2OneToken.darkAction)
        #expect(c.report == One2OneToken.darkReport)
        #expect(c.warn == One2OneToken.darkWarn)
        #expect(c.surfaceAlt == One2OneToken.darkCard)
        #expect(c.inkMuted == One2OneToken.darkInk4)
        #expect(c.actionInk == One2OneToken.darkAction)
        #expect(c.reportInk == One2OneToken.darkReport)
        #expect(c.warnInk == One2OneToken.darkWarn)
    }

    @Test("En séance, aucune encre ne retombe sur une encre de la palette claire")
    func noLightInkLeaksIntoTheSession() {
        let session = One2OneTheme.session.colors
        let clair = [One2OneToken.ink1, One2OneToken.ink2, One2OneToken.ink3,
                     One2OneToken.ink4, One2OneToken.inkMuted]
        for encre in [session.ink1, session.ink2, session.ink3, session.ink4,
                      session.inkMuted] {
            #expect(!clair.contains(encre),
                    "une encre de la palette claire s'est glissée dans le thème séance")
        }
    }

    @Test("Les chips gardent leurs couples d'avant en clair")
    func chipsUnchangedOnPaper() {
        for ton in ChipTon.allCases {
            #expect(ton.encre(.paper) == ton.encre)
            #expect(ton.fond(.paper) == ton.fond)
        }
        #expect(ChipTon.action.encre(.paper) == One2OneToken.actionInk)
        #expect(ChipTon.report.fond(.paper) == One2OneToken.reportBg)
    }

    @Test("En séance, toutes les chips reposent sur la pilule sombre")
    func chipsOnSession() {
        for ton in ChipTon.allCases {
            #expect(ton.fond(.session) == One2OneToken.darkPill)
            #expect(ton.encre(.session) != ton.encre(.paper),
                    "la chip \(ton) garderait son encre claire sur fond sombre")
        }
    }

    @Test("La portion écoulée de l'axe est le `#e04b3f` de la spec, distinct de accent/report")
    func railElapsedToken() {
        #expect(One2OneToken.railElapsed == Color(.sRGB,
                                                  red: 0xE0 / 255,
                                                  green: 0x4B / 255,
                                                  blue: 0x3F / 255,
                                                  opacity: 1))
        #expect(One2OneToken.railElapsed != One2OneToken.report)
    }
}
