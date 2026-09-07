import Testing
import SwiftUI
@testable import OneToOne

/// « Aucune couleur ne doit apparaître à l'écran si elle n'est pas dans la table
/// §1.2 ; et tout texte sous 12 px doit atteindre 4,5:1 de contraste. » — spec de
/// refonte, §1.2.
///
/// Le second point est la seule règle de la table qu'un test peut vérifier seul :
/// la première est une règle de revue. Ce fichier tient donc la preuve
/// arithmétique du contraste, paire par paire, pour les couples réellement
/// employés sous 12 px par les maquettes 1a et 1b.
@Suite("Jetons One2One — la table §1.2 et le contraste")
struct One2OneTokensTests {

    /// Repère de calibrage : si le noir sur blanc ne donne pas 21:1, c'est la
    /// mesure qui est fausse, pas les jetons.
    @Test("Le noir sur blanc vaut 21:1 — la mesure est calibrée")
    func blackOnWhiteIsTwentyOne() throws {
        let ratio = try #require(ContrastRatio.ratio(.black, .white))
        #expect(abs(ratio - 21) < 0.05)
    }

    @Test("Une couleur identique à son fond vaut 1:1")
    func sameColorIsOne() throws {
        let ratio = try #require(ContrastRatio.ratio(One2OneToken.ink1, One2OneToken.ink1))
        #expect(abs(ratio - 1) < 0.001)
    }

    /// Les paires de la palette claire employées sous 12 px : libellés de section
    /// (mono 9,5), timecodes (mono 10), pilules et chips (10–10,5).
    @Test(
        "Chaque paire texte/fond de la palette claire employée sous 12 px atteint 4,5:1",
        arguments: [
            ("ink/4 sur surface", One2OneToken.ink4, One2OneToken.surface),
            ("ink/4 sur surface/alt", One2OneToken.ink4, One2OneToken.surfaceAlt),
            ("ink/4 sur bg/app", One2OneToken.ink4, One2OneToken.bgApp),
            ("ink/4 sur bg/canvas", One2OneToken.ink4, One2OneToken.bgCanvas),
            ("ink/3 sur surface", One2OneToken.ink3, One2OneToken.surface),
            ("action/ink sur action/bg", One2OneToken.actionInk, One2OneToken.actionBg),
            ("action/ink sur action/bg2", One2OneToken.actionInk, One2OneToken.actionBg2),
            ("report/ink sur report/bg", One2OneToken.reportInk, One2OneToken.reportBg),
            ("warn/ink sur warn/bg", One2OneToken.warnInk, One2OneToken.warnBg),
            ("oneonone/ink sur oneonone/bg", One2OneToken.oneOnOneInk, One2OneToken.oneOnOneBg),
            ("workshop sur workshop/bg", One2OneToken.workshop, One2OneToken.workshopBg),
            ("onFilledButton sur action", One2OneToken.onFilledButton, One2OneToken.action),
            ("onFilledButton sur report", One2OneToken.onFilledButton, One2OneToken.report),
        ]
    )
    func lightPairsReachFourAndAHalf(pair: (String, Color, Color)) throws {
        let (name, ink, background) = pair
        let ratio = try #require(ContrastRatio.ratio(ink, background))
        #expect(ratio >= 4.5, "\(name) : \(String(format: "%.2f", ratio)):1")
    }

    /// Mêmes règles pour le mode séance (capture 1b) : c'est un fond sombre, pas
    /// un mode sombre système, donc les paires doivent être vérifiées à part.
    @Test(
        "Chaque paire texte/fond de la palette séance employée sous 12 px atteint 4,5:1",
        arguments: [
            ("dark/ink4 sur dark/base", One2OneToken.darkInk4, One2OneToken.darkBase),
            ("dark/ink4 sur dark/transcript", One2OneToken.darkInk4, One2OneToken.darkTranscript),
            ("dark/ink4 sur dark/card", One2OneToken.darkInk4, One2OneToken.darkCard),
            ("dark/ink4 sur dark/cardActive", One2OneToken.darkInk4, One2OneToken.darkCardActive),
            ("dark/ink4 sur dark/pill", One2OneToken.darkInk4, One2OneToken.darkPill),
            ("dark/ink3 sur dark/base", One2OneToken.darkInk3, One2OneToken.darkBase),
            ("dark/action sur dark/base", One2OneToken.darkAction, One2OneToken.darkBase),
            ("dark/action sur dark/card", One2OneToken.darkAction, One2OneToken.darkCard),
            ("dark/report sur dark/base", One2OneToken.darkReport, One2OneToken.darkBase),
            ("dark/report sur dark/card", One2OneToken.darkReport, One2OneToken.darkCard),
            ("dark/warn sur dark/base", One2OneToken.darkWarn, One2OneToken.darkBase),
            ("dark/warn sur dark/card", One2OneToken.darkWarn, One2OneToken.darkCard),
        ]
    )
    func sessionPairsReachFourAndAHalf(pair: (String, Color, Color)) throws {
        let (name, ink, background) = pair
        let ratio = try #require(ContrastRatio.ratio(ink, background))
        #expect(ratio >= 4.5, "\(name) : \(String(format: "%.2f", ratio)):1")
    }

    /// `ink/muted` est explicitement réservé aux placeholders de 11,5 px et plus
    /// (spec §1.2). Le test documente qu'il **n'atteint pas** 4,5:1 : c'est la
    /// raison de la règle, et si un jour il l'atteignait, la règle aurait changé.
    @Test("ink/muted n'atteint pas 4,5:1 — d'où la règle « jamais sous 11,5 px »")
    func inkMutedIsBelowThreshold() throws {
        let ratio = try #require(ContrastRatio.ratio(One2OneToken.inkMuted, One2OneToken.surface))
        #expect(ratio < 4.5)
    }

    /// **Constat sur la table §1.2, relevé au lot 0A.** `accent/ok` ne publie
    /// que deux encres, `#2f9e5f` et `#2f7d4e` ; la plus profonde des deux
    /// mesure 4,43:1 sur son propre fond `#e8f3ec` — soit 0,07 sous le seuil de
    /// 4,5:1 que la spec impose sous 12 px. C'est la table qui fait foi, donc
    /// le jeton n'a pas été retouché : la mesure est figée ici pour que
    /// l'écart soit connu et pour qu'un futur assombrissement de `ok/deep` (la
    /// seule correction possible) soit une décision explicite.
    ///
    /// La pilule d'invite renseignée (`InvitePill.Etat.renseignee`) est la
    /// primitive concernée : elle emploie ce couple, conformément à la capture
    /// 1a, et son propre test de lisibilité renvoie à ce constat.
    @Test("ok/deep sur ok/bg est la meilleure encre que la table offre, à 4,43:1")
    func okDeepOnOkBackgroundIsJustBelowThreshold() throws {
        let profonde = try #require(ContrastRatio.ratio(One2OneToken.okDeep, One2OneToken.okBg))
        let vive = try #require(ContrastRatio.ratio(One2OneToken.ok, One2OneToken.okBg))
        #expect(profonde > vive, "ok/deep doit rester l'encre à préférer sur ok/bg")
        #expect(profonde >= 4.4)
        #expect(profonde < 4.5, "si ce test casse, la table a changé : reverser le couple dans la liste ≥ 4,5:1")
    }

    @Test("Les largeurs fixes de la conception sont celles de la spec §1.2")
    func fixedWidthsMatchSpec() {
        #expect(One2OneToken.actionsRailWidth == 330)
        #expect(One2OneToken.oneOnOneRailNarrow == 320)
        #expect(One2OneToken.oneOnOneRailWide == 356)
        #expect(One2OneToken.sideNavWidth == 190)
        #expect(One2OneToken.toolPaletteWidth == 52)
        #expect(One2OneToken.timeColumnWidth == 78)
        #expect(One2OneToken.projectPanelWidth == 430)
        #expect(One2OneToken.resourcesDrawerWidth == 396)
        #expect(One2OneToken.sessionTranscriptWidth == 400)
    }

    @Test("Les rayons de la conception sont ceux de la spec §1.2")
    func radiiMatchSpec() {
        #expect(One2OneToken.radiusPreview == 4)
        #expect(One2OneToken.radiusButton == 6)
        #expect(One2OneToken.radiusCard == 7)
        #expect(One2OneToken.radiusPanel == 10)
        #expect(One2OneToken.radiusPill == 11)
        #expect(One2OneToken.radiusAudio == 16)
    }

    /// L'ombre du panneau de fiche projet, spec §4.3 : `-8px 0 24px
    /// rgba(0,0,0,.07)`. Trois jetons plutôt qu'un littéral dans la vue :
    /// c'est la seule façon de garder vraie la règle « seul
    /// `One2OneTokens.swift` nomme une couleur » — et de la vérifier.
    @Test("L'ombre de panneau reprend -8px 0 24px rgba(0,0,0,.07)")
    func panelShadowMatchesSpec() {
        #expect(One2OneToken.panelShadowRadius == 24)
        #expect(One2OneToken.panelShadowOffsetX == -8)
        #expect(One2OneToken.panelShadow == Color.black.opacity(0.07))
    }

    /// La colonne principale passe à 55 % d'opacité quand la fiche projet
    /// s'ouvre (spec §4.3). Elle reste **consultable** : le dépoli est visuel,
    /// jamais un `allowsHitTesting(false)`.
    @Test("Le dépoli de la colonne principale vaut 55 %")
    func dimmedOpacityMatchesSpec() {
        #expect(One2OneToken.dimmedOpacity == 0.55)
    }
}
