import Testing
import SwiftUI
@testable import OneToOne

/// « Thème local par environnement, pas via le mode sombre système. » —
/// programme de refonte §2.3.
///
/// Les trois `WindowGroup` de `OneToOneApp` épinglent
/// `.preferredColorScheme(.light)`. Le mode séance (capture 1b) est pourtant
/// une palette sombre. Il ne peut donc pas passer par `colorScheme` : c'est un
/// thème d'écran explicite, porté par l'environnement, et ce fichier fixe le
/// contrat des deux palettes.
@Suite("Thème One2One — papier et séance")
struct One2OneThemeTests {

    @Test("Le thème par défaut de l'environnement est le papier")
    func defaultThemeIsPaper() {
        #expect(EnvironmentValues().one2OneTheme == .paper)
    }

    @Test("Le thème papier résout sur les jetons de la palette claire")
    func paperResolvesLightTokens() {
        let c = One2OneTheme.paper.colors
        #expect(c.base == One2OneToken.bgApp)
        #expect(c.canvas == One2OneToken.bgCanvas)
        #expect(c.card == One2OneToken.surface)
        #expect(c.cardActive == One2OneToken.actionBg)
        #expect(c.ink1 == One2OneToken.ink1)
        #expect(c.ink4 == One2OneToken.ink4)
        #expect(c.action == One2OneToken.action)
        #expect(c.report == One2OneToken.report)
    }

    @Test("Le thème séance résout sur les jetons dark/*")
    func sessionResolvesDarkTokens() {
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
    }

    /// Un thème dont le libellé mono ne serait pas lisible sur son propre fond
    /// serait un thème inutilisable : la règle des 4,5:1 vaut pour les deux.
    @Test("Dans les deux thèmes, le libellé mono atteint 4,5:1 sur le fond et sur la carte",
          arguments: One2OneTheme.allCases)
    func bothThemesReachContrast(theme: One2OneTheme) throws {
        let c = theme.colors
        let onBase = try #require(ContrastRatio.ratio(c.ink4, c.base))
        let onCard = try #require(ContrastRatio.ratio(c.ink4, c.card))
        #expect(onBase >= 4.5, "\(theme) ink4 sur base : \(String(format: "%.2f", onBase)):1")
        #expect(onCard >= 4.5, "\(theme) ink4 sur carte : \(String(format: "%.2f", onCard)):1")
    }

    @Test("Les deux thèmes ont un identifiant stable, mémorisable tel quel")
    func rawValuesAreStable() {
        #expect(One2OneTheme.paper.rawValue == "paper")
        #expect(One2OneTheme.session.rawValue == "session")
    }
}
