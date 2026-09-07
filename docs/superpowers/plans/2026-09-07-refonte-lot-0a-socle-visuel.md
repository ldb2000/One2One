# Refonte — lot 0A : socle visuel et état d'écran

> **Pour les exécutants agentiques :** SOUS-COMPÉTENCE REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour dérouler ce plan tâche par tâche. Les étapes
> sont des cases à cocher (`- [ ]`).

**Objectif :** rendre reproductibles les jetons, la typographie et la géométrie de la
spécification §1.2, livrer les dix primitives visuelles de la refonte, et sortir l'état
d'écran de `MeetingView` dans un `MeetingScreenModel` — **sans aucun changement visuel**.

**Architecture :** un seul fichier nomme les couleurs de la refonte
(`One2OneTokens.swift`) ; la typographie résout les fontes IBM Plex embarquées par leurs
noms PostScript **abrégés** avec repli système ; les primitives sont des vues sans état,
chacune avec sa logique pure testée à part ; l'état d'écran devient un `@Observable`
`@MainActor` unique injecté par paramètre aux quatre vues qui portaient des `@Binding`
traversants.

**Pile technique :** Swift 6 / SwiftUI / SwiftData, exécutable SwiftPM, Swift Testing
(`import Testing`, suites en français), AppKit (`NSFont`, `CTFontManager`), aucune
dépendance SwiftPM nouvelle.

**Spécification :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §1.2
**Programme :** `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 0A »
**Référence copiée (jamais liée) :** `/Users/laurent.deberti/Documents/dev/perso/Teams-Capture/Sources/CaptureDesign/{Tokens,Typography}.swift`
et `Tests/CaptureDesignTests/TypographyTests.swift`
**Captures de référence :** `docs/superpowers/specs/refonte-2026-09/ecrans/1a-cockpit.png`, `1b-mode-seance.png`

## Contraintes globales

- Branche `feat/refonte-lot-0a-socle-visuel`, partie de `origin/master` (`a3c44f2`). Jamais de commit sur `master`.
- Commits conventionnels, un par tâche, terminés par `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- `swift build` avant chaque commit. `swift test --filter <NomDeSuite>` en cours de route.
  `swift test` complet et **vert** avant la PR (référence : 1 037 XCTest + 618 Swift Testing).
- Aucune dépendance SwiftPM nouvelle. Les fontes sont des **ressources** (`Package.swift` a déjà `.process("Resources")`).
- Aucun test ne touche MLX, ScreenCaptureKit, WebKit interactif ni une session graphique.
- Libellés d'interface et commentaires en **français**, symboles en **anglais**.
- Énums persistées en `…Raw: String` + wrapper calculé (ici : `MeetingScreenModel` persiste dans `UserDefaults`, pas dans SwiftData — la règle s'applique par analogie : on écrit des `rawValue` de `String`).
- **Ne toucher à aucun de ces fichiers** (lot 0B en parallèle) : `Models/SchemaVersions.swift`, `Models/*`, `Services/Live/`, `Services/ConfidentialityFilter.swift`, `Services/MeetingNoteStore.swift`.
- **Ne pas toucher** aux chemins `adoptPendingLiveNotes()` / `discardEmptyNoteIfNeeded()` de `MeetingView.swift` (lignes ~384–515), ni au `.preferredColorScheme(.light)` épinglé dans `OneToOneApp.swift`.
- `activeSection` de `MeetingView` **reste un `@State`** dans ce lot (les espaces arrivent au lot 1).
- Aucune vue existante n'utilise les primitives à la fin de ce lot : elles sont livrées avec leurs `#Preview` et leurs tests, pas câblées.

---

## Carte des fichiers

### Créés

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Views/DesignSystem/One2OneTokens.swift` | `enum One2OneToken` : la table §1.2 complète (fonds, bordures, encres, accents, palette `dark/*` complète, rayons, densités, largeurs fixes). **Seul fichier qui nomme une couleur de la refonte.** Porte l'init privé `Color(hex:)`. |
| `OneToOne/Views/DesignSystem/ContrastRatio.swift` | Fonctions pures WCAG 2.1 : luminance relative et ratio de contraste entre deux `Color`. |
| `OneToOne/Views/DesignSystem/One2OneTypography.swift` | `PlexWeight`, `PlexFont` (noms PostScript abrégés, enregistrement des fontes embarquées, repli système), `Font.plexSans/plexMono`, `View.sectionLabel()`. |
| `OneToOne/Views/DesignSystem/One2OneTheme.swift` | `One2OneTheme` (`.paper`/`.session`), `One2OneColors` (couleurs résolues), clé et accesseur `EnvironmentValues.one2OneTheme`. |
| `OneToOne/Views/DesignSystem/Components/Refonte/SectionLabel.swift` | Primitive libellé de section. |
| `OneToOne/Views/DesignSystem/Components/Refonte/MonoMeta.swift` | Primitive métadonnée mono. |
| `OneToOne/Views/DesignSystem/Components/Refonte/TimecodeLabel.swift` | Primitive timecode `mm:ss` largeur fixe + `TimecodeLabel.format(_:)`. |
| `OneToOne/Views/DesignSystem/Components/Refonte/Chip.swift` | Primitive chip (rayon 5–6). |
| `OneToOne/Views/DesignSystem/Components/Refonte/Pill.swift` | Primitive pilule (rayon 11). |
| `OneToOne/Views/DesignSystem/Components/Refonte/InvitePill.swift` | Primitive pilule d'invite (`＋ assigner`), trois états. |
| `OneToOne/Views/DesignSystem/Components/Refonte/RefonteCard.swift` | Primitive carte (rayon 7, bordure `border/card`, padding 9–13). |
| `OneToOne/Views/DesignSystem/Components/Refonte/AvatarStack.swift` | Primitive pile d'avatars 19 px, chevauchement −6, max 6 puis `+n` + `AvatarStack.layout(...)`. |
| `OneToOne/Views/DesignSystem/Components/Refonte/ProgressBar.swift` | Primitive barre de progression + `ProgressBar.clamp(_:)`. |
| `OneToOne/Views/DesignSystem/Components/Refonte/SegmentedMode.swift` | Primitive sélecteur segmenté générique, segment actif `ink/1` plein. |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | `@Observable @MainActor` : espace, mode temporel, brouillon d'action, bascules d'affichage, persistance par réunion. |
| `OneToOne/Resources/Fonts/IBMPlexSans-Regular.ttf` … (5 fichiers) | Fontes IBM Plex embarquées (OFL). |
| `OneToOne/Resources/Fonts/OFL.txt` | Licence SIL Open Font License 1.1 copiée à côté des fichiers. |
| `Tests/One2OneTokensTests.swift` | Suite « Jetons One2One — la table §1.2 et le contraste ». |
| `Tests/One2OneTypographyTests.swift` | Suite « Typographie Plex — les cinq noms PostScript ». |
| `Tests/One2OneThemeTests.swift` | Suite « Thème One2One — papier et séance ». |
| `Tests/One2OnePrimitivesTests.swift` | Suite « Primitives de la refonte — leurs règles pures ». |
| `Tests/MeetingScreenModelTests.swift` | Suite « MeetingScreenModel — l'état d'écran d'une réunion ». |

### Modifiés

| Fichier | Modification |
| --- | --- |
| `OneToOne/OneToOneApp.swift` | Un appel `PlexFont.ensureRegistered()` en tête de `init()`. Rien d'autre. |
| `OneToOne/Views/MeetingView.swift` | Retrait de 12 `@State` (brouillon d'action, `showSpeakersView`, `showPlayback`, `newAdhocName`, `suggestedTagNames`) au profit de `@State private var screen = MeetingScreenModel()`. Les sites de lecture/écriture passent par `screen.…`. |
| `OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift` | Les 8 `@Binding` du brouillon d'action → un `MeetingScreenModel` en paramètre. |
| `OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift` | Idem. |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | `@Binding var suggestedTagNames` → `MeetingScreenModel` en paramètre. |
| `OneToOne/Views/Meeting/ManageParticipantsSheet.swift` | `@Binding var newAdhocName` → `MeetingScreenModel` en paramètre. |
| `STATUS.md` | Nouvelle section en tête. |

---

## Tâche 1 : jetons de la refonte et ratio de contraste

**Fichiers :**
- Créer : `OneToOne/Views/DesignSystem/ContrastRatio.swift`
- Créer : `OneToOne/Views/DesignSystem/One2OneTokens.swift`
- Test : `Tests/One2OneTokensTests.swift`

**Interfaces :**
- Consomme : rien.
- Produit :
  - `enum ContrastRatio` : `static func components(_ color: Color) -> (r: Double, g: Double, b: Double)?`, `static func relativeLuminance(_ color: Color) -> Double?`, `static func ratio(_ a: Color, _ b: Color) -> Double?`
  - `enum One2OneToken` avec, en `static let` : `bgApp`, `bgCanvas`, `surface`, `surfaceAlt`, `hair`, `cardBorder`, `strongBorder`, `ink1`…`ink4`, `inkMuted`, `action`, `actionBg`, `actionBg2`, `actionInk`, `report`, `reportBg`, `reportInk`, `ok`, `okDeep`, `okBg`, `warn`, `warnInk`, `warnBg`, `oneOnOne`, `oneOnOneInk`, `oneOnOneBg`, `workshop`, `workshopBg`, `darkBase`, `darkTranscript`, `darkCard`, `darkCardActive`, `darkPill`, `darkInk1`…`darkInk4`, `darkAction`, `darkReport`, `darkWarn`, `captureMarker`, `scrim`, `onFilledButton` (type `Color`) ; `radiusPreview`, `radiusButton`, `radiusCard`, `radiusPanel`, `radiusPill`, `radiusAudio`, `cardPaddingMin`, `cardPaddingMax`, `cardGap`, `tableRowPaddingV`, `actionsRailWidth`, `oneOnOneRailNarrow`, `oneOnOneRailWide`, `sideNavWidth`, `toolPaletteWidth`, `timeColumnWidth`, `projectPanelWidth`, `resourcesDrawerWidth`, `sessionTranscriptWidth` (type `CGFloat`).

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/One2OneTokensTests.swift` :

```swift
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
            ("ok/deep sur ok/bg", One2OneToken.okDeep, One2OneToken.okBg),
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
}
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

```bash
swift test --filter One2OneTokensTests
```
Attendu : ÉCHEC de compilation — `cannot find 'ContrastRatio' in scope`, `cannot find 'One2OneToken' in scope`.

- [ ] **Étape 3 : écrire `ContrastRatio.swift`**

```swift
import AppKit
import SwiftUI

/// Ratio de contraste WCAG 2.1 entre deux couleurs.
///
/// Fonctions **pures** : elles ne dépendent que des composantes sRGB de la
/// couleur, pas d'une session graphique. La conversion passe par `NSColor`
/// parce que `Color` ne publie pas ses composantes ; `usingColorSpace(.sRGB)`
/// suffit et ne touche pas au serveur de fenêtres.
///
/// Sert au test de contraste des jetons (spec §1.2 : « tout texte sous 12 px
/// doit atteindre 4,5:1 »). Rendre `nil` plutôt que 1 ou 21 sur une couleur
/// inconvertible est volontaire : un test doit échouer bruyamment, pas mesurer
/// un contraste imaginaire.
enum ContrastRatio {

    /// Composantes sRGB de la couleur, normalisées 0…1, ou `nil` si la couleur
    /// n'est pas convertible en sRGB (couleur dynamique, motif…).
    static func components(_ color: Color) -> (r: Double, g: Double, b: Double)? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
    }

    /// Linéarisation d'une composante sRGB (WCAG 2.1, formule de la luminance
    /// relative).
    static func linearized(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// Luminance relative 0…1.
    static func relativeLuminance(_ color: Color) -> Double? {
        guard let c = components(color) else { return nil }
        return 0.2126 * linearized(c.r) + 0.7152 * linearized(c.g) + 0.0722 * linearized(c.b)
    }

    /// Ratio de contraste, toujours ≥ 1 quel que soit l'ordre des arguments.
    static func ratio(_ a: Color, _ b: Color) -> Double? {
        guard let la = relativeLuminance(a), let lb = relativeLuminance(b) else { return nil }
        let lighter = max(la, lb), darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
```

- [ ] **Étape 4 : écrire `One2OneTokens.swift`**

Copie de `Teams-Capture/Sources/CaptureDesign/Tokens.swift`, renommée `One2OneToken`,
complétée de la palette `dark/*` du mode séance et des largeurs fixes de la spec §1.2.
`public` retiré : OneToOne est un module unique.

```swift
import SwiftUI

/// Les jetons visuels de la refonte de l'écran de réunion, spec §1.2.
///
/// C'est le **seul** endroit du projet où une couleur de la refonte est écrite.
/// Une couleur qui n'est pas dans cette table n'a pas à apparaître sur un écran
/// refondu. Les palettes historiques (`AppTheme`, `MeetingTheme`, `FicheTokens`)
/// restent en place pour les écrans non refondus : elles ne sont ni fusionnées
/// ni supprimées ici.
///
/// Copié depuis `Teams-Capture/Sources/CaptureDesign/Tokens.swift` (règle du
/// programme : copier, jamais lier), puis complété.
enum One2OneToken {

    // MARK: - Fonds

    static let bgApp = Color(hex: 0xF7F4EE)
    static let bgCanvas = Color(hex: 0xFAF8F4)
    static let surface = Color(hex: 0xFFFFFF)
    static let surfaceAlt = Color(hex: 0xFDFCFA)

    // MARK: - Bordures

    static let hair = Color.black.opacity(0.07)
    static let cardBorder = Color.black.opacity(0.09)
    static let strongBorder = Color.black.opacity(0.14)

    // MARK: - Encres

    static let ink1 = Color(hex: 0x1A1A1A)
    static let ink2 = Color(hex: 0x2A2723)
    static let ink3 = Color(hex: 0x4A453D)
    static let ink4 = Color(hex: 0x6B6659)
    /// Placeholder et métadonnée. **Jamais sous 11,5 px** : n'atteint pas 4,5:1
    /// sur `surface` (cf. `One2OneTokensTests`).
    static let inkMuted = Color(hex: 0x7D7768)

    // MARK: - Accents

    static let action = Color(hex: 0x2563D9)
    static let actionBg = Color(hex: 0xEEF2FD)
    static let actionBg2 = Color(hex: 0xF7FAFF)
    static let actionInk = Color(hex: 0x1B4DAD)

    static let report = Color(hex: 0xB8544C)
    static let reportBg = Color(hex: 0xFBECEB)
    static let reportInk = Color(hex: 0x8F3F38)

    static let ok = Color(hex: 0x2F9E5F)
    static let okDeep = Color(hex: 0x2F7D4E)
    static let okBg = Color(hex: 0xE8F3EC)

    static let warn = Color(hex: 0xD98324)
    static let warnInk = Color(hex: 0x8A5A12)
    static let warnBg = Color(hex: 0xF9EFE0)

    static let oneOnOne = Color(hex: 0x6B4D8F)
    static let oneOnOneInk = Color(hex: 0x5C4180)
    static let oneOnOneBg = Color(hex: 0xF4F1F6)

    static let workshop = Color(hex: 0x1F6B6B)
    static let workshopBg = Color(hex: 0xF2F8F7)

    // MARK: - Palette sombre du mode séance (capture 1b)

    /// Fond général du mode séance.
    static let darkBase = Color(hex: 0x1C1A17)
    /// Fond de la colonne de transcription, un cran plus sombre que la base.
    static let darkTranscript = Color(hex: 0x191714)
    /// Carte au repos.
    static let darkCard = Color(hex: 0x221F1B)
    /// Carte active — le segment de transcription survolé ou sélectionné.
    static let darkCardActive = Color(hex: 0x232019)
    /// Pilule et champ.
    static let darkPill = Color(hex: 0x2F2B26)

    static let darkInk1 = Color(hex: 0xF2EFE9)
    static let darkInk2 = Color(hex: 0xE6E1D8)
    static let darkInk3 = Color(hex: 0xC9C3B8)
    static let darkInk4 = Color(hex: 0x9A9285)

    static let darkAction = Color(hex: 0x9AB6F0)
    /// Décision et rapport sur fond sombre. Absent de `Teams-Capture`, qui
    /// n'affiche que la pastille : ajouté pour le mode séance.
    static let darkReport = Color(hex: 0xE8B0AA)
    static let darkWarn = Color(hex: 0xE8C48A)

    // MARK: - Cas particuliers

    /// Marqueur de capture sur la frise. Bleu profond, distinct de `action`, qui
    /// est réservé au marqueur de la **dernière** capture.
    static let captureMarker = Color(hex: 0x3D5180)

    /// Voile d'assombrissement. Pas dans la table du §1.2 : c'est un voile, pas
    /// une couleur de la charte, mais il n'a pas à être écrit en clair dans une
    /// vue — sinon la règle « seul ce fichier nomme une couleur » cesse d'être
    /// vraie et cesse donc d'être vérifiable.
    static let scrim = Color.black.opacity(0.45)

    /// Texte sur les boutons pleins, quel que soit le fond. Même raison que
    /// `scrim`.
    static let onFilledButton = Color.white

    // MARK: - Rayons (spec §1.2, Géométrie)

    static let radiusPreview: CGFloat = 4
    static let radiusButton: CGFloat = 6
    static let radiusCard: CGFloat = 7
    static let radiusPanel: CGFloat = 10
    static let radiusPill: CGFloat = 11
    static let radiusAudio: CGFloat = 16

    // MARK: - Densités (spec §1.2, Géométrie)

    static let cardPaddingMin: CGFloat = 9
    static let cardPaddingMax: CGFloat = 13
    static let cardGap: CGFloat = 12
    static let tableRowPaddingV: CGFloat = 8

    // MARK: - Largeurs fixes (spec §1.2, Géométrie)

    /// Rail d'actions des types multi-participants.
    static let actionsRailWidth: CGFloat = 330
    /// Rail 1:1 côté manager.
    static let oneOnOneRailNarrow: CGFloat = 320
    /// Rail 1:1 côté collaborateur.
    static let oneOnOneRailWide: CGFloat = 356
    /// Navigation latérale du poste de pilotage (mode Relire).
    static let sideNavWidth: CGFloat = 190
    /// Palette d'outils de l'atelier.
    static let toolPaletteWidth: CGFloat = 52
    /// Colonne temps du mode séance.
    static let timeColumnWidth: CGFloat = 78
    /// Panneau de fiche projet.
    static let projectPanelWidth: CGFloat = 430
    /// Tiroir de ressources.
    static let resourcesDrawerWidth: CGFloat = 396
    /// Colonne de transcription du mode séance.
    static let sessionTranscriptWidth: CGFloat = 400
}

private extension Color {
    /// Couleur depuis un littéral hexadécimal `0xRRGGBB`, pour transcrire la
    /// table des jetons telle quelle.
    ///
    /// Volontairement **privée au fichier** : c'est `One2OneTokens.swift` qui a
    /// le droit de nommer une couleur, pas le reste de l'application. Si un jour
    /// cette contrainte doit sauter, ce sera une décision explicite, pas un
    /// effet de bord.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
```

- [ ] **Étape 5 : lancer le test pour vérifier qu'il passe**

```bash
swift test --filter One2OneTokensTests
```
Attendu : SUCCÈS.

Si `ContrastRatio.ratio` rend `nil` (donc `#require` échoue) parce que `NSColor(Color)`
ne convertit pas hors session graphique : ne pas contourner le test. Ajouter dans
`One2OneTokens.swift` un `enum One2OneToken.Hex` de `UInt32` dont les `Color` dérivent
(source unique), exposer `ContrastRatio.ratio(_ a: UInt32, _ b: UInt32) -> Double` et
faire porter les tests sur les hexadécimaux. Consigner l'écart dans `STATUS.md`.

Si une paire échoue le seuil de 4,5:1 : **ne pas modifier la valeur du jeton** (la table
§1.2 fait foi). Retirer la paire de la liste et la consigner dans `STATUS.md` comme
combinaison interdite sous 12 px, avec la valeur mesurée.

- [ ] **Étape 6 : `swift build` puis commit**

```bash
swift build
git add OneToOne/Views/DesignSystem/One2OneTokens.swift OneToOne/Views/DesignSystem/ContrastRatio.swift Tests/One2OneTokensTests.swift
git commit -m "$(cat <<'EOF'
feat(refonte): jetons One2One de la spec §1.2 et mesure de contraste

Copie de Tokens.swift de Teams-Capture, complétée de la palette dark/* du
mode séance (dont dark/accent report #e8b0aa, #191714, #232019) et des
largeurs fixes 330/320/356/190/52/78/430/396/400. ContrastRatio prouve
par test les 4,5:1 exigés sous 12 px.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 2 : typographie IBM Plex et fontes embarquées

**Fichiers :**
- Créer : `OneToOne/Resources/Fonts/IBMPlexSans-Regular.ttf`, `IBMPlexSans-Medium.ttf`, `IBMPlexSans-SemiBold.ttf`, `IBMPlexMono-Medium.ttf`, `IBMPlexMono-SemiBold.ttf`, `OFL.txt`
- Créer : `OneToOne/Views/DesignSystem/One2OneTypography.swift`
- Modifier : `OneToOne/OneToOneApp.swift` (un appel dans `init()`)
- Test : `Tests/One2OneTypographyTests.swift`

**Interfaces :**
- Consomme : `One2OneToken.ink4` (tâche 1).
- Produit :
  - `enum PlexWeight { case regular, medium, semibold }` avec `var sansPostScriptName: String`, `var monoPostScriptName: String`, `var systemWeight: Font.Weight`
  - `enum PlexFont` : `static let requiredPostScriptNames: [String]`, `static let bundledFileNames: [String]`, `static func bundledFontURLs() -> [URL]`, `static func ensureRegistered()`, `static func isInstalled(_ postScriptName: String) -> Bool`
  - `Font.plexSans(_ size: CGFloat, _ weight: PlexWeight = .regular) -> Font`
  - `Font.plexMono(_ size: CGFloat, _ weight: PlexWeight = .medium) -> Font`
  - `View.sectionLabel() -> some View`

- [ ] **Étape 1 : récupérer les fontes et la licence**

Les cinq graisses de la spec (Plex Sans 400/500/600, Plex Mono 500/600), depuis le dépôt
officiel `IBM/plex` (OFL). **Vérifié le 2026-09-07 : ces fichiers portent bien les noms
PostScript abrégés** (`IBMPlexSans-Medm`, `IBMPlexSans-SmBld`, `IBMPlexMono-Medm`,
`IBMPlexMono-SmBld`), ce qui est la condition de tout le reste.

```bash
mkdir -p OneToOne/Resources/Fonts
B=https://raw.githubusercontent.com/IBM/plex/master/packages
curl -fsSL -o OneToOne/Resources/Fonts/IBMPlexSans-Regular.ttf  "$B/plex-sans/fonts/complete/ttf/IBMPlexSans-Regular.ttf"
curl -fsSL -o OneToOne/Resources/Fonts/IBMPlexSans-Medium.ttf   "$B/plex-sans/fonts/complete/ttf/IBMPlexSans-Medium.ttf"
curl -fsSL -o OneToOne/Resources/Fonts/IBMPlexSans-SemiBold.ttf "$B/plex-sans/fonts/complete/ttf/IBMPlexSans-SemiBold.ttf"
curl -fsSL -o OneToOne/Resources/Fonts/IBMPlexMono-Medium.ttf   "$B/plex-mono/fonts/complete/ttf/IBMPlexMono-Medium.ttf"
curl -fsSL -o OneToOne/Resources/Fonts/IBMPlexMono-SemiBold.ttf "$B/plex-mono/fonts/complete/ttf/IBMPlexMono-SemiBold.ttf"
curl -fsSL -o OneToOne/Resources/Fonts/OFL.txt                  "https://raw.githubusercontent.com/IBM/plex/master/LICENSE.txt"
ls -l OneToOne/Resources/Fonts/
head -3 OneToOne/Resources/Fonts/OFL.txt
```

Attendu : 5 fichiers de 100–260 Ko et `OFL.txt` de ~4,5 Ko commençant par
`Copyright © 2017 IBM Corp. with Reserved Font Name "Plex"` puis
`This Font Software is licensed under the SIL Open Font License, Version 1.1.`

Si le réseau est indisponible : copier les mêmes graisses depuis `~/Library/Fonts`
(`IBMPlexSans-Regular.otf`, `-Medium.otf`, `-SemiBold.otf`, `IBMPlexMono-Medium.otf`,
`-SemiBold.otf`, IBM Plex 2.005, noms PostScript abrégés eux aussi), écrire `OFL.txt`
depuis le texte de la SIL OFL 1.1, adapter `bundledFileNames` à l'extension `.otf`, et
**consigner l'écart dans `STATUS.md`**.

- [ ] **Étape 2 : écrire les tests qui échouent**

Créer `Tests/One2OneTypographyTests.swift` — port du test des cinq noms de
`Teams-Capture/Tests/CaptureDesignTests/TypographyTests.swift`, augmenté de la
vérification que les fichiers sont bien dans le bundle (parade du risque « fontes Plex
absentes du bundle », programme §8).

```swift
import Testing
import SwiftUI
import AppKit
@testable import OneToOne

/// « La consigne est la reproduction stricte ; repli système si le chargement
/// échoue. » — décision D2 du programme de refonte.
///
/// Porté de `Teams-Capture/Tests/CaptureDesignTests/TypographyTests.swift`, où
/// Plex était seulement *installé sur le poste*. OneToOne embarque en plus les
/// fichiers, donc deux choses sont à prouver et non une : que les cinq noms
/// résolvent, et que les fichiers voyagent bien dans le bundle — sans quoi le
/// rendu se dégraderait silencieusement sur un poste sans Plex installé.
@Suite("Typographie Plex — les cinq noms PostScript")
struct One2OneTypographyTests {

    @Test("Les cinq graisses de la conception sont embarquées dans le bundle")
    func bundledFontFilesArePresent() {
        let urls = PlexFont.bundledFontURLs()
        #expect(urls.count == PlexFont.bundledFileNames.count,
                "fichiers trouvés : \(urls.map(\.lastPathComponent))")
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("Après enregistrement, les cinq noms PostScript résolvent")
    func plexResolvesAfterRegistration() {
        PlexFont.ensureRegistered()
        for name in PlexFont.requiredPostScriptNames {
            #expect(NSFont(name: name, size: 12) != nil, "fonte absente : \(name)")
        }
    }

    @Test("L'API rend les noms PostScript abrégés, pas les noms longs auxquels on s'attendrait")
    func apiUsesAbbreviatedNames() {
        // Ce test-ci documente le piège : `PlexWeight` rend bien les noms
        // abrégés (`Medm`, `SmBld`), pas les noms longs (`Medium`, `SemiBold`)
        // qu'une lecture naïve du design attendrait. Demander le nom long rend
        // `nil` et fait retomber silencieusement sur la fonte système — d'où le
        // besoin de le figer par un test.
        #expect(PlexWeight.regular.sansPostScriptName == "IBMPlexSans")
        #expect(PlexWeight.medium.sansPostScriptName == "IBMPlexSans-Medm")
        #expect(PlexWeight.semibold.sansPostScriptName == "IBMPlexSans-SmBld")
        #expect(PlexWeight.medium.monoPostScriptName == "IBMPlexMono-Medm")
        #expect(PlexWeight.semibold.monoPostScriptName == "IBMPlexMono-SmBld")
        #expect(PlexFont.isInstalled("IBMPlexSans-SemiBold") == false)
        #expect(PlexFont.isInstalled("IBMPlexSans-Medium") == false)
    }

    @Test("Les cinq rôles typographiques de la conception sont couverts")
    func requiredNamesCoverSpec() {
        #expect(Set(PlexFont.requiredPostScriptNames) == Set([
            "IBMPlexSans", "IBMPlexSans-Medm", "IBMPlexSans-SmBld",
            "IBMPlexMono-Medm", "IBMPlexMono-SmBld",
        ]))
    }

    @Test("Une fonte inexistante retombe sur la fonte système sans lever")
    func unknownNameFallsBack() {
        #expect(PlexFont.isInstalled("IBMPlexSans-Fantome") == false)
        // `plexSans` ne doit jamais lever ni rendre une fonte nulle : le repli
        // est la garantie que l'écran reste lisible sur un poste dégradé.
        _ = Font.plexSans(12, .semibold)
        _ = Font.plexMono(10, .medium)
    }
}
```

- [ ] **Étape 3 : lancer le test pour vérifier qu'il échoue**

```bash
swift test --filter One2OneTypographyTests
```
Attendu : ÉCHEC de compilation — `cannot find 'PlexFont' in scope`.

- [ ] **Étape 4 : écrire `One2OneTypography.swift`**

Copie de `Teams-Capture/Sources/CaptureDesign/Typography.swift`, augmentée de
l'enregistrement des fontes embarquées. La localisation des ressources reprend
exactement le schéma de `MermaidResourceLocator` (`Bundle.module` en développement, puis
`Contents/Resources/OneToOne_OneToOne.bundle` dans le `.app` packagé par
`Scripts/bump-and-build.sh`).

```swift
import AppKit
import CoreText
import SwiftUI

/// Les trois graisses de Plex utilisées par la conception.
enum PlexWeight: Sendable {
    case regular
    case medium
    case semibold

    /// Nom PostScript de la variante sans-serif.
    ///
    /// Attention aux abréviations : `Medm` et `SmBld`, pas `Medium` ni
    /// `SemiBold`. Les noms longs n'existent pas dans les fichiers d'IBM Plex ;
    /// les demander rend `nil` et fait retomber silencieusement sur la fonte
    /// système.
    var sansPostScriptName: String {
        switch self {
        case .regular: "IBMPlexSans"
        case .medium: "IBMPlexSans-Medm"
        case .semibold: "IBMPlexSans-SmBld"
        }
    }

    /// Nom PostScript de la variante monospace. Même piège d'abréviation.
    var monoPostScriptName: String {
        switch self {
        case .regular: "IBMPlexMono"
        case .medium: "IBMPlexMono-Medm"
        case .semibold: "IBMPlexMono-SmBld"
        }
    }

    /// Graisse équivalente sur la fonte système, pour la retombée.
    var systemWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}

/// Résolution des fontes Plex : enregistrement des fichiers embarqués, puis
/// interrogation par nom PostScript.
enum PlexFont {

    /// Les cinq noms dont la conception a besoin (spec §1.2, Typographie). Un
    /// test vérifie qu'ils résolvent : leur disparition doit être un échec
    /// bruyant, pas une typographie qui change de fonte sans le dire.
    static let requiredPostScriptNames = [
        "IBMPlexSans",
        "IBMPlexSans-Medm",
        "IBMPlexSans-SmBld",
        "IBMPlexMono-Medm",
        "IBMPlexMono-SmBld",
    ]

    /// Les fichiers embarqués, dans `OneToOne/Resources/Fonts/` (OFL, licence
    /// copiée à côté dans `OFL.txt`). Plex Sans 400/500/600 et Plex Mono
    /// 500/600 : exactement les cinq rôles de `requiredPostScriptNames`.
    static let bundledFileNames = [
        "IBMPlexSans-Regular.ttf",
        "IBMPlexSans-Medium.ttf",
        "IBMPlexSans-SemiBold.ttf",
        "IBMPlexMono-Medium.ttf",
        "IBMPlexMono-SemiBold.ttf",
    ]

    private static let resourceBundleName = "OneToOne_OneToOne.bundle"

    /// URL des fichiers de fonte réellement trouvés.
    ///
    /// Deux dispositions à couvrir, comme pour `mermaid.min.js` : en
    /// développement `Bundle.module` résout (l'exécutable et
    /// `OneToOne_OneToOne.bundle` sont voisins dans `.build/<config>/`) ; dans
    /// le `.app` packagé par `Scripts/bump-and-build.sh`, le bundle de
    /// ressources est copié un niveau plus bas, sous `Contents/Resources/`, là
    /// où l'accesseur généré ne regarde pas. `.process("Resources")` peut aussi
    /// aplatir `Fonts/` à la racine du bundle selon la version de SwiftPM :
    /// les deux emplacements sont donc essayés.
    static func bundledFontURLs() -> [URL] {
        bundledFileNames.compactMap { fileName in
            let stem = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            if let url = Bundle.module.url(forResource: stem, withExtension: ext, subdirectory: "Fonts") {
                return url
            }
            if let url = Bundle.module.url(forResource: stem, withExtension: ext) {
                return url
            }
            return packagedFontURL(fileName: fileName)
        }
    }

    /// `resourceRoot/OneToOne_OneToOne.bundle/[Fonts/]<fichier>` — disposition
    /// produite par `bump-and-build.sh`. `resourceRoot` injectable pour les tests.
    static func packagedFontURL(fileName: String, resourceRoot: URL? = Bundle.main.resourceURL) -> URL? {
        guard let resourceRoot else { return nil }
        let bundleRoot = resourceRoot.appendingPathComponent(resourceBundleName, isDirectory: true)
        for candidate in [
            bundleRoot.appendingPathComponent("Fonts", isDirectory: true).appendingPathComponent(fileName),
            bundleRoot.appendingPathComponent(fileName),
        ] where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    /// Enregistrement au premier besoin, une seule fois pour tout le process
    /// (`static let` = garanti unique par le runtime Swift). Portée `.process` :
    /// les fontes ne sont pas installées sur le poste de l'utilisateur, elles
    /// vivent le temps de l'exécution.
    private static let registration: [String] = {
        var failures: [String] = []
        for url in bundledFontURLs() {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let message = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "raison inconnue"
                failures.append("\(url.lastPathComponent) : \(message)")
            }
        }
        if !failures.isEmpty {
            // Pas de `fatalError` : une fonte manquante dégrade le rendu, elle
            // ne casse pas l'application. Le repli système fait le reste, et le
            // test `bundledFontFilesArePresent` est là pour que la dégradation
            // ne passe pas inaperçue en intégration.
            print("[PlexFont] enregistrement partiel : \(failures.joined(separator: ", "))")
        }
        return failures
    }()

    /// Force l'enregistrement. Appelé par `isInstalled`, donc par tout usage de
    /// `plexSans`/`plexMono` : il n'y a pas d'ordre de lancement à respecter.
    /// Également appelé explicitement au démarrage de l'application, pour que la
    /// première image dessinée soit déjà à la bonne fonte.
    static func ensureRegistered() {
        _ = registration
    }

    static func isInstalled(_ postScriptName: String) -> Bool {
        ensureRegistered()
        return NSFont(name: postScriptName, size: 12) != nil
    }
}

extension Font {
    /// Plex Sans à la taille et la graisse demandées, ou la fonte système si
    /// Plex ne résout pas.
    ///
    /// Ne jamais chaîner `.weight(...)` par-dessus : la graisse est déjà dans le
    /// fichier de fonte, et la redemander pousse SwiftUI à en synthétiser une.
    static func plexSans(_ size: CGFloat, _ weight: PlexWeight = .regular) -> Font {
        PlexFont.isInstalled(weight.sansPostScriptName)
            ? .custom(weight.sansPostScriptName, fixedSize: size)
            : .system(size: size, weight: weight.systemWeight)
    }

    /// Plex Mono, mêmes règles. Sert aux timecodes et aux libellés de section.
    static func plexMono(_ size: CGFloat, _ weight: PlexWeight = .medium) -> Font {
        PlexFont.isInstalled(weight.monoPostScriptName)
            ? .custom(weight.monoPostScriptName, fixedSize: size)
            : .system(size: size, weight: weight.systemWeight, design: .monospaced)
    }
}

extension View {
    /// Libellé de section : Plex Mono 600 à 9,5 pt, majuscules, interlettrage
    /// 0,07 em, couleur `ink/4`. Jamais `ink/muted` : sous 12 pt il faut 4,5:1
    /// de contraste (spec §1.2).
    func sectionLabel() -> some View {
        self.font(.plexMono(9.5, .semibold))
            .tracking(9.5 * 0.07)
            .textCase(.uppercase)
            .foregroundStyle(One2OneToken.ink4)
    }
}
```

- [ ] **Étape 5 : appeler l'enregistrement au lancement**

Dans `OneToOne/OneToOneApp.swift`, première ligne du corps de `init()`, avant la
construction du `ModelContainer` :

```swift
    init() {
        // Fontes IBM Plex embarquées enregistrées avant la première image
        // dessinée. `isInstalled` le referait au premier usage, mais un
        // enregistrement tardif ferait clignoter la typographie.
        PlexFont.ensureRegistered()

        // Store dédié sous `Application Support/OneToOne/OneToOne.store` : …
```

- [ ] **Étape 6 : lancer le test pour vérifier qu'il passe**

```bash
swift test --filter One2OneTypographyTests
```
Attendu : SUCCÈS, les 5 tests.

`apiUsesAbbreviatedNames` attend que `IBMPlexSans-SemiBold` et `IBMPlexSans-Medium`
**ne** résolvent **pas**. Si l'un résout, c'est qu'une version ≥ 6 de Plex a été
embarquée (noms longs) ou est installée sur le poste : reprendre l'étape 1 avec des
fichiers dont `psname` rend bien les formes abrégées, ou retirer l'assertion et
consigner l'écart dans `STATUS.md`.

- [ ] **Étape 7 : `swift build` puis commit**

```bash
swift build
git add OneToOne/Resources/Fonts OneToOne/Views/DesignSystem/One2OneTypography.swift OneToOne/OneToOneApp.swift Tests/One2OneTypographyTests.swift
git commit -m "$(cat <<'EOF'
feat(refonte): typographie Plex et fontes IBM Plex embarquées

Copie de Typography.swift de Teams-Capture (noms PostScript abrégés
IBMPlexSans-Medm / -SmBld, jamais .weight() par-dessus) et de son test des
cinq noms. Plex Sans 400/500/600 et Plex Mono 500/600 embarqués sous
Resources/Fonts avec la licence OFL, enregistrés par
CTFontManagerRegisterFontsForURL en portée .process ; repli système conservé.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 3 : thème d'écran (`.paper` / `.session`) par environnement

**Fichiers :**
- Créer : `OneToOne/Views/DesignSystem/One2OneTheme.swift`
- Test : `Tests/One2OneThemeTests.swift`

**Interfaces :**
- Consomme : `One2OneToken.*` (tâche 1), `ContrastRatio.ratio` (tâche 1).
- Produit :
  - `enum One2OneTheme: String, CaseIterable, Sendable { case paper, session }` avec `var colors: One2OneColors`
  - `struct One2OneColors: Sendable` — champs `base`, `canvas`, `card`, `cardActive`, `pill`, `ink1`, `ink2`, `ink3`, `ink4`, `action`, `report`, `warn`, `ok`, `hair`, `cardBorder` (tous `Color`)
  - `EnvironmentValues.one2OneTheme: One2OneTheme` (défaut `.paper`)
  - `View.one2OneTheme(_ theme: One2OneTheme) -> some View`

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/One2OneThemeTests.swift` :

```swift
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
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

```bash
swift test --filter One2OneThemeTests
```
Attendu : ÉCHEC de compilation — `cannot find 'One2OneTheme' in scope`.

- [ ] **Étape 3 : écrire `One2OneTheme.swift`**

```swift
import SwiftUI

/// Couleurs résolues d'un thème d'écran de la refonte.
///
/// Une vue refondue lit `\.one2OneTheme` et n'utilise que ces champs : elle
/// devient ainsi indifférente à la palette dans laquelle elle est affichée. Les
/// vues qui n'ont qu'une seule palette possible peuvent continuer à lire
/// `One2OneToken` directement.
struct One2OneColors: Sendable {
    /// Fond général de l'écran.
    let base: Color
    /// Fond de la zone de travail ou de la colonne de transcription.
    let canvas: Color
    /// Carte au repos.
    let card: Color
    /// Carte active : segment survolé ou sélectionné.
    let cardActive: Color
    /// Pilule et champ de saisie.
    let pill: Color
    let ink1: Color
    let ink2: Color
    let ink3: Color
    /// Libellé mono. Jamais remplacé par une encre plus claire : sous 12 px il
    /// faut 4,5:1 (spec §1.2).
    let ink4: Color
    let action: Color
    let report: Color
    let warn: Color
    let ok: Color
    let hair: Color
    let cardBorder: Color
}

/// Thème d'écran de la refonte.
///
/// `.session` n'est **pas** le mode sombre du système : les `WindowGroup` de
/// `OneToOneApp` épinglent `.preferredColorScheme(.light)` et ce lot n'y touche
/// pas. C'est un thème local, choisi par l'écran qui s'affiche — le mode séance
/// plein écran de la capture 1b.
enum One2OneTheme: String, CaseIterable, Sendable {
    case paper
    case session

    var colors: One2OneColors {
        switch self {
        case .paper:
            One2OneColors(
                base: One2OneToken.bgApp,
                canvas: One2OneToken.bgCanvas,
                card: One2OneToken.surface,
                cardActive: One2OneToken.actionBg,
                pill: One2OneToken.surface,
                ink1: One2OneToken.ink1,
                ink2: One2OneToken.ink2,
                ink3: One2OneToken.ink3,
                ink4: One2OneToken.ink4,
                action: One2OneToken.action,
                report: One2OneToken.report,
                warn: One2OneToken.warn,
                ok: One2OneToken.ok,
                hair: One2OneToken.hair,
                cardBorder: One2OneToken.cardBorder
            )
        case .session:
            One2OneColors(
                base: One2OneToken.darkBase,
                canvas: One2OneToken.darkTranscript,
                card: One2OneToken.darkCard,
                cardActive: One2OneToken.darkCardActive,
                pill: One2OneToken.darkPill,
                ink1: One2OneToken.darkInk1,
                ink2: One2OneToken.darkInk2,
                ink3: One2OneToken.darkInk3,
                ink4: One2OneToken.darkInk4,
                action: One2OneToken.darkAction,
                report: One2OneToken.darkReport,
                warn: One2OneToken.darkWarn,
                // La palette dark/* de la spec §1.2 ne publie pas d'encre
                // « tenu » : le vert clair de la palette claire n'est pas
                // lisible sur `#1c1a17`, et l'action bleu clair sert déjà de
                // teinte positive dans la capture 1b.
                ok: One2OneToken.darkAction,
                hair: Color.white.opacity(0.07),
                cardBorder: Color.white.opacity(0.09)
            )
        }
    }
}

private struct One2OneThemeKey: EnvironmentKey {
    static let defaultValue: One2OneTheme = .paper
}

extension EnvironmentValues {
    /// Thème de la refonte pour la sous-arborescence. `.paper` par défaut : un
    /// écran qui ne dit rien est un écran clair.
    var one2OneTheme: One2OneTheme {
        get { self[One2OneThemeKey.self] }
        set { self[One2OneThemeKey.self] = newValue }
    }
}

extension View {
    /// Applique un thème de la refonte à la sous-arborescence.
    func one2OneTheme(_ theme: One2OneTheme) -> some View {
        environment(\.one2OneTheme, theme)
    }
}
```

Note : `hair` et `cardBorder` de `.session` sont des opacités de blanc, pas des
hexadécimaux — ils restent nommés dans un fichier du système de conception, ce qui
respecte la règle « seul le système de conception nomme une couleur ».

- [ ] **Étape 4 : lancer le test pour vérifier qu'il passe**

```bash
swift test --filter One2OneThemeTests
```
Attendu : SUCCÈS.

- [ ] **Étape 5 : `swift build` puis commit**

```bash
swift build
git add OneToOne/Views/DesignSystem/One2OneTheme.swift Tests/One2OneThemeTests.swift
git commit -m "$(cat <<'EOF'
feat(refonte): thème d'écran papier/séance par environnement

One2OneTheme expose les couleurs résolues des deux palettes via
\.one2OneTheme, sans toucher au .preferredColorScheme(.light) épinglé sur
les trois WindowGroup : le mode séance est un thème local, pas le mode
sombre système.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 4 : primitives de texte et de pilules

**Fichiers :**
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/SectionLabel.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/MonoMeta.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/TimecodeLabel.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/Chip.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/Pill.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/InvitePill.swift`
- Test : `Tests/One2OnePrimitivesTests.swift` (créé ici, complété à la tâche 5)

**Interfaces :**
- Consomme : `One2OneToken.*`, `Font.plexSans/plexMono`, `View.sectionLabel()`, `EnvironmentValues.one2OneTheme`.
- Produit :
  - `struct SectionLabel: View` — `init(_ texte: String)`
  - `struct MonoMeta: View` — `init(_ texte: String, emphase: Bool = false)`
  - `struct TimecodeLabel: View` — `init(seconds: Double)`, `static func format(_ seconds: Double) -> String`, `static let width: CGFloat`
  - `struct Chip: View` — `init(_ texte: String, ton: ChipTon = .neutre)` ; `enum ChipTon { case neutre, action, report, ok, warn, oneOnOne, workshop }` avec `var encre: Color` et `var fond: Color`
  - `struct Pill: View` — `init(_ texte: String, ton: ChipTon = .neutre, bordee: Bool = false)`
  - `struct InvitePill: View` — `init(_ texte: String, etat: InvitePill.Etat = .invite, action: (() -> Void)? = nil)` ; `enum Etat { case invite, renseignee, neutre }` avec `var encre: Color` et `var fond: Color`

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/One2OnePrimitivesTests.swift` :

```swift
import Testing
import SwiftUI
@testable import OneToOne

/// Les primitives de la refonte portent chacune une règle de la spec §1.2 :
/// « timecode toujours mm:ss, largeur fixe », « ＋ assigner en accent/action,
/// renseignée en accent/ok », « pile d'avatars 19 px, chevauchement −6, max 6
/// puis +n ».
///
/// Une vue SwiftUI ne se teste pas sans session graphique. Ce fichier teste donc
/// la **règle**, extraite en fonction pure à côté de la vue qui l'applique — ce
/// qui est de toute façon la bonne façon de l'écrire.
@Suite("Primitives de la refonte — leurs règles pures")
struct One2OnePrimitivesTests {

    // MARK: - Timecode

    @Test("Un timecode est toujours mm:ss, sur deux chiffres chacun")
    func timecodeIsAlwaysMinutesSeconds() {
        #expect(TimecodeLabel.format(0) == "00:00")
        #expect(TimecodeLabel.format(9) == "00:09")
        #expect(TimecodeLabel.format(252) == "04:12")
        #expect(TimecodeLabel.format(1404) == "23:24")
    }

    @Test("Au-delà d'une heure, les minutes débordent — jamais de hh:mm:ss")
    func timecodeOverflowsIntoMinutes() {
        // La spec §1.2 dit « toujours mm:ss » : une réunion de 1 h 02 s'écrit
        // 62:xx. Basculer en hh:mm:ss changerait la largeur de la colonne.
        #expect(TimecodeLabel.format(3723) == "62:03")
    }

    @Test("Un timecode négatif ou non fini se lit 00:00 plutôt que de produire un absurde")
    func timecodeClampsDegenerateValues() {
        #expect(TimecodeLabel.format(-1) == "00:00")
        #expect(TimecodeLabel.format(.nan) == "00:00")
        #expect(TimecodeLabel.format(.infinity) == "00:00")
    }

    @Test("Les secondes fractionnaires sont tronquées, pas arrondies")
    func timecodeTruncates() {
        // 04:12,9 est encore 04:12 : arrondir ferait apparaître un timecode que
        // la tête de lecture n'a pas encore atteint.
        #expect(TimecodeLabel.format(252.9) == "04:12")
    }

    // MARK: - Pilule d'invite

    @Test("Une pilule d'invite non renseignée s'affiche en accent/action")
    func invitePillInvitesInAction() {
        #expect(InvitePill.Etat.invite.encre == One2OneToken.actionInk)
        #expect(InvitePill.Etat.invite.fond == One2OneToken.actionBg)
    }

    @Test("Une pilule d'invite renseignée passe en accent/ok")
    func invitePillFilledIsOk() {
        #expect(InvitePill.Etat.renseignee.encre == One2OneToken.okDeep)
        #expect(InvitePill.Etat.renseignee.fond == One2OneToken.okBg)
    }

    @Test("Une pilule d'invite neutre ne réclame rien : encre ink/3 sur surface/alt")
    func invitePillNeutralIsQuiet() {
        #expect(InvitePill.Etat.neutre.encre == One2OneToken.ink3)
        #expect(InvitePill.Etat.neutre.fond == One2OneToken.surfaceAlt)
    }

    @Test("Chaque état de pilule d'invite reste lisible : 4,5:1 sur son propre fond",
          arguments: [InvitePill.Etat.invite, .renseignee, .neutre])
    func invitePillStatesAreReadable(etat: InvitePill.Etat) throws {
        // Les pilules font 10–10,5 px (spec §1.2) : elles tombent donc sous le
        // seuil de 12 px et doivent atteindre 4,5:1.
        let ratio = try #require(ContrastRatio.ratio(etat.encre, etat.fond))
        #expect(ratio >= 4.5, "\(etat) : \(String(format: "%.2f", ratio)):1")
    }

    @Test("Chaque ton de chip reste lisible : 4,5:1 sur son propre fond",
          arguments: ChipTon.allCases)
    func chipTonesAreReadable(ton: ChipTon) throws {
        let ratio = try #require(ContrastRatio.ratio(ton.encre, ton.fond))
        #expect(ratio >= 4.5, "\(ton) : \(String(format: "%.2f", ratio)):1")
    }
}
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

```bash
swift test --filter One2OnePrimitivesTests
```
Attendu : ÉCHEC de compilation — `cannot find 'TimecodeLabel' in scope`.

- [ ] **Étape 3 : écrire les six primitives**

`SectionLabel.swift` :

```swift
import SwiftUI

/// Libellé de section : « MES NOTES », « À ASSIGNER — 9 », « CAPTURÉ CETTE
/// SÉANCE ». Plex Mono 600 à 9,5 px, majuscules, interlettrage 0,07 em
/// (spec §1.2).
///
/// La couleur suit le thème : `ink/4` sur papier, `dark/ink4` en séance. Jamais
/// `ink/muted` — sous 12 px il faut 4,5:1.
struct SectionLabel: View {
    let texte: String
    @Environment(\.one2OneTheme) private var theme

    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.plexMono(9.5, .semibold))
            .tracking(9.5 * 0.07)
            .textCase(.uppercase)
            .foregroundStyle(theme.colors.ink4)
    }
}

#Preview("SectionLabel — papier") {
    VStack(alignment: .leading, spacing: 12) {
        SectionLabel("mes notes")
        SectionLabel("à assigner — 9")
        SectionLabel("capturé cette séance")
    }
    .padding(20)
    .background(One2OneToken.surface)
}

#Preview("SectionLabel — séance") {
    VStack(alignment: .leading, spacing: 12) {
        SectionLabel("temps")
        SectionLabel("transcription live")
    }
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
```

`MonoMeta.swift` :

```swift
import SwiftUI

/// Métadonnée monospace : « Cohere MLX », « auto · 2 min », « Ajouté par ·
/// 09:41 · 1,2 Mo ». Plex Mono 10 px, encre `ink/4` — ou `ink/3` quand la
/// métadonnée porte une valeur qu'on lit vraiment (`emphase`).
struct MonoMeta: View {
    let texte: String
    let emphase: Bool
    @Environment(\.one2OneTheme) private var theme

    init(_ texte: String, emphase: Bool = false) {
        self.texte = texte
        self.emphase = emphase
    }

    var body: some View {
        Text(texte)
            .font(.plexMono(10, .medium))
            .foregroundStyle(emphase ? theme.colors.ink3 : theme.colors.ink4)
    }
}

#Preview("MonoMeta") {
    VStack(alignment: .leading, spacing: 8) {
        MonoMeta("Cohere MLX")
        MonoMeta("auto · 2 min")
        MonoMeta("4 sept. 2026 · 9:15", emphase: true)
    }
    .padding(20)
    .background(One2OneToken.surface)
}
```

`TimecodeLabel.swift` :

```swift
import SwiftUI

/// Timecode d'un élément horodaté : `mm:ss`, Plex Mono 500 à 10 px, **largeur
/// fixe** (spec §1.2).
///
/// La largeur est figée et non calculée : une colonne de timecodes dont la
/// largeur varie d'une ligne à l'autre décale tout le texte à sa droite, et
/// c'est justement ce que la conception évite en imposant `mm:ss` même au-delà
/// d'une heure.
struct TimecodeLabel: View {

    /// Largeur réservée : cinq caractères de Plex Mono à 10 px, arrondie au
    /// demi-point supérieur.
    static let width: CGFloat = 34

    let seconds: Double
    /// Teinte de l'accent quand le timecode est celui d'une décision ou d'un
    /// élément mis en avant. `nil` = encre de libellé mono du thème.
    let teinte: Color?
    @Environment(\.one2OneTheme) private var theme

    init(seconds: Double, teinte: Color? = nil) {
        self.seconds = seconds
        self.teinte = teinte
    }

    /// `mm:ss` depuis un nombre de secondes. Les minutes débordent au-delà de
    /// 59 (« toujours mm:ss ») ; les valeurs négatives ou non finies se lisent
    /// `00:00` ; les fractions sont tronquées, jamais arrondies — un timecode
    /// arrondi vers le haut désigne un instant que la tête de lecture n'a pas
    /// encore atteint.
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        Text(Self.format(seconds))
            .font(.plexMono(10, .medium))
            .foregroundStyle(teinte ?? theme.colors.ink4)
            .frame(width: Self.width, alignment: .leading)
            .monospacedDigit()
    }
}

#Preview("TimecodeLabel") {
    VStack(alignment: .leading, spacing: 6) {
        TimecodeLabel(seconds: 0)
        TimecodeLabel(seconds: 252, teinte: One2OneToken.action)
        TimecodeLabel(seconds: 663, teinte: One2OneToken.report)
        TimecodeLabel(seconds: 3723)
    }
    .padding(20)
    .background(One2OneToken.surface)
}
```

`Chip.swift` :

```swift
import SwiftUI

/// Ton d'une chip ou d'une pilule : le couple encre/fond que la spec §1.2
/// associe à chaque accent. Chaque couple atteint 4,5:1 (les chips font
/// 10–10,5 px), ce qu'un test vérifie.
enum ChipTon: CaseIterable, Sendable {
    case neutre
    case action
    case report
    case ok
    case warn
    case oneOnOne
    case workshop

    var encre: Color {
        switch self {
        case .neutre: One2OneToken.ink3
        case .action: One2OneToken.actionInk
        case .report: One2OneToken.reportInk
        case .ok: One2OneToken.okDeep
        case .warn: One2OneToken.warnInk
        case .oneOnOne: One2OneToken.oneOnOneInk
        case .workshop: One2OneToken.workshop
        }
    }

    var fond: Color {
        switch self {
        case .neutre: One2OneToken.surfaceAlt
        case .action: One2OneToken.actionBg
        case .report: One2OneToken.reportBg
        case .ok: One2OneToken.okBg
        case .warn: One2OneToken.warnBg
        case .oneOnOne: One2OneToken.oneOnOneBg
        case .workshop: One2OneToken.workshopBg
        }
    }
}

/// Chip : étiquette courte à angles peu arrondis (rayon 5–6, spec §1.2). Sert
/// aux thèmes, aux familles de sujets récurrents, aux commandes `/action`
/// affichées en permanence.
struct Chip: View {
    let texte: String
    let ton: ChipTon

    init(_ texte: String, ton: ChipTon = .neutre) {
        self.texte = texte
        self.ton = ton
    }

    var body: some View {
        Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(ton.encre)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ton.fond)
            )
    }
}

#Preview("Chip") {
    HStack(spacing: 6) {
        Chip("migration")
        Chip("/action", ton: .action)
        Chip("décision", ton: .report)
        Chip("tenu", ton: .ok)
        Chip("à surveiller", ton: .warn)
        Chip("1:1", ton: .oneOnOne)
        Chip("atelier", ton: .workshop)
    }
    .padding(20)
    .background(One2OneToken.surface)
}
```

`Pill.swift` :

```swift
import SwiftUI

/// Pilule : étiquette courte à bords ronds (rayon 11, padding 2–3 × 7–8,
/// Plex Sans 500 à 10–10,5 px — spec §1.2). Sert aux états (`● Privé — vous
/// deux`, `● Capture · Teams 4`), aux badges de type et aux compteurs.
///
/// `bordee` ajoute le contour que les captures montrent sur les pilules d'état
/// actif (`● Partage actif`) plutôt qu'un fond plein.
struct Pill: View {
    let texte: String
    let ton: ChipTon
    let bordee: Bool

    init(_ texte: String, ton: ChipTon = .neutre, bordee: Bool = false) {
        self.texte = texte
        self.ton = ton
        self.bordee = bordee
    }

    var body: some View {
        Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(ton.encre)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous).fill(ton.fond)
            )
            .overlay {
                if bordee {
                    Capsule(style: .continuous).strokeBorder(ton.encre.opacity(0.35), lineWidth: 1)
                }
            }
    }
}

#Preview("Pill") {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
            Pill("Global")
            Pill("Projet", ton: .action)
            Pill("Rapport ✓", ton: .report)
        }
        HStack(spacing: 6) {
            Pill("● Privé — vous deux", ton: .oneOnOne, bordee: true)
            Pill("● Capture · Teams 4", ton: .ok, bordee: true)
            Pill("Source perdue", ton: .warn, bordee: true)
        }
    }
    .padding(20)
    .background(One2OneToken.bgApp)
}
```

`InvitePill.swift` :

```swift
import SwiftUI

/// Pilule d'invite : `＋ assigner`, `＋ échéance`, `＋ Ajouter un risque`.
///
/// C'est la primitive qui porte la règle « aucune zone vide sans invite »
/// (spec, chantier 1, critère 1). Tant que le champ n'est pas renseigné, elle
/// réclame en `accent/action` ; renseignée, elle passe en `accent/ok` — ou
/// reste neutre quand la valeur affichée n'est pas un engagement (une durée,
/// une charge).
struct InvitePill: View {

    enum Etat: CaseIterable, Sendable {
        /// Rien n'est renseigné : la pilule invite.
        case invite
        /// La valeur est là et elle engage quelqu'un.
        case renseignee
        /// La valeur est là et elle n'engage personne.
        case neutre

        var encre: Color {
            switch self {
            case .invite: One2OneToken.actionInk
            case .renseignee: One2OneToken.okDeep
            case .neutre: One2OneToken.ink3
            }
        }

        var fond: Color {
            switch self {
            case .invite: One2OneToken.actionBg
            case .renseignee: One2OneToken.okBg
            case .neutre: One2OneToken.surfaceAlt
            }
        }
    }

    let texte: String
    let etat: Etat
    let action: (() -> Void)?

    init(_ texte: String, etat: Etat = .invite, action: (() -> Void)? = nil) {
        self.texte = texte
        self.etat = etat
        self.action = action
    }

    var body: some View {
        let etiquette = Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(etat.encre)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(etat.fond))

        if let action {
            Button(action: action) { etiquette }
                .buttonStyle(.plain)
                .accessibilityLabel(texte)
        } else {
            etiquette
        }
    }
}

#Preview("InvitePill") {
    HStack(spacing: 6) {
        InvitePill("＋ assigner")
        InvitePill("＋ échéance")
        InvitePill("Yann", etat: .renseignee)
        InvitePill("11 sept.", etat: .renseignee)
        InvitePill("2h", etat: .neutre)
    }
    .padding(20)
    .background(One2OneToken.surface)
}
```

- [ ] **Étape 4 : lancer le test pour vérifier qu'il passe**

```bash
swift test --filter One2OnePrimitivesTests
```
Attendu : SUCCÈS.

Si un ton de chip échoue le seuil de 4,5:1 : ne pas retoucher le jeton (§1.2 fait foi),
mais changer l'encre du ton pour l'encre `…Ink` correspondante de la table, et si le
couple de la table lui-même échoue, consigner la mesure dans `STATUS.md` et laisser le
test rouge documenté — non : **corriger le ton pour un couple conforme**, jamais laisser
un test rouge.

- [ ] **Étape 5 : `swift build` puis commit**

```bash
swift build
git add OneToOne/Views/DesignSystem/Components/Refonte Tests/One2OnePrimitivesTests.swift
git commit -m "$(cat <<'EOF'
feat(refonte): primitives de texte et de pilules

SectionLabel, MonoMeta, TimecodeLabel (mm:ss largeur fixe), Chip, Pill et
InvitePill (＋ assigner en accent/action, renseignée en accent/ok), avec
un #Preview chacune. Aucune vue existante ne les utilise encore.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 5 : primitives de mise en page

**Fichiers :**
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/RefonteCard.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/AvatarStack.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/ProgressBar.swift`
- Créer : `OneToOne/Views/DesignSystem/Components/Refonte/SegmentedMode.swift`
- Modifier : `Tests/One2OnePrimitivesTests.swift` (ajout d'une extension de suite)

**Interfaces :**
- Consomme : `One2OneToken.*`, `EnvironmentValues.one2OneTheme`, `Avatar.initiales(de:)` (existant, `OneToOne/Views/DesignSystem/Components/Avatar.swift`).
- Produit :
  - `struct RefonteCard<Content: View>: View` — `init(padding: CGFloat = One2OneToken.cardPaddingMax, @ViewBuilder content: () -> Content)`
  - `struct AvatarStack: View` — `init(noms: [String], maxVisibles: Int = 6)`, `static func layout(noms: [String], maxVisibles: Int) -> (visibles: [String], surplus: Int)`, `static let diametre: CGFloat`, `static let chevauchement: CGFloat`
  - `struct ProgressBar: View` — `init(valeur: Double, teinte: Color = One2OneToken.ok)`, `static func clamp(_ valeur: Double) -> Double`
  - `struct SegmentedMode<Valeur: Hashable>: View` — `init(selection: Binding<Valeur>, options: [Valeur], libelle: @escaping (Valeur) -> String)`

- [ ] **Étape 1 : écrire les tests qui échouent**

Ajouter à la fin de `Tests/One2OnePrimitivesTests.swift`, **dans** la suite existante
`One2OnePrimitivesTests` (juste avant son accolade fermante) :

```swift
    // MARK: - Pile d'avatars

    @Test("Jusqu'à six participants, la pile les montre tous et n'affiche pas de surplus")
    func avatarStackShowsUpToSix() {
        let noms = ["Patrice Y", "Nicolas L", "Claire-Amélie P", "Laurent S", "Camille A", "Loïc D"]
        let mise = AvatarStack.layout(noms: noms, maxVisibles: 6)
        #expect(mise.visibles.count == 6)
        #expect(mise.surplus == 0)
    }

    @Test("Au-delà de six, la pile en montre six et compte le reste")
    func avatarStackOverflows() {
        let noms = (1...9).map { "Participant \($0)" }
        let mise = AvatarStack.layout(noms: noms, maxVisibles: 6)
        #expect(mise.visibles.count == 6)
        #expect(mise.surplus == 3)
        #expect(mise.visibles.first == "Participant 1")
        #expect(mise.visibles.last == "Participant 6")
    }

    @Test("Une pile vide n'affiche ni avatar ni « +0 »")
    func avatarStackEmpty() {
        let mise = AvatarStack.layout(noms: [], maxVisibles: 6)
        #expect(mise.visibles.isEmpty)
        #expect(mise.surplus == 0)
    }

    @Test("La géométrie de la pile est celle de la conception : 19 px, chevauchement −6")
    func avatarStackGeometry() {
        #expect(AvatarStack.diametre == 19)
        #expect(AvatarStack.chevauchement == -6)
    }

    // MARK: - Barre de progression

    @Test("Une progression est bornée à 0…1")
    func progressBarClamps() {
        #expect(ProgressBar.clamp(0.5) == 0.5)
        #expect(ProgressBar.clamp(-3) == 0)
        #expect(ProgressBar.clamp(1.4) == 1)
    }

    @Test("Une progression indéfinie vaut zéro plutôt qu'une barre de largeur absurde")
    func progressBarHandlesNaN() {
        // 3 actions closes sur 0 action produit `nan` : la barre doit rester
        // vide, pas disparaître ni occuper toute la carte.
        #expect(ProgressBar.clamp(.nan) == 0)
        #expect(ProgressBar.clamp(.infinity) == 1)
    }
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

```bash
swift test --filter One2OnePrimitivesTests
```
Attendu : ÉCHEC de compilation — `cannot find 'AvatarStack' in scope`.

- [ ] **Étape 3 : écrire les quatre primitives**

`RefonteCard.swift` :

```swift
import SwiftUI

/// Carte de la refonte : rayon 7, contour `border/card`, padding 9–13
/// (spec §1.2). Suit le thème, donc utilisable telle quelle en mode séance.
///
/// Nommée `RefonteCard` et non `Card` : l'application porte déjà plusieurs
/// notions de carte (cartes de dashboard, `FicheTokens`), et ce lot ne les
/// remplace pas.
struct RefonteCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.one2OneTheme) private var theme

    init(padding: CGFloat = One2OneToken.cardPaddingMax, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(theme.colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(theme.colors.cardBorder, lineWidth: 1)
            )
    }
}

#Preview("RefonteCard — papier") {
    VStack(spacing: One2OneToken.cardGap) {
        RefonteCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("présence")
                Text("100 %").font(.plexSans(22, .semibold)).foregroundStyle(One2OneToken.ink1)
            }
        }
        RefonteCard(padding: One2OneToken.cardPaddingMin) {
            Text("Padding minimal, 9 px").font(.plexSans(12))
        }
    }
    .padding(20)
    .background(One2OneToken.bgCanvas)
}

#Preview("RefonteCard — séance") {
    RefonteCard {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("capturé cette séance")
            Text("4 actions").font(.plexSans(12)).foregroundStyle(One2OneToken.darkInk2)
        }
    }
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
```

`AvatarStack.swift` :

```swift
import SwiftUI

/// Pile d'avatars de la refonte : pastilles de 19 px, chevauchement de −6 px,
/// six au maximum puis un `+n` (spec §1.2 et capture 1a).
///
/// Distincte de `MeetingAvatarStack`, qui sert les écrans non refondus avec sa
/// propre géométrie : ce lot ne remplace pas l'existant.
struct AvatarStack: View {

    static let diametre: CGFloat = 19
    /// Décalage horizontal appliqué à chaque pastille après la première.
    /// Négatif : les pastilles se chevauchent.
    static let chevauchement: CGFloat = -6

    let noms: [String]
    let maxVisibles: Int
    @Environment(\.one2OneTheme) private var theme

    init(noms: [String], maxVisibles: Int = 6) {
        self.noms = noms
        self.maxVisibles = maxVisibles
    }

    /// Répartition entre pastilles affichées et surplus compté.
    ///
    /// Fonction pure, testée : c'est elle qui porte la règle « max 6 puis +n »,
    /// et une pile de 6 exactement ne doit **pas** afficher « +0 ».
    static func layout(noms: [String], maxVisibles: Int) -> (visibles: [String], surplus: Int) {
        guard maxVisibles > 0 else { return ([], noms.count) }
        guard noms.count > maxVisibles else { return (noms, 0) }
        return (Array(noms.prefix(maxVisibles)), noms.count - maxVisibles)
    }

    var body: some View {
        let mise = Self.layout(noms: noms, maxVisibles: maxVisibles)
        HStack(spacing: Self.chevauchement) {
            ForEach(Array(mise.visibles.enumerated()), id: \.offset) { _, nom in
                pastille(Avatar.initiales(de: nom), aide: nom)
            }
            if mise.surplus > 0 {
                pastille("+\(mise.surplus)", aide: "\(mise.surplus) participants de plus")
            }
        }
    }

    private func pastille(_ texte: String, aide: String) -> some View {
        Text(texte)
            .font(.plexSans(8.5, .semibold))
            .foregroundStyle(theme.colors.ink3)
            .frame(width: Self.diametre, height: Self.diametre)
            .background(Circle().fill(theme.colors.pill))
            .overlay(Circle().strokeBorder(theme.colors.card, lineWidth: 1.5))
            .help(aide)
    }
}

#Preview("AvatarStack") {
    VStack(alignment: .leading, spacing: 12) {
        AvatarStack(noms: ["Patrice Y", "Nicolas L", "Claire-Amélie P"])
        AvatarStack(noms: ["Patrice Y", "Nicolas L", "Claire-Amélie P", "Laurent S", "Camille A", "Loïc D"])
        AvatarStack(noms: (1...9).map { "Participant \($0)" })
    }
    .padding(20)
    .background(One2OneToken.surface)
}
```

`ProgressBar.swift` :

```swift
import SwiftUI

/// Barre de progression fine des cartes KPI (capture 1a, carte ACTIONS).
/// 4 px de haut, rayon plein, portion faite en `accent/ok` par défaut.
struct ProgressBar: View {
    let valeur: Double
    let teinte: Color
    @Environment(\.one2OneTheme) private var theme

    init(valeur: Double, teinte: Color = One2OneToken.ok) {
        self.valeur = valeur
        self.teinte = teinte
    }

    /// Borne une progression à 0…1.
    ///
    /// `nan` vaut 0 : « 3 actions closes sur 0 action » est un rapport
    /// indéfini, et une largeur `nan` fait disparaître la barre sans rien dire.
    static func clamp(_ valeur: Double) -> Double {
        guard !valeur.isNaN else { return 0 }
        return min(max(valeur, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.hair)
                Capsule()
                    .fill(teinte)
                    .frame(width: geo.size.width * Self.clamp(valeur))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Progression")
        .accessibilityValue("\(Int(Self.clamp(valeur) * 100)) %")
    }
}

#Preview("ProgressBar") {
    VStack(spacing: 14) {
        ProgressBar(valeur: 0)
        ProgressBar(valeur: 0.25)
        ProgressBar(valeur: 0.6, teinte: One2OneToken.warn)
        ProgressBar(valeur: 1)
    }
    .frame(width: 240)
    .padding(20)
    .background(One2OneToken.surface)
}
```

`SegmentedMode.swift` :

```swift
import SwiftUI

/// Sélecteur segmenté de la refonte : `Préparer / En séance / Relire`,
/// `Liste / Calendrier / Eisenhower`. Le segment actif est **plein `ink/1`**
/// avec un texte inversé (capture 1a), les autres sont transparents.
///
/// Générique sur la valeur : le sélecteur de mode temporel, celui des vues du
/// rail d'actions et ceux des lots suivants sont le même composant.
struct SegmentedMode<Valeur: Hashable>: View {
    @Binding var selection: Valeur
    let options: [Valeur]
    let libelle: (Valeur) -> String
    @Environment(\.one2OneTheme) private var theme

    init(selection: Binding<Valeur>, options: [Valeur], libelle: @escaping (Valeur) -> String) {
        self._selection = selection
        self.options = options
        self.libelle = libelle
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let actif = option == selection
                Button {
                    selection = option
                } label: {
                    Text(libelle(option))
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(actif ? theme.colors.card : theme.colors.ink3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                                .fill(actif ? theme.colors.ink1 : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
    }
}

#Preview("SegmentedMode") {
    struct Apercu: View {
        @State private var mode = "En séance"
        @State private var vue = "Liste"
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedMode(selection: $mode,
                              options: ["Préparer", "En séance", "Relire"],
                              libelle: { $0 })
                SegmentedMode(selection: $vue,
                              options: ["Liste", "Calendrier", "Eisenhower"],
                              libelle: { $0 })
            }
            .padding(20)
            .background(One2OneToken.bgApp)
        }
    }
    return Apercu()
}
```

- [ ] **Étape 4 : lancer le test pour vérifier qu'il passe**

```bash
swift test --filter One2OnePrimitivesTests
```
Attendu : SUCCÈS.

- [ ] **Étape 5 : `swift build` puis commit**

```bash
swift build
git add OneToOne/Views/DesignSystem/Components/Refonte Tests/One2OnePrimitivesTests.swift
git commit -m "$(cat <<'EOF'
feat(refonte): primitives de mise en page

RefonteCard (rayon 7, bordure border/card, padding 9-13), AvatarStack
(19 px, chevauchement -6, max 6 puis +n), ProgressBar et SegmentedMode
(segment actif ink/1 plein), avec un #Preview chacune.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 6 : `MeetingScreenModel` et sa persistance

**Fichiers :**
- Créer : `OneToOne/Views/Meeting/MeetingScreenModel.swift`
- Test : `Tests/MeetingScreenModelTests.swift`

**Interfaces :**
- Consomme : `ActionAudience` et `Collaborator` (modèles existants — **lus, pas modifiés**).
- Produit :
  - `@MainActor @Observable final class MeetingScreenModel`
  - `enum MeetingScreenModel.Space: String, CaseIterable { case meeting, report, resources }`
  - `enum MeetingScreenModel.Mode: String, CaseIterable { case prepare, live, review }`
  - `init(defaults: UserDefaults = .standard)`
  - `func attach(meetingID: UUID)` — idempotent, relit l'espace et le mode mémorisés
  - `var space: Space`, `var mode: Mode` (persistés à chaque écriture)
  - `var newTaskTitle: String`, `var selectedCollaborator: Collaborator?`, `var showNewTaskDueDate: Bool`, `var newTaskDueDate: Date?`, `var newTaskAudience: ActionAudience`, `var newTaskUrgent: Bool`, `var newTaskImportant: Bool`, `var newTaskPomodoros: Int`, `var didApplyActionDefaults: Bool`
  - `var showSpeakers: Bool` (défaut `true`), `var showPlayback: Bool`, `var follow: Bool` (défaut `true`)
  - `var newAdhocName: String`, `var suggestedTagNames: [String]`
  - `func resetActionDraft()`
  - `static func spaceKey(for meetingID: UUID) -> String`, `static func modeKey(for meetingID: UUID) -> String`

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/MeetingScreenModelTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// « Le mode est un état d'écran, pas une donnée. » — programme de refonte §3,
/// à propos de `Meeting.mode`.
///
/// Ce que l'écran de réunion sait de lui-même (quel espace, quel moment, quel
/// brouillon d'action en cours) vivait dans une cinquantaine de `@State` de
/// `MeetingView`, dont huit descendaient en `@Binding` sur deux niveaux. Cette
/// suite fixe le contrat du modèle unique qui les remplace — en particulier ce
/// qui se mémorise d'une ouverture à l'autre, et ce qui ne doit pas.
@Suite("MeetingScreenModel — l'état d'écran d'une réunion")
@MainActor
struct MeetingScreenModelTests {

    /// `UserDefaults` isolé par test : `.standard` polluerait le poste et
    /// rendrait l'ordre des tests significatif.
    private func makeDefaults(_ nom: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MeetingScreenModelTests.\(nom)")!
        defaults.removePersistentDomain(forName: "MeetingScreenModelTests.\(nom)")
        return defaults
    }

    @Test("À l'ouverture, une réunion jamais vue s'affiche sur l'espace Réunion, en séance")
    func defaultsAreMeetingAndLive() {
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        #expect(model.space == .meeting)
        #expect(model.mode == .live)
    }

    @Test("L'espace et le mode choisis sont retrouvés à la réouverture de la même réunion")
    func spaceAndModeArePersistedPerMeeting() {
        let defaults = makeDefaults()
        let id = UUID()

        let premier = MeetingScreenModel(defaults: defaults)
        premier.attach(meetingID: id)
        premier.space = .resources
        premier.mode = .review

        let second = MeetingScreenModel(defaults: defaults)
        second.attach(meetingID: id)
        #expect(second.space == .resources)
        #expect(second.mode == .review)
    }

    @Test("Deux réunions ne partagent pas leur espace ni leur mode")
    func memoryIsPerMeeting() {
        let defaults = makeDefaults()
        let premiere = UUID(), seconde = UUID()

        let a = MeetingScreenModel(defaults: defaults)
        a.attach(meetingID: premiere)
        a.space = .report
        a.mode = .prepare

        let b = MeetingScreenModel(defaults: defaults)
        b.attach(meetingID: seconde)
        #expect(b.space == .meeting)
        #expect(b.mode == .live)
    }

    @Test("Une valeur mémorisée illisible ne casse rien : on retombe sur le défaut")
    func corruptStoredValueFallsBack() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set("espace-inconnu", forKey: MeetingScreenModel.spaceKey(for: id))
        defaults.set(42, forKey: MeetingScreenModel.modeKey(for: id))

        let model = MeetingScreenModel(defaults: defaults)
        model.attach(meetingID: id)
        #expect(model.space == .meeting)
        #expect(model.mode == .live)
    }

    @Test("`attach` est idempotent et ne réécrit pas ce qui vient d'être choisi")
    func attachIsIdempotent() {
        let defaults = makeDefaults()
        let id = UUID()
        let model = MeetingScreenModel(defaults: defaults)
        model.attach(meetingID: id)
        model.mode = .review
        model.attach(meetingID: id)
        #expect(model.mode == .review)
    }

    /// Critère du lot 1 (« changement de mode sans perte de saisie ») : le
    /// brouillon ne dépend pas du mode, donc changer de mode ne peut pas le
    /// vider. Le test le fige dès maintenant, avant que la vue existe.
    @Test("Changer d'espace ou de mode ne touche pas au brouillon d'action en cours")
    func changingModeKeepsTheDraft() {
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        model.newTaskTitle = "Chiffrer la fin de migration Marine"
        model.newTaskUrgent = true
        model.newTaskPomodoros = 2

        model.mode = .review
        model.space = .report

        #expect(model.newTaskTitle == "Chiffrer la fin de migration Marine")
        #expect(model.newTaskUrgent)
        #expect(model.newTaskPomodoros == 2)
    }

    @Test("Le brouillon d'action n'est pas mémorisé d'une ouverture à l'autre")
    func draftIsNotPersisted() {
        let defaults = makeDefaults()
        let id = UUID()
        let premier = MeetingScreenModel(defaults: defaults)
        premier.attach(meetingID: id)
        premier.newTaskTitle = "Ne doit pas survivre"

        let second = MeetingScreenModel(defaults: defaults)
        second.attach(meetingID: id)
        #expect(second.newTaskTitle.isEmpty)
    }

    @Test("`resetActionDraft` remet le brouillon à zéro mais garde le destinataire choisi")
    func resetKeepsAudience() {
        // Après création d'une action, le composeur du rail doit rester prêt à
        // en saisir une autre pour la même personne : vider le destinataire
        // obligerait à le re-choisir à chaque ligne.
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        model.newTaskTitle = "Vérifier l'état des comptes GitLab"
        model.newTaskDueDate = Date()
        model.showNewTaskDueDate = true
        model.newTaskUrgent = true
        model.newTaskImportant = true
        model.newTaskPomodoros = 4
        model.newTaskAudience = .collaborateur

        model.resetActionDraft()

        #expect(model.newTaskTitle.isEmpty)
        #expect(model.newTaskDueDate == nil)
        #expect(model.showNewTaskDueDate == false)
        #expect(model.newTaskUrgent == false)
        #expect(model.newTaskImportant == false)
        #expect(model.newTaskPomodoros == 0)
        #expect(model.newTaskAudience == .collaborateur)
    }

    @Test("Les bascules d'affichage ont les défauts de l'écran actuel")
    func displayTogglesKeepCurrentDefaults() {
        // Aucun changement visuel dans ce lot : les défauts sont exactement
        // ceux des `@State` retirés de `MeetingView`.
        let model = MeetingScreenModel(defaults: makeDefaults())
        #expect(model.showSpeakers)
        #expect(model.showPlayback == false)
        #expect(model.follow)
    }

    @Test("Les clés de mémorisation portent l'identifiant de la réunion")
    func keysCarryTheMeetingID() {
        let id = UUID()
        #expect(MeetingScreenModel.spaceKey(for: id).contains(id.uuidString))
        #expect(MeetingScreenModel.modeKey(for: id).contains(id.uuidString))
        #expect(MeetingScreenModel.spaceKey(for: id) != MeetingScreenModel.modeKey(for: id))
    }
}
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

```bash
swift test --filter MeetingScreenModelTests
```
Attendu : ÉCHEC de compilation — `cannot find 'MeetingScreenModel' in scope`.

- [ ] **Étape 3 : écrire `MeetingScreenModel.swift`**

```swift
import Foundation
import Observation

/// Tout ce que l'écran de réunion sait de lui-même : quel espace est affiché,
/// à quel moment de la réunion on se trouve, et le brouillon d'action en cours
/// de saisie.
///
/// Remplace les `@State` de `MeetingView` qui descendaient en `@Binding` sur
/// deux niveaux (`MeetingView` → `OverviewDashboard` → `ActionsPanel`) : le
/// programme de refonte interdit désormais tout `@Binding` traversant plus d'un
/// niveau, et cette classe est l'unique porteuse de cet état.
///
/// Ce qui est **mémorisé** d'une ouverture à l'autre : l'espace et le mode, par
/// réunion (`UserDefaults`). Le mode est un état d'écran, pas une donnée : il
/// n'a pas de colonne dans `Meeting`. Ce qui n'est **pas** mémorisé : le
/// brouillon d'action et les bascules d'affichage, qui repartent des défauts à
/// chaque ouverture — exactement comme les `@State` qu'ils remplacent.
@MainActor
@Observable
final class MeetingScreenModel {

    /// Les trois espaces de la spec §1.1. Valeurs brutes stables : elles sont
    /// écrites dans `UserDefaults`, donc on ne les renomme pas sans migration.
    enum Space: String, CaseIterable, Sendable {
        case meeting
        case report
        case resources
    }

    /// Le sous-mode temporel de la spec §1.1. Il ne change pas la navigation,
    /// il change la disposition par défaut et le focus clavier.
    enum Mode: String, CaseIterable, Sendable {
        case prepare
        case live
        case review
    }

    // MARK: - Espace et moment

    var space: Space = .meeting {
        didSet { persistSpace() }
    }

    var mode: Mode = .live {
        didSet { persistMode() }
    }

    // MARK: - Brouillon d'action

    var newTaskTitle = ""
    var selectedCollaborator: Collaborator?
    var showNewTaskDueDate = false
    var newTaskDueDate: Date?
    var newTaskAudience: ActionAudience = .moi
    var newTaskUrgent = false
    var newTaskImportant = false
    var newTaskPomodoros = 0
    /// Le défaut malin du destinataire n'est appliqué qu'une fois par écran
    /// (cf. `MeetingView.applyActionDraftDefaultsIfNeeded`).
    var didApplyActionDefaults = false

    // MARK: - Bascules d'affichage

    /// Affiche les locuteurs dans la transcription.
    var showSpeakers = true
    /// La barre de lecture audio est dépliée.
    var showPlayback = false
    /// La transcription suit la tête de lecture. Consommé à partir du lot 2 ;
    /// porté ici parce que c'est un état d'écran et qu'il n'a pas d'autre
    /// domicile.
    var follow = true

    // MARK: - Saisies éphémères des surfaces filles

    /// Nom en cours de saisie dans la modale de gestion des participants.
    var newAdhocName = ""
    /// Thèmes proposés par l'IA, en attente d'acceptation. Éphémères, non
    /// persistés : régénérés à chaque rapport ou à la demande.
    var suggestedTagNames: [String] = []

    // MARK: - Mémorisation

    private let defaults: UserDefaults
    private var meetingID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let prefix = "onetoone.meetingScreen"

    static func spaceKey(for meetingID: UUID) -> String {
        "\(prefix).space.\(meetingID.uuidString)"
    }

    static func modeKey(for meetingID: UUID) -> String {
        "\(prefix).mode.\(meetingID.uuidString)"
    }

    /// Rattache le modèle à une réunion et relit l'espace et le mode mémorisés.
    ///
    /// Idempotent : appelé depuis `.onAppear`, qui peut se déclencher plusieurs
    /// fois pour un même écran. Un second appel pour la même réunion ne relit
    /// rien — sinon il écraserait le choix que l'utilisateur vient de faire.
    func attach(meetingID: UUID) {
        guard self.meetingID != meetingID else { return }
        self.meetingID = meetingID
        // Écriture directe des propriétés stockées via `withoutPersisting` :
        // passer par `space =` déclencherait `didSet`, donc réécrirait dans
        // `UserDefaults` la valeur qu'on vient d'en lire. Inoffensif mais
        // trompeur à la lecture.
        isRestoring = true
        space = Space(rawValue: defaults.string(forKey: Self.spaceKey(for: meetingID)) ?? "") ?? .meeting
        mode = Mode(rawValue: defaults.string(forKey: Self.modeKey(for: meetingID)) ?? "") ?? .live
        isRestoring = false
    }

    private var isRestoring = false

    private func persistSpace() {
        guard !isRestoring, let meetingID else { return }
        defaults.set(space.rawValue, forKey: Self.spaceKey(for: meetingID))
    }

    private func persistMode() {
        guard !isRestoring, let meetingID else { return }
        defaults.set(mode.rawValue, forKey: Self.modeKey(for: meetingID))
    }

    // MARK: - Brouillon

    /// Vide le brouillon après création d'une action, **sans** toucher au
    /// destinataire ni au collaborateur choisi : le composeur doit rester prêt
    /// à saisir la ligne suivante pour la même personne.
    func resetActionDraft() {
        newTaskTitle = ""
        newTaskDueDate = nil
        showNewTaskDueDate = false
        newTaskUrgent = false
        newTaskImportant = false
        newTaskPomodoros = 0
    }
}
```

Note sur `defaults.string(forKey:)` : la clé écrite en `Int` par le test
`corruptStoredValueFallbackFallsBack` fait rendre `nil` à `string(forKey:)` (aucune
conversion numérique implicite pour un `Int` stocké), d'où le repli sur `.live`.
Si `UserDefaults` rendait `"42"`, `Mode(rawValue:)` rendrait `nil` de toute façon.

- [ ] **Étape 4 : lancer le test pour vérifier qu'il passe**

```bash
swift test --filter MeetingScreenModelTests
```
Attendu : SUCCÈS, les 10 tests.

- [ ] **Étape 5 : `swift build` puis commit**

```bash
swift build
git add OneToOne/Views/Meeting/MeetingScreenModel.swift Tests/MeetingScreenModelTests.swift
git commit -m "$(cat <<'EOF'
feat(refonte): MeetingScreenModel, l'état d'écran d'une réunion

@Observable @MainActor : espace (meeting/report/resources), mode temporel
(prepare/live/review) mémorisés par réunion dans UserDefaults, brouillon
d'action et bascules d'affichage. Aucune vue ne l'utilise encore.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 7 : migrer `MeetingView` sur le modèle, sans changement visuel

**Fichiers :**
- Modifier : `OneToOne/Views/MeetingView.swift` (lignes ~88–96, 128, 141–142, 167, 230, 268, 361–374, 396–398, 730–739, 2197–2227, 2362)
- Modifier : `OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift` (lignes 12–18, 143–146)
- Modifier : `OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift` (lignes 36–43 et tous les usages)
- Modifier : `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (le `@Binding var suggestedTagNames`)
- Modifier : `OneToOne/Views/Meeting/ManageParticipantsSheet.swift` (le `@Binding var newAdhocName`)

**Interfaces :**
- Consomme : `MeetingScreenModel` (tâche 6).
- Produit : les quatre vues reçoivent `let screen: MeetingScreenModel` en paramètre au lieu de leurs `@Binding` traversants.

**Règle de la tâche : aucun changement visuel.** Aucun libellé, aucune couleur, aucune
disposition ne bouge. `activeSection` reste un `@State` de `MeetingView`. Les chemins
`adoptPendingLiveNotes()` / `discardEmptyNoteIfNeeded()` ne sont pas touchés.

- [ ] **Étape 1 : introduire le modèle dans `MeetingView` et retirer les `@State`**

Dans `OneToOne/Views/MeetingView.swift`, remplacer le bloc de `@State` du brouillon
d'action (lignes ~88–96) par la déclaration du modèle :

```swift
    // MARK: - État d'écran

    /// L'état d'écran de cette réunion : espace, moment, brouillon d'action,
    /// bascules d'affichage. Remplace une douzaine de `@State` dont huit
    /// descendaient en `@Binding` sur deux niveaux (cf. `MeetingScreenModel`).
    @State private var screen = MeetingScreenModel()
```

Puis retirer, dans le reste du bloc `Local state` :
`newTaskTitle`, `selectedCollaborator`, `showNewTaskDueDate`, `newTaskDueDate`,
`newTaskAudience`, `newTaskUrgent`, `newTaskImportant`, `newTaskPomodoros`,
`didSetActionDefaults`, `newAdhocName`, `showPlayback`, `showSpeakersView`,
`suggestedTagNames`.

Ne **pas** retirer `isSuggestingTags` (un drapeau d'activité, pas un état d'écran, et il
n'est pas dans le périmètre du modèle) ni `activeSection`.

- [ ] **Étape 2 : rattacher le modèle et réécrire les sites d'usage**

Dans le `.onAppear` de `MeetingView` (ligne ~396), rattacher avant tout le reste :

```swift
        .onAppear {
            screen.attach(meetingID: meeting.ensuredStableID)
            MeetingScreenRegistry.shared.screenAppeared(meeting.persistentModelID)
            applyActionDraftDefaultsIfNeeded()
```

Puis remplacer mécaniquement, dans ce fichier :

| Avant | Après |
| --- | --- |
| `newTaskTitle` | `screen.newTaskTitle` |
| `selectedCollaborator` | `screen.selectedCollaborator` |
| `showNewTaskDueDate` | `screen.showNewTaskDueDate` |
| `newTaskDueDate` | `screen.newTaskDueDate` |
| `newTaskAudience` | `screen.newTaskAudience` |
| `newTaskUrgent` | `screen.newTaskUrgent` |
| `newTaskImportant` | `screen.newTaskImportant` |
| `newTaskPomodoros` | `screen.newTaskPomodoros` |
| `didSetActionDefaults` | `screen.didApplyActionDefaults` |
| `newAdhocName` | `screen.newAdhocName` |
| `showPlayback` | `screen.showPlayback` |
| `showSpeakersView` | `screen.showSpeakers` |
| `suggestedTagNames` | `screen.suggestedTagNames` |

`addTask()` (ligne ~2195) devient :

```swift
    private func addTask() {
        let t = ActionTask(
            title: screen.newTaskTitle,
            dueDate: screen.showNewTaskDueDate ? (screen.newTaskDueDate ?? Date()) : nil
        )
        t.meeting = meeting
        t.project = meeting.project
        t.destinataire = screen.newTaskAudience
        t.collaborator = screen.newTaskAudience == .collaborateur ? screen.selectedCollaborator : nil
        t.isUrgent = screen.newTaskUrgent
        t.isImportant = screen.newTaskImportant
        t.pomodoros = screen.newTaskPomodoros
        context.insert(t)
        screen.resetActionDraft()
        saveContext()
    }
```

`applyActionDraftDefaultsIfNeeded()` (ligne ~2219) devient :

```swift
    private func applyActionDraftDefaultsIfNeeded() {
        guard !screen.didApplyActionDefaults else { return }
        screen.didApplyActionDefaults = true
        if meeting.kind == .oneToOne, let partner = meeting.participants.first {
            screen.newTaskAudience = .collaborateur
            screen.selectedCollaborator = partner
        } else {
            screen.newTaskAudience = .moi
        }
    }
```

Attention à deux endroits où un `Binding` est encore attendu par une vue non refondue :
`Toggle("Afficher speakers", isOn: $showSpeakersView)` (ligne ~2362) devient
`Toggle("Afficher speakers", isOn: Binding(get: { screen.showSpeakers }, set: { screen.showSpeakers = $0 }))`.
Idem pour tout `$…` restant sur une propriété déplacée. Le `Binding` construit à la main
est nécessaire parce que `@Observable` n'expose pas de projection `$`.

- [ ] **Étape 3 : basculer les quatre vues filles sur le modèle**

`OverviewDashboard.swift` — remplacer les huit `@Binding` (lignes 12–18) par :

```swift
    /// L'état d'écran de la réunion. Remplace huit `@Binding` qui traversaient
    /// cette vue sans qu'elle les lise, uniquement pour atteindre `ActionsPanel`.
    let screen: MeetingScreenModel
```

et le passage à `ActionsPanel` (lignes ~143–146) par `screen: screen`. Vérifier que
`OverviewDashboard` ne lisait bien **aucune** de ces valeurs pour son propre compte
(`grep -n "newTask\|selectedCollaborator" OverviewDashboard.swift` ne doit plus rien
rendre en dehors de la ligne de passage).

`ActionsPanel.swift` — remplacer les huit `@Binding` (lignes 36–43) par
`let screen: MeetingScreenModel`, puis préfixer chaque usage par `screen.`. Les deux
endroits qui exigent un `Binding` sont :
- `EditableTextField(placeholder: "Nouvelle action…", text: $newTaskTitle)` (ligne ~320)
  → `text: Binding(get: { screen.newTaskTitle }, set: { screen.newTaskTitle = $0 })`
- `iconToggle("Urgent", systemImage: "exclamationmark", isOn: $newTaskUrgent, color: .blue)`
  (lignes ~334–335) → `isOn: Binding(get: { screen.newTaskUrgent }, set: { screen.newTaskUrgent = $0 })`,
  idem pour `newTaskImportant`.

`MeetingTopChromeBar.swift` — remplacer `@Binding var suggestedTagNames: [String]` par
`let screen: MeetingScreenModel` et chaque usage de `suggestedTagNames` par
`screen.suggestedTagNames`. Ne pas toucher à `isSuggestingTags` ni à
`onRequestTagSuggestions`.

`ManageParticipantsSheet.swift` — remplacer `@Binding var newAdhocName: String` par
`let screen: MeetingScreenModel` et l'usage par
`Binding(get: { screen.newAdhocName }, set: { screen.newAdhocName = $0 })` là où un
`TextField` l'exige.

Mettre à jour les sites d'appel dans `MeetingView.swift` (lignes ~268, 361–374, 730–739)
pour passer `screen: screen`.

- [ ] **Étape 4 : vérifier qu'aucun `@Binding` déplacé ne subsiste**

```bash
grep -rn "@Binding var newTask\|@Binding var selectedCollaborator\|@Binding var showNewTaskDueDate\|@Binding var newAdhocName\|@Binding var suggestedTagNames" OneToOne/
```
Attendu : aucune sortie.

```bash
grep -cn "screen\." OneToOne/Views/MeetingView.swift
```
Attendu : au moins 25 occurrences.

- [ ] **Étape 5 : build et suite complète**

```bash
swift build
swift test
```
Attendu : build propre (mêmes avertissements préexistants) et suite **verte**, sans
changement du nombre de tests par rapport à `master` en dehors des suites ajoutées par
ce lot. Les suites à surveiller particulièrement : `NoteFactoryTests`,
`PendingEditorTextTests`, `MeetingScreenRegistryTests` (parade du risque « `MeetingView`
se casse », programme §8).

- [ ] **Étape 6 : recette visuelle**

```bash
Scripts/bump-and-build.sh dev
```
Ouvrir une réunion existante et vérifier, sans référence à la maquette (ce lot est
invisible) : les onglets sont inchangés, le composeur d'action du rail crée une action,
`Afficher speakers` bascule la transcription, la barre de lecture se déplie au clic sur
lecture, l'ajout d'un participant ad hoc fonctionne, les thèmes proposés s'affichent
après génération d'un rapport. Consigner dans `STATUS.md` ce qui a été vérifié à l'écran
et ce qui ne l'a pas été.

- [ ] **Étape 7 : commit**

```bash
git add OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift OneToOne/Views/Meeting/MeetingTopChromeBar.swift OneToOne/Views/Meeting/ManageParticipantsSheet.swift
git commit -m "$(cat <<'EOF'
refactor(refonte): sortir l'état d'écran de MeetingView

Treize @State de MeetingView passent dans MeetingScreenModel, injecté en
paramètre à OverviewDashboard, ActionsPanel, MeetingTopChromeBar et
ManageParticipantsSheet : les huit @Binding du brouillon d'action ne
traversent plus deux niveaux de vue. Aucun changement visuel ;
activeSection reste un @State jusqu'au lot 1.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Tâche 8 : `STATUS.md`, branche et PR

**Fichiers :**
- Modifier : `STATUS.md`

- [ ] **Étape 1 : suite complète et chiffres réels**

```bash
swift test 2>&1 | tail -40
```
Relever les nombres exacts (XCTest exécutés / ignorés / échoués, Swift Testing tests /
suites / échecs). La suite doit être **verte**. Si un test échoue, le corriger avant de
continuer — pas de PR sur du rouge.

- [ ] **Étape 2 : écrire la section `STATUS.md`**

Insérer une section **en tête** (juste après `Dernière mise à jour :`, dont la date passe
à `2026-09-07 CEST`), sur le modèle des sections existantes : état, fichiers créés et
modifiés avec ce que chacun porte, tests avec les chiffres réels, écarts assumés,
non-vérifié, prochaine action = lot 1.

Écarts à consigner explicitement :
- l'énumération des jetons s'appelle `One2OneToken` (et non `Token` comme dans
  Teams-Capture), pour lever toute ambiguïté dans un module unique de cette taille ;
- `newAdhocName` et `suggestedTagNames` ont rejoint le modèle en plus de la liste du
  programme : ce sont les seuls `@Binding` traversants de `ManageParticipantsSheet` et
  `MeetingTopChromeBar`, les deux vues que le lot devait justement libérer ;
- `showNewTaskDueDate` et `didApplyActionDefaults` ont rejoint le modèle avec le reste du
  brouillon d'action, dont ils sont indissociables ;
- `AvatarStack`, `RefonteCard` : noms retenus pour ne pas heurter `MeetingAvatarStack` ni
  les cartes de dashboard existantes ;
- `One2OneTheme.session.ok` retombe sur `dark/accent action` : la palette `dark/*` de la
  spec §1.2 ne publie pas d'encre « tenu » ;
- toute paire de contraste retirée de la liste des tests, avec sa mesure ;
- tout écart constaté aux étapes de repli des tâches 1, 2 et 4.

- [ ] **Étape 3 : commit, pousser, PR**

```bash
git add STATUS.md
git commit -m "$(cat <<'EOF'
docs(status): consigner le lot 0A de la refonte de l'écran de réunion

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push -u origin feat/refonte-lot-0a-socle-visuel
```

Puis ouvrir la PR (corps = critères du lot cochés + résultat de `swift test`) :

```bash
gh pr create --base master --title "feat(refonte): lot 0A — socle visuel et état d'écran" --body "$(cat <<'EOF'
Lot 0A du programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` (§5).
Plan d'exécution : `docs/superpowers/plans/2026-09-07-refonte-lot-0a-socle-visuel.md`.

## Critères du lot

- [x] `One2OneTokens.swift` : table §1.2 complète, palette `dark/*` du mode séance (dont `dark/accent report #e8b0aa`, `#191714`, `#232019`), largeurs fixes 330/320/356/190/52/78/430/396/400 — seul fichier qui nomme une couleur de la refonte
- [x] Typographie Plex copiée de Teams-Capture (noms PostScript abrégés, jamais `.weight()` par-dessus) + test des cinq noms
- [x] Fontes IBM Plex embarquées (Sans 400/500/600, Mono 500/600) + licence OFL, enregistrement `CTFontManagerRegisterFontsForURL` en portée `.process`, repli système conservé
- [x] Dix primitives avec un `#Preview` chacune, aucune vue existante ne les utilise encore
- [x] `One2OneTheme` en `EnvironmentValue` (`.paper` / `.session`), sans toucher au `.preferredColorScheme(.light)` épinglé
- [x] `MeetingScreenModel` (`@Observable`, `@MainActor`) + persistance du dernier espace/mode par réunion
- [x] `MeetingView` allégé de treize `@State` ; plus aucun `@Binding` du brouillon d'action ne traverse deux niveaux ; aucun changement visuel
- [x] Contraste ≥ 4,5:1 vérifié par test sur chaque paire texte/fond employée sous 12 px

## Tests

<REMPLACER par la sortie exacte de `swift test`>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Ne pas merger.

---

## Auto-revue

**Couverture du périmètre du lot (programme §5, Lot 0A) :**

| Point du périmètre | Tâche |
| --- | --- |
| 1. `One2OneTokens.swift`, table §1.2 + `dark/*` complet + largeurs fixes | 1 |
| 2. Typographie Plex + fontes embarquées + test des 5 noms + licence OFL | 2 |
| 3. Dix primitives + un `#Preview` chacune | 4 et 5 |
| 4. `One2OneTheme` en `EnvironmentValue` | 3 |
| 5. `MeetingScreenModel` + persistance + migration sans changement visuel | 6 et 7 |
| 6. Test de contraste ≥ 4,5:1 | 1 (et repris par thème en 3, par ton de chip en 4) |
| Critère « build et tests inchangés » | 7 (étape 5) et 8 (étape 1) |
| `STATUS.md`, branche, PR | 8 |

**Cohérence des types entre tâches :** `ChipTon` est défini en tâche 4 (`Chip.swift`) et
consommé par `Pill` dans la même tâche ; `One2OneColors.pill` est défini en tâche 3 et
consommé par `AvatarStack` en tâche 5 ; `ContrastRatio.ratio` rend un `Double?` et tous
les tests le déplient par `#require` ; `MeetingScreenModel.showSpeakers` (tâche 6)
correspond bien à `showSpeakersView` retiré en tâche 7 ; `resetActionDraft()` est défini
en tâche 6 et appelé par `addTask()` en tâche 7.
