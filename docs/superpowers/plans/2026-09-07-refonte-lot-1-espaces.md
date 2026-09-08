# Lot 1 — barre du haut, trois espaces, modes, bandeau KPI

> **Pour les sessions d'exécution :** COMPÉTENCE REQUISE — `superpowers:executing-plans`
> ou `superpowers:subagent-driven-development`, tâche par tâche, en TDD. Les étapes
> sont des cases à cocher (`- [ ]`).

**Objectif :** remplacer les sept onglets de `MeetingView` par les trois espaces
(`Réunion` / `Rapport` / `Ressources`) et le sélecteur de mode
(`Préparer` / `En séance` / `Relire`), avec la barre du haut sur une ligne de 38 px, le
bandeau de quatre indicateurs et la barre d'invocation de l'assistant — la **partie haute**
de `docs/superpowers/specs/refonte-2026-09/ecrans/1a-cockpit.png`.

**Architecture :** rien n'est ajouté à `MeetingView.swift` : le chrome, la barre d'espaces,
le bandeau KPI, les trois espaces et l'assistant vivent dans `OneToOne/Views/Meeting/Spaces/`
et ne reçoivent que des valeurs et des closures. `MeetingScreenModel` (lot 0A) devient
l'unique porteur de l'état d'écran — espace, mode, brouillon d'action **et** tête de lecture
(le registre global `MeetingPlayhead.for(meeting:)` disparaît). Tout calcul (indicateurs,
largeurs de colonnes, invites d'état vide, contenu du mode Préparer) est une fonction pure
dans `Services/` ou `Models/`, testée avant la vue.

**Pile :** SwiftUI + SwiftData, exécutable SwiftPM, Swift Testing (`@Suite`/`@Test`) pour le
neuf, XCTest conservé pour l'existant. Aucune dépendance nouvelle.

**Spécification :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §1.1, §1.2,
§1.4, §2.1, §2.2, §2.3 et « Critères d'acceptation — chantier 1 » n° 1, 4, 5.
**Programme :** `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 1 »,
décisions D0 (1c = mode Relire) et D8 (le dashboard personnalisable quitte l'espace Réunion,
son code n'est supprimé qu'au lot 19).
**Écran de référence :** `docs/superpowers/specs/refonte-2026-09/ecrans/1a-cockpit.png`.

## Contraintes globales

- Aucune couleur en dehors de `One2OneToken` (`OneToOne/Views/DesignSystem/One2OneTokens.swift`) ;
  `Color(hex:)` y est privé au fichier, cette règle reste vérifiable.
- Aucune fonte hors `Font.plexSans` / `Font.plexMono` (`One2OneTypography.swift`) ; jamais de
  `.weight()` par-dessus, les noms PostScript sont abrégés (`IBMPlexSans-Medm`, `-SmBld`).
- Aucune dépendance nouvelle dans `Package.swift`.
- Commentaires et libellés d'interface en **français**, symboles en anglais.
- Énums persistées SwiftData en `…Raw: String` + wrapper calculé. Aucune montée de schéma :
  `SchemaV3` du lot 0B suffit, le lot 1 n'ajoute ni table ni colonne.
- `MeetingView.swift` ne reçoit que du **routage** : viser au moins −400 lignes.
- `Note` (`MeetingKind.note`) garde son éditeur markdown et les chemins
  `adoptPendingLiveNotes()` / `discardEmptyNoteIfNeeded()` **intacts**.
- Aucun test ne dépend de MLX ni d'une session graphique.
- `swift build` avant chaque commit ; `swift test` complet vert avant chaque PR
  (référence après 0A+0B : 1 037 XCTest + ~664 Swift Testing ≈ 1 700).
- Un commit par tâche, message conventionnel, terminé par
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Découpage en deux PR empilées

Le lot compte 15 tâches, au-delà du seuil de 14 fixé par le programme §7. Il est donc coupé
en deux branches empilées :

| Branche | Tâches | Périmètre du programme §5 |
| --- | --- | --- |
| `feat/refonte-lot-1a-chrome` | 1 → 6 | tâches 1 (barre du haut), 2 (barre d'espaces), 7 (migration d'état) et le **routage minimal** des trois espaces, sans lequel 1a laisserait l'écran incohérent (les sept onglets et les trois espaces ne peuvent pas coexister) |
| `feat/refonte-lot-1b-espaces-kpi-assistant` (sur 1a) | 7 → 15 | tâches 3 (bandeau KPI), 4 (contenu des modes), 5 (assistant), 6 (mode Préparer), 8 (jeu de démonstration) |

## Structure de fichiers

**Créés — `OneToOne/Views/Meeting/Spaces/`**

| Fichier | Responsabilité |
| --- | --- |
| `MeetingSpacesBar.swift` | Barre d'espaces 34 px : trois espaces avec compteurs, `SegmentedMode` des modes, date. |
| `MeetingKPIBand.swift` | Les quatre cartes d'indicateurs, rendu seul (les nombres viennent de `MeetingKPIBuilder`). |
| `MeetingSpaceView.swift` | L'espace `Réunion` : aiguille sur le mode et compose bandeau + contenu + barre d'assistant. |
| `MeetingLiveSpace.swift` | Mode En séance : notes markdown ↔ transcription à parts égales (contenu provisoire du lot 2). |
| `MeetingReviewSpace.swift` | Mode Relire : résumé, décisions, liste d'actions (contenu provisoire du lot 5). |
| `MeetingPrepareSpace.swift` | Mode Préparer : actions reportées, derniers points, alertes, rail réduit, composeur de sujet. |
| `MeetingResourcesSpace.swift` | Espace `Ressources` : contenu de `documentsView`, compteur, zone de dépôt active. |
| `MeetingAssistantDock.swift` | Barre d'invocation persistante + `MeetingAssistantPanel` qui héberge `MeetingChatView`. |
| `MeetingEmptyInvite.swift` | La primitive d'invite d'état vide (critère n° 1) : jamais de `ContentUnavailableView` muet. |

**Créés — logique pure**

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/Meeting/MeetingKPIBuilder.swift` | `MeetingKPI` (présence, actions, décisions, risques) calculé depuis un `Meeting`. |
| `OneToOne/Services/Meeting/MeetingSpaceLayout.swift` | Largeurs des colonnes à une largeur de fenêtre donnée (critère n° 5). |
| `OneToOne/Services/Meeting/MeetingPrepareBuilder.swift` | Actions reportées, trois derniers points du projet, alertes du mode Préparer. |
| `OneToOne/Services/Meeting/MeetingSpaceRouting.swift` | Espaces visibles selon le `MeetingKind` — remplace `MeetingView.visibleSections(for:)`. |

**Modifiés**

| Fichier | Nature |
| --- | --- |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | réécrit sur une ligne 38 px. |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | porte la tête de lecture ; `MeetingPlayhead` perd son registre global. |
| `OneToOne/Services/Live/MeetingPlayhead.swift` | registre retiré, `marker(at:)` conservé, `addMarker(at:kind:)` ajouté. |
| `OneToOne/Views/MeetingView.swift` | routage seulement ; `MeetingSection`, `MeetingTabsUnderline` et `sectionContent` retirés. |
| `OneToOne/Views/Menus/MeetingMenuActions.swift`, `Menus/MeetingCommands.swift` | `⌘K` et `⌘M`. |
| `OneToOne/Views/MeetingDetailsBlock.swift` | accueille `MeetingTagEditor`, chassé de la barre du haut. |
| `Tests/MeetingVisibleSectionsTests.swift` | adapté au nouveau routage (fichier conservé). |
| `STATUS.md` | section en tête. |

**Supprimé :** `OneToOne/Views/Meeting/MeetingTabsUnderline.swift` (93 l.).

---

## Branche `feat/refonte-lot-1a-chrome`

### Tâche 1 — La tête de lecture appartient au modèle d'écran

Reprend la note d'écart n° 1 du lot 0B : le registre statique LRU à 4 de `MeetingPlayhead`
devient une propriété de `MeetingScreenModel`, un modèle par réunion ouverte.

**Fichiers**
- Modifier : `OneToOne/Views/Meeting/MeetingScreenModel.swift`
- Modifier : `OneToOne/Services/Live/MeetingPlayhead.swift` (retrait de `registry`,
  `registryCapacity`, `registryCount`, `for(meeting:)`, `resetRegistryForTesting`)
- Modifier : `OneToOne/Views/MeetingView.swift` (`private var playhead` → `screen.playhead`)
- Modifier : `Tests/MeetingPlayheadTests.swift` (tests du registre remplacés)
- Modifier : `Tests/MeetingScreenModelTests.swift`

**Interfaces**
- Produit : `MeetingScreenModel.playhead: MeetingPlayhead` (non optionnel, créé au premier
  accès), `MeetingScreenModel.attachPlayhead(meeting: Meeting)`,
  `MeetingPlayhead.addMarker(at:kind:label:)`.
- Consomme : `MeetingPlayhead.init(meetingStableID:player:now:)`, `beginRecording(startedAt:)`.

- [ ] **Étape 1 : écrire les tests qui échouent**

```swift
// Tests/MeetingScreenModelTests.swift — ajouts
@Test("La tête de lecture est celle du modèle d'écran, une par réunion")
@MainActor func playheadBelongsToScreen() {
    let a = MeetingScreenModel(defaults: Self.scratchDefaults())
    a.attach(meetingID: UUID())
    let first = a.playhead
    #expect(a.playhead === first)          // deux accès, une instance
    let b = MeetingScreenModel(defaults: Self.scratchDefaults())
    b.attach(meetingID: UUID())
    #expect(b.playhead !== first)          // deux réunions, deux têtes
}

@Test("Un marqueur posé sur la tête de lecture y reste, trié")
@MainActor func markerIsKept() {
    let s = MeetingScreenModel(defaults: Self.scratchDefaults())
    s.attach(meetingID: UUID())
    s.playhead.addMarker(at: 30, kind: .note)
    s.playhead.addMarker(at: 10, kind: .decision)
    #expect(s.playhead.markers.map(\.t) == [10, 30])
    #expect(s.playhead.marker(at: 10.2)?.kind == .decision)
}
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter MeetingScreenModelTests` → échec de compilation
(« value of type 'MeetingScreenModel' has no member 'playhead' »).

- [ ] **Étape 3 : implémenter**

Dans `MeetingScreenModel` : `private var storedPlayhead: MeetingPlayhead?`, accesseur
`var playhead: MeetingPlayhead` qui crée l'instance à la demande, et
`func attachPlayhead(meeting: Meeting)` qui, si `meeting.recordingStartedAt != nil` et
`AudioRecorderService.shared.isRecording(for:)`, appelle `beginRecording(startedAt:)`.
Dans `MeetingPlayhead` : supprimer les cinq membres statiques du registre, ajouter

```swift
func addMarker(at t: Double, kind: Marker.Kind, label: String = "") {
    markers.append(Marker(t: t, kind: kind, label: label))
}
```

Dans `MeetingView` : `private var playhead: MeetingPlayhead { screen.playhead }` et, dans
`.onAppear`, `screen.attachPlayhead(meeting: meeting)` juste après `screen.attach(meetingID:)`.

- [ ] **Étape 4 : vérifier le passage**

`swift test --filter MeetingScreenModelTests` puis `--filter MeetingPlayheadTests` → vert.

- [ ] **Étape 5 : commit**

```bash
git add -A && git commit -m "refactor(reunion): la tête de lecture appartient au modèle d'écran"
```

---

### Tâche 2 — Largeurs de colonnes (critère d'acceptation n° 5)

**Fichiers**
- Créer : `OneToOne/Services/Meeting/MeetingSpaceLayout.swift`
- Créer : `Tests/MeetingSpaceLayoutTests.swift`

**Interfaces**
- Produit : `enum MeetingSpaceLayout { static let fluidMinimum: CGFloat = 520 ;
  static func columns(totalWidth: CGFloat, rail: CGFloat?, sideNav: CGFloat?) ->
  (fluid: CGFloat, rail: CGFloat, sideNav: CGFloat) ; static func showsRail(totalWidth:) -> Bool }`

- [ ] **Étape 1 : écrire le test qui échoue**

```swift
@Suite("Largeurs des colonnes de l'espace Réunion")
struct MeetingSpaceLayoutTests {
    @Test("À 1 280 px, la colonne fluide dépasse 520 px avec le rail de 330")
    func fluidAt1280() {
        let c = MeetingSpaceLayout.columns(totalWidth: 1280, rail: One2OneToken.actionsRailWidth, sideNav: nil)
        #expect(c.rail == 330)
        #expect(c.fluid >= MeetingSpaceLayout.fluidMinimum)
        #expect(c.fluid + c.rail + c.sideNav <= 1280)
    }

    @Test("Le mode Relire ajoute la nav de 190 px sans descendre sous 520")
    func reviewAt1280() {
        let c = MeetingSpaceLayout.columns(totalWidth: 1280, rail: One2OneToken.actionsRailWidth, sideNav: One2OneToken.sideNavWidth)
        #expect(c.fluid >= MeetingSpaceLayout.fluidMinimum)
        #expect(c.fluid + c.rail + c.sideNav <= 1280)
    }

    @Test("Sous le minimum, le rail est retiré plutôt que chevauché")
    func railDropsBelowMinimum() {
        #expect(MeetingSpaceLayout.showsRail(totalWidth: 1280))
        #expect(!MeetingSpaceLayout.showsRail(totalWidth: 820))
        let c = MeetingSpaceLayout.columns(totalWidth: 820, rail: One2OneToken.actionsRailWidth, sideNav: nil)
        #expect(c.rail == 0)
        #expect(c.fluid == 820)
    }

    @Test("Aucune largeur n'est négative, même sur une fenêtre absurde")
    func neverNegative() {
        let c = MeetingSpaceLayout.columns(totalWidth: 200, rail: 330, sideNav: 190)
        #expect(c.fluid >= 0 && c.rail >= 0 && c.sideNav >= 0)
        #expect(c.fluid + c.rail + c.sideNav <= 200)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec** — `swift test --filter MeetingSpaceLayoutTests`.
- [ ] **Étape 3 : implémenter** — les colonnes fixes ne sont accordées que si le reste tient
la fluide à `fluidMinimum` ; sinon elles sont abandonnées dans l'ordre `sideNav` puis `rail`,
et la fluide prend tout. Aucune soustraction non bornée : `max(0, …)` partout.
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(reunion): largeurs de colonnes de l'espace Réunion`.

---

### Tâche 3 — Routage des espaces selon le type de réunion

**Fichiers**
- Créer : `OneToOne/Services/Meeting/MeetingSpaceRouting.swift`
- Modifier : `Tests/MeetingVisibleSectionsTests.swift` (adapté, **pas** supprimé)

**Interfaces**
- Produit : `enum MeetingSpaceRouting { static func spaces(for kind: MeetingKind) ->
  [MeetingScreenModel.Space] ; static func modes(for kind: MeetingKind) ->
  [MeetingScreenModel.Mode] ; static func fallback(space:mode:for:) ->
  (MeetingScreenModel.Space, MeetingScreenModel.Mode) }`

- [ ] **Étape 1 : écrire les tests qui échouent**

```swift
@Suite("Espaces visibles selon le type de réunion")
struct MeetingVisibleSectionsTests {

    @Test("Une note n'a que son corps et ses ressources — ni rapport, ni modes")
    func noteHasTwoSpaces() {
        #expect(MeetingSpaceRouting.spaces(for: .note) == [.meeting, .resources])
        #expect(MeetingSpaceRouting.modes(for: .note) == [])
    }

    @Test("Les autres types ont les trois espaces et les trois modes")
    func othersHaveEverything() {
        for kind in MeetingKind.allCases where kind != .note {
            #expect(MeetingSpaceRouting.spaces(for: kind) == [.meeting, .report, .resources])
            #expect(MeetingSpaceRouting.modes(for: kind) == [.prepare, .live, .review])
        }
    }

    @Test("Un espace mémorisé devenu invisible retombe sur Réunion")
    func fallbackWhenKindChanges() {
        let r = MeetingSpaceRouting.fallback(space: .report, mode: .review, for: .note)
        #expect(r.0 == .meeting)
        #expect(r.1 == .live)
        let kept = MeetingSpaceRouting.fallback(space: .report, mode: .review, for: .project)
        #expect(kept.0 == .report && kept.1 == .review)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** le fichier (trois fonctions, `switch` sans `default`).
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(reunion): routage des trois espaces selon le type`.

---

### Tâche 4 — Barre du haut sur une ligne de 38 px

Spec §2.1. La deuxième ligne (`MeetingTagEditor`) part dans la feuille Détails.

**Fichiers**
- Modifier : `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (réécrit)
- Modifier : `OneToOne/Views/MeetingDetailsBlock.swift` (accueille `MeetingTagEditor`)
- Modifier : `OneToOne/Views/MeetingView.swift` (paramètres de la barre)
- Créer : `Tests/MeetingTopChromeBarTests.swift`

**Interfaces**
- Consomme : `MeetingMenuActions` (inchangé), `MeetingScreenModel.playhead`,
  `One2OneToken`, `Font.plexSans/plexMono`.
- Produit : `MeetingTopChromeBar.height: CGFloat = 38`,
  `MeetingTopChromeBar.tint(for kind: MeetingKind) -> Color` (barre teintée
  `#f4f1f6` = `One2OneToken.oneOnOneBg` pour `.oneToOne` et `.manager`, `bgApp` sinon),
  `MeetingTopChromeBar.TimecodeInput.parse(_:) -> Double?`.

- [ ] **Étape 1 : écrire les tests qui échouent**

```swift
@Suite("Barre du haut de la réunion")
struct MeetingTopChromeBarTests {

    @Test("Hauteur de 38 px, comme la spec §2.1")
    func height() { #expect(MeetingTopChromeBar.height == 38) }

    @Test("Les deux types 1:1 teintent la barre, les autres non")
    func tintFollowsKind() {
        #expect(MeetingTopChromeBar.tint(for: .oneToOne) == One2OneToken.oneOnOneBg)
        #expect(MeetingTopChromeBar.tint(for: .manager) == One2OneToken.oneOnOneBg)
        #expect(MeetingTopChromeBar.tint(for: .project) == One2OneToken.bgApp)
        #expect(MeetingTopChromeBar.tint(for: .workshop) == One2OneToken.bgApp)
    }

    @Test("Un timecode tapé à la main est lu, et le reste rejeté")
    func timecodeParsing() {
        #expect(MeetingTopChromeBar.TimecodeInput.parse("04:12") == 252)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("4:12") == 252)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("1:02:03") == 3723)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("252") == 252)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("04:99") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("abc") == nil)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter la barre** — un seul `HStack(spacing: 10)` dans un
`.frame(height: 38)`, `.padding(.horizontal, 14)`, fond `tint(for:)`, bordure basse
`One2OneToken.cardBorder` sur 1 px. De gauche à droite :

1. bouton panneau (`sidebar.left`) si `onBack != nil`, `⌘[` conservé ;
2. fil d'Ariane `One2One › <projet> ›` en `Font.plexSans(.regular, 11)` `ink4`, le segment
   projet dans un `RoundedRectangle(cornerRadius: 5).strokeBorder(One2OneToken.action)`,
   cliquable → `onOpenProject` ;
3. titre `EditableTextField` en `Font.plexSans(.semibold, 13)`,
   `.frame(maxWidth: .infinity).lineLimit(1)` — le `flex:1; min-width:0` de la spec ;
4. pilule audio : `RoundedRectangle(cornerRadius: One2OneToken.radiusAudio)` remplie
   `One2OneToken.ink1`, contenant `▶`/`⏸`, `Text(playhead.formatted) / mmss(duration)` en
   `Font.plexMono(.medium, 10)`, un bouton marqueur (`⌘M`) et `✂`. Clic sur le temps → champ
   de saisie validé par `TimecodeInput.parse` puis `playhead.seek(to:)` ;
5. menu type : les sept `MeetingKind`, un `Divider()`, puis « Nouvelle réunion… » (le `+`
   de l'ancienne deuxième ligne) ;
6. menu template : `templatePickerButton` existant, réhabillé ;
7. bouton `Rapport ✓ (m:ss)` : fond `One2OneToken.report`, rayon `radiusButton` ;
8. `⋯` de 28 px : `moreMenu` existant (Exporter, Détails, Importer, Audio, Supprimer).

Supprimer le `VStack` et l'appel à `MeetingTagEditor` ; le déplacer dans
`MeetingDetailsBlock`, avec le même binding sur `screen.suggestedTagNames`.

- [ ] **Étape 4 : vérifier le passage** — `swift build` puis la suite.
- [ ] **Étape 5 : commit** — `feat(reunion): barre du haut sur une ligne de 38 px`.

---

### Tâche 5 — Barre d'espaces de 34 px

Spec §2.2.

**Fichiers**
- Créer : `OneToOne/Views/Meeting/Spaces/MeetingSpacesBar.swift`
- Créer : `Tests/MeetingSpacesBarTests.swift`
- Supprimer : `OneToOne/Views/Meeting/MeetingTabsUnderline.swift`
- Modifier : `OneToOne/Views/MeetingView.swift`

**Interfaces**
- Produit : `MeetingSpacesBar` (init `screen:`, `kind:`, `hasReport:`, `documentsCount:`,
  `date:`), `MeetingSpacesBar.height: CGFloat = 34`,
  `MeetingSpacesBar.label(for:hasReport:documentsCount:) -> (titre: String, complement: String)`.
- Consomme : `MeetingSpaceRouting` (tâche 3), `SegmentedMode` (lot 0A).

- [ ] **Étape 1 : écrire les tests qui échouent**

```swift
@Suite("Barre d'espaces")
struct MeetingSpacesBarTests {

    @Test("Hauteur de 34 px, comme la spec §2.2")
    func height() { #expect(MeetingSpacesBar.height == 34) }

    @Test("Chaque espace porte un compteur ou un état, jamais rien (spec §1.1)")
    func everySpaceCarriesACounter() {
        #expect(MeetingSpacesBar.label(for: .meeting, hasReport: false, documentsCount: 0).titre == "Réunion")
        #expect(MeetingSpacesBar.label(for: .report, hasReport: false, documentsCount: 0).complement == "à générer")
        #expect(MeetingSpacesBar.label(for: .report, hasReport: true, documentsCount: 0).complement == "✓")
        #expect(MeetingSpacesBar.label(for: .resources, hasReport: true, documentsCount: 0).complement == "0 doc")
        #expect(MeetingSpacesBar.label(for: .resources, hasReport: true, documentsCount: 1).complement == "1 doc")
        #expect(MeetingSpacesBar.label(for: .resources, hasReport: true, documentsCount: 7).complement == "7 docs")
    }

    @Test("Les libellés des modes sont ceux de la capture")
    func modeLabels() {
        #expect(MeetingScreenModel.Mode.prepare.label == "Préparer")
        #expect(MeetingScreenModel.Mode.live.label == "En séance")
        #expect(MeetingScreenModel.Mode.review.label == "Relire")
    }
}
```

- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** — `HStack` de 34 px, fond `One2OneToken.bgApp`, bordure basse
`cardBorder`. À gauche, `ForEach` sur `MeetingSpaceRouting.spaces(for: kind)` : titre en
`Font.plexSans(.semibold, 12)` `ink1` si actif (`ink3` sinon), complément en
`Font.plexSans(.regular, 10.5)` `inkMuted`, et pour l'espace actif un
`Rectangle().fill(One2OneToken.report).frame(height: 2)`. À droite, si
`!MeetingSpaceRouting.modes(for: kind).isEmpty`, un `SegmentedMode` lié à `screen.mode`, puis
la date au format `4 sept. 2026 · 9:15`. Ajouter `var label: String` sur
`MeetingScreenModel.Mode` et `.Space`. Supprimer `MeetingTabsUnderline.swift`.
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(reunion): barre d'espaces de 34 px`.

---

### Tâche 6 — Routage dans `MeetingView` : les sept onglets disparaissent

**Fichiers**
- Modifier : `OneToOne/Views/MeetingView.swift`
- Créer : `OneToOne/Views/Meeting/Spaces/MeetingEmptyInvite.swift`
- Créer : `OneToOne/Views/Meeting/Spaces/MeetingResourcesSpace.swift`
- Créer : `Tests/MeetingEmptyInviteTests.swift`
- Modifier : `OneToOne/Views/Menus/MeetingMenuActions.swift`, `Menus/MeetingCommands.swift`,
  `Tests/MeetingMenuActionsTests.swift`

**Interfaces**
- Produit : `MeetingEmptyInvite` (init `titre:`, `invite:`, `libelleAction:`, `action:`),
  `MeetingEmptyInvite.Catalogue.invite(for space:mode:) -> (titre: String, invite: String)`,
  `MeetingResourcesSpace`.

- [ ] **Étape 1 : écrire le test qui échoue (critère n° 1)**

```swift
@Suite("Aucun espace vide sans invite (critère chantier 1 n° 1)")
struct MeetingEmptyInviteTests {

    @Test("Les neuf combinaisons espace × mode ont toutes une invite non vide")
    func everyStateHasAnInvite() {
        for space in MeetingScreenModel.Space.allCases {
            for mode in MeetingScreenModel.Mode.allCases {
                let i = MeetingEmptyInvite.Catalogue.invite(for: space, mode: mode)
                #expect(!i.titre.isEmpty)
                #expect(!i.invite.isEmpty)
            }
        }
    }

    @Test("L'invite dit quoi faire, pas seulement qu'il n'y a rien")
    func inviteIsActionable() {
        #expect(MeetingEmptyInvite.Catalogue.invite(for: .meeting, mode: .live).invite.contains("/"))
        let res = MeetingEmptyInvite.Catalogue.invite(for: .resources, mode: .live).invite.lowercased()
        #expect(res.contains("dépos") || res.contains("import"))
    }
}
```

- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** — `MeetingEmptyInvite` : `VStack` centré, titre en
`Font.plexSans(.semibold, 12)` `ink2`, invite en `Font.plexSans(.regular, 11.5)` `inkMuted`,
bouton facultatif. `Catalogue` : neuf entrées explicites, aucun `default`.
`MeetingResourcesSpace` : reprise de `documentsView` dont le `ContentUnavailableView` cède la
place à `MeetingEmptyInvite`, la zone de dépôt restant visible en permanence.
`mainPanel` devient :

```swift
private var mainPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
        MeetingSpacesBar(screen: screen, kind: meeting.kind,
                         hasReport: !meeting.summary.isEmpty,
                         documentsCount: meeting.attachments.count,
                         date: meeting.date)
        spaceContent
    }
    .background(One2OneToken.bgCanvas)
    .onAppear { normalizeSpace() }
    .onChange(of: meeting.kind) { _, _ in normalizeSpace() }
}
```

`normalizeSpace()` applique `MeetingSpaceRouting.fallback` ; `spaceContent` aiguille
`.meeting` → contenu provisoire (markdown + `transcriptView`), `.report` → `reportView`,
`.resources` → `MeetingResourcesSpace`. Les `activeSection = …` deviennent des affectations
sur `screen`. `MeetingChatView` et `OverviewDashboard` ne sont plus instanciés (D8).

- [ ] **Étape 4 : `⌘K` et `⌘M` dans les menus** — deux closures `openAssistant`,
`addPlayheadMarker`, deux cas `MeetingMenuItem.assistant` / `.marker`, `isEnabled` →
`assistant: true`, `marker: hasPlayableAudio || isRecording`. Dans `MeetingCommands`,
`.keyboardShortcut("k", modifiers: .command)` et `("m", modifiers: .command)`. Test :

```swift
@Test("⌘K est toujours actif, ⌘M exige un audio ou un enregistrement")
func assistantAndMarkerAvailability() {
    #expect(Self.make(kind: .project, hasPlayableAudio: false).isEnabled(.assistant))
    #expect(!Self.make(kind: .project, hasPlayableAudio: false).isEnabled(.marker))
    #expect(Self.make(kind: .project, hasPlayableAudio: true).isEnabled(.marker))
    #expect(Self.make(kind: .note, hasPlayableAudio: false).isEnabled(.assistant))
}
```

- [ ] **Étape 5 : vérifier** — `swift build` puis `swift test` **complet**.
- [ ] **Étape 6 : commits** — `feat(reunion): les sept onglets cèdent la place aux trois espaces`
puis `feat(reunion): ⌘K pour l'assistant, ⌘M pour un marqueur`.
- [ ] **Étape 7 : PR 1a** — `git push -u origin feat/refonte-lot-1a-chrome`, `gh pr create`.

---

## Branche `feat/refonte-lot-1b-espaces-kpi-assistant` (basée sur 1a)

### Tâche 7 — `MeetingKPIBuilder` : les quatre indicateurs, calcul pur

Spec §2.3.

**Fichiers**
- Créer : `OneToOne/Services/Meeting/MeetingKPIBuilder.swift`
- Créer : `Tests/MeetingKPIBuilderTests.swift`

**Interfaces**
- Produit :

```swift
struct MeetingKPI: Equatable, Sendable {
    struct Presence: Equatable, Sendable { var present: Int; var total: Int; var percent: Int; var initials: [String] }
    struct Actions: Equatable, Sendable { var total: Int; var unassigned: Int; var done: Int; var doneFraction: Double }
    struct Decisions: Equatable, Sendable { var count: Int; var budgetCount: Int; var first: String? }
    enum Level: String, Sendable { case critique, eleve, modere, faible }
    struct Risks: Equatable, Sendable { var count: Int; var criticalCount: Int; var levels: [Level]; var overflow: Int }
    var presence: Presence; var actions: Actions; var decisions: Decisions; var risks: Risks
}
enum MeetingKPIBuilder {
    static let maxRiskDots = 8
    @MainActor static func build(meeting: Meeting) -> MeetingKPI
    static func initials(_ name: String) -> String
    static func level(fromSeverity: String) -> MeetingKPI.Level
}
```

- Consomme : `PresenceStats.compute(statuses:)`, `Meeting.participantStatus(for:)`,
  `Meeting.tasks`, `Meeting.decisions`, `Meeting.meetingAlerts`.

- [ ] **Étape 1 : écrire les tests qui échouent** — initiales (`PY`, `NL`, `LD`), actions
(total / non assignées / part faite), décisions (compte, première en clair, mention budget),
risques (niveaux ordonnés du plus grave, surplus au-delà de huit), réunion vide (compteurs à
zéro, jamais d'état invalide).
- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** — présence par `PresenceStats`, non assignées par le champ de
responsable d'`ActionTask` (nom exact à lire dans le modèle), `budgetCount` = lignes contenant
« budget » sans casse ni diacritiques, risques triés par gravité décroissante,
`doneFraction = 0` si `total == 0`.
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(reunion): calcul des quatre indicateurs`.

---

### Tâche 8 — `MeetingKPIBand` : les quatre cartes

**Fichiers**
- Créer : `OneToOne/Views/Meeting/Spaces/MeetingKPIBand.swift`

**Interfaces**
- Produit : `MeetingKPIBand` (init `kpi:`, `onManageParticipants:`, `onFilterDecisions:`,
  `onOpenRisks:`).
- Consomme : `MeetingKPI`, `AvatarStack`, `ProgressBar`, `SectionLabel`, `RefonteCard`,
  `MeetingEmptyInvite.Catalogue`.

- [ ] **Étape 1** — un `#Preview` par état (plein, tout à zéro) ; la logique est déjà couverte
par les tâches 6 et 7.
- [ ] **Étape 2 : implémenter** — quatre colonnes égales, `spacing: 10`, cartes
`RefonteCard(padding: 12)` : `SectionLabel`, valeur en `Font.plexSans(.semibold, 20)` `ink1`,
complément, micro-visualisation (`AvatarStack`, `ProgressBar`, première décision en
`lineLimit(1)`, points de 7 px teintés par niveau + `+n`). Compteur à 0 → texte de
`MeetingEmptyInvite.Catalogue` au lieu de la micro-visualisation. Zones cliquables branchées
sur les trois closures.
- [ ] **Étape 3 : vérifier** — `swift build`.
- [ ] **Étape 4 : commit** — `feat(reunion): bandeau des quatre indicateurs`.

---

### Tâche 9 — `MeetingSpaceView` : l'espace Réunion et ses trois modes

**Fichiers**
- Créer : `MeetingSpaceView.swift`, `MeetingLiveSpace.swift`, `MeetingReviewSpace.swift`
  dans `OneToOne/Views/Meeting/Spaces/`
- Modifier : `OneToOne/Views/MeetingView.swift`

- [ ] **Étape 1 : `MeetingLiveSpace`** — `GeometryReader`, `HStack(spacing: 0)` de deux
colonnes égales séparées par un filet de 1 px `One2OneToken.hair` : à gauche l'éditeur
markdown `liveNotes` existant, à droite `transcriptView` existant. En-tête
« Notes & transcription · synchronisées sur l'audio », bascule `Speakers` liée à
`screen.showSpeakers`, bouton `Résumer`. Aucune `ScrollView` non bornée imbriquée (piège n° 4
du programme §2.4).
- [ ] **Étape 2 : `MeetingReviewSpace`** — `ScrollView` unique : carte `EN UNE PHRASE`
(`meeting.shortSummary`, sinon `MeetingEmptyInvite` vers `SummaryCard.generate`), carte
`DÉCISIONS PRISES · n`, puis la liste d'actions existante ; transcription repliée.
- [ ] **Étape 3 : `MeetingSpaceView`** — `VStack(spacing: 0)` : `MeetingKPIBand` (modes
`live` et `review`), contenu du mode, `MeetingAssistantDock` en pied.
- [ ] **Étape 4 : brancher** dans `MeetingView`, `swift build`.
- [ ] **Étape 5 : commit** — `feat(reunion): l'espace Réunion et ses trois modes`.

---

### Tâche 10 — Changer de mode ne perd aucune saisie (critère n° 4)

**Fichiers**
- Modifier : `OneToOne/Views/Meeting/MeetingScreenModel.swift`
- Modifier : `Tests/MeetingScreenModelTests.swift`

**Interfaces**
- Produit : `MeetingScreenModel.pendingNoteText: String` (non persisté, jamais vidé par un
  changement d'espace ni de mode).

- [ ] **Étape 1 : écrire les tests qui échouent**

```swift
@Test("Préparer → En séance → Relire ne perd ni le brouillon d'action ni le texte en cours")
@MainActor func modeChangeKeepsDrafts() {
    let s = MeetingScreenModel(defaults: Self.scratchDefaults())
    s.attach(meetingID: UUID())
    s.newTaskTitle = "Chiffrer la fin de migration"
    s.newTaskUrgent = true
    s.newTaskPomodoros = 2
    s.pendingNoteText = "40k déjà payés, rien de finalisé"
    for mode in [MeetingScreenModel.Mode.prepare, .live, .review, .prepare] {
        s.mode = mode
        #expect(s.newTaskTitle == "Chiffrer la fin de migration")
        #expect(s.newTaskUrgent)
        #expect(s.newTaskPomodoros == 2)
        #expect(s.pendingNoteText == "40k déjà payés, rien de finalisé")
    }
    for space in MeetingScreenModel.Space.allCases {
        s.space = space
        #expect(s.newTaskTitle == "Chiffrer la fin de migration")
        #expect(s.pendingNoteText == "40k déjà payés, rien de finalisé")
    }
}

@Test("Le texte en cours n'est pas mémorisé d'une ouverture à l'autre")
@MainActor func pendingNoteIsNotPersisted() {
    let defaults = Self.scratchDefaults()
    let id = UUID()
    let first = MeetingScreenModel(defaults: defaults)
    first.attach(meetingID: id)
    first.pendingNoteText = "en cours"
    let second = MeetingScreenModel(defaults: defaults)
    second.attach(meetingID: id)
    #expect(second.pendingNoteText.isEmpty)
}
```

- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** — une propriété de plus, sans `didSet`.
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `test(reunion): changer de mode ne perd aucune saisie`.

---

### Tâche 11 — Espace Rapport et espace Ressources : compteurs et invites

- [ ] **Étape 1** — dans `reportView`, quand `meeting.summary.isEmpty`, `MeetingEmptyInvite`
(`Catalogue.invite(for: .report, mode:)`) avec un bouton « Générer le rapport ». Dans
`MeetingResourcesSpace`, la zone de dépôt reste visible même avec des documents et le compteur
vient de `MeetingSpacesBar.label` (pas de second calcul).
- [ ] **Étape 2 : vérifier** — `swift build`, `swift test --filter MeetingEmptyInviteTests`.
- [ ] **Étape 3 : commit** — `feat(reunion): invites d'état vide dans Rapport et Ressources`.

---

### Tâche 12 — Barre d'invocation de l'assistant et panneau

**Fichiers**
- Créer : `OneToOne/Views/Meeting/Spaces/MeetingAssistantDock.swift`
- Créer : `Tests/MeetingAssistantDockTests.swift`
- Modifier : `OneToOne/Views/MeetingView.swift`

**Interfaces**
- Produit : `MeetingAssistantDock` (init `meeting:`, `isOpen: Binding<Bool>`, `suggestions:`),
  `MeetingAssistantDock.suggestions(for meeting: Meeting) -> [String]`,
  `MeetingAssistantPanel` (héberge `MeetingChatView(meeting:)` **tel quel**).

- [ ] **Étape 1 : écrire le test qui échoue**

```swift
@Suite("Barre d'invocation de l'assistant")
@MainActor
struct MeetingAssistantDockTests {
    @Test("Toujours deux suggestions, jamais vides")
    func suggestions() {
        let s = MeetingAssistantDock.suggestions(for: Meeting(title: "[P25_110] Partage statut", date: .now))
        #expect(s.count == 2)
        #expect(s.allSatisfy { !$0.isEmpty })
    }
}
```

- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** — barre de 34 px en pied de l'espace Réunion : `✳` en
`One2OneToken.action`, placeholder « Demander à l'assistant sur cette réunion, l'historique,
les documents… », deux `Pill` de suggestion, `⌘K` en `Font.plexMono(.medium, 10)` `ink4`.
Fond `surface`, bordure `cardBorder`, rayon `radiusCard`. Un clic ou `⌘K` ouvre
`MeetingAssistantPanel` en `.sheet` (`minWidth: 560`).
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(reunion): barre d'invocation de l'assistant et ⌘K`.

---

### Tâche 13 — Mode Préparer

Spec §2.2, ligne « Préparer ». Pour les types 1:1 et Atelier, le même contenu pour l'instant
(les écrans dédiés arrivent aux lots 12, 14 et 18).

**Fichiers**
- Créer : `OneToOne/Services/Meeting/MeetingPrepareBuilder.swift`
- Créer : `OneToOne/Views/Meeting/Spaces/MeetingPrepareSpace.swift`
- Créer : `Tests/MeetingPrepareBuilderTests.swift`

**Interfaces**
- Produit :

```swift
struct MeetingPrepareContext: Equatable, Sendable {
    struct LastPoint: Equatable, Sendable { var title: String; var date: Date; var shortSummary: String }
    var carriedCount: Int
    var lastPoints: [LastPoint]     // 3 au plus, décroissant par date
    var alertTitles: [String]
}
enum MeetingPrepareBuilder {
    static let lastPointsCount = 3
    @MainActor static func build(meeting: Meeting, allMeetings: [Meeting]) -> MeetingPrepareContext
}
```

- Consomme : `PrepCarryoverService.drainStandingIntoMeeting(_:in:)`, `MeetingPrepTab`,
  `Meeting.shortSummary`, `Project.alerts`.

- [ ] **Étape 1 : écrire les tests qui échouent** — au plus trois derniers points, du même
projet, la réunion courante exclue et les réunions d'un autre projet écartées ; sans projet,
aucun dernier point mais jamais d'erreur ; seules les alertes non résolues remontent.
- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter le calcul** puis la vue : `HStack(spacing: 0)` — colonne
principale (`ACTIONS REPORTÉES`, `DERNIERS POINTS`, `ALERTES PROJET`, chacune avec son
`MeetingEmptyInvite` si vide) et rail réduit, un placeholder bordé de
`One2OneToken.actionsRailWidth` portant `MeetingEmptyInvite` (« Le rail d'actions arrive au
lot 3 »). En pied, le composeur de sujet réutilise `MeetingPrepTab(meeting:)` ;
`PrepCarryoverService.drainStandingIntoMeeting` est appelé au `.onAppear` du mode, comme le
faisait l'onglet Préparation.
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(reunion): mode Préparer — reports, derniers points, alertes`.

---

### Tâche 14 — Jeu de données de démonstration

**Fichiers**
- Créer : `OneToOne/Services/Debug/RefonteDemoSeed.swift`
- Modifier : le menu Debug existant (ou les réglages avancés)
- Créer : `Tests/RefonteDemoSeedTests.swift`

**Interfaces**
- Produit : `enum RefonteDemoSeed { @MainActor static func seed(in context: ModelContext) -> Meeting }`

- [ ] **Étape 1 : écrire le test qui échoue** — la réunion
`[P25_110] Partage statut final et chiffrage reste à faire` du projet
`S/D — Modernisation CI/CD`, 6 participants (initiales `PY NL CP LS CA LD`), 12 actions dont
9 non assignées, 3 décisions dont une contenant « partenaire », 5 risques dont 2 critiques,
présence à 100 % ; rejouer le semis ne duplique pas la réunion.
- [ ] **Étape 2 : vérifier l'échec.**
- [ ] **Étape 3 : implémenter** — notes et transcription recopiées de la capture,
`durationSeconds = 1404` (23:24). Idempotence par recherche du titre.
- [ ] **Étape 4 : vérifier le passage.**
- [ ] **Étape 5 : commit** — `feat(debug): jeu de démonstration de la refonte`.

---

### Tâche 15 — Recette visuelle, `STATUS.md`, PR

- [ ] **Étape 1** — `swift build -c release`, lancer `.build/release/OneToOne` (**pas**
`Scripts/bump-and-build.sh`), charger le jeu de démonstration.
- [ ] **Étape 2** — `screencapture -x` à 1 280 puis 1 920 px de large, enregistrées dans
`docs/superpowers/specs/refonte-2026-09/recette/lot-1-1280.png` et `lot-1-1920.png`.
- [ ] **Étape 3** — comparer à `ecrans/1a-cockpit.png`, lister les écarts.
- [ ] **Étape 4** — `swift test` complet, chiffres exacts relevés.
- [ ] **Étape 5** — `STATUS.md` : section en tête (créés, modifiés, tests, écarts, prochaine
action = lots 2, 3, 9), delta de lignes de `MeetingView.swift`.
- [ ] **Étape 6** — `git push -u origin feat/refonte-lot-1b-espaces-kpi-assistant`,
`gh pr create` vers `master`.

---

## Revue du plan

**Couverture de la spécification.** §2.1 → tâche 4 ; §2.2 → tâches 5 et 6 (barre), 9 et 13
(dispositions par mode) ; §2.3 → tâches 7 et 8 ; §1.1 « aucun onglet vide » → tâches 6 et 11 ;
§1.1 « l'assistant est une surface » → tâche 12 ; §1.4 `⌘K`, `⌘M` → tâche 6 étape 4 ; §1.2
(jetons, typographie, géométrie) → contrainte globale, tenue par chaque vue. Critères
d'acceptation : n° 1 → tâche 6 ; n° 4 → tâche 10 ; n° 5 → tâche 2. Les critères n° 2 et n° 3
relèvent des lots 2 et 3, hors périmètre.

**Programme §5 lot 1.** Tâche 1 du programme → tâche 4 ; 2 → tâche 5 ; 3 → tâches 7 et 8 ;
4 → tâches 6, 9 et 11 ; 5 → tâche 12 ; 6 → tâche 13 ; 7 (menus) → tâche 6 étape 4 ; migration
d'état → tâche 1 ; jeu de données → tâche 14. D8 est respectée : `OverviewDashboard` n'est plus
instanciée mais son fichier reste jusqu'au lot 19.

**Types et signatures.** `MeetingScreenModel.Space`/`.Mode` sont ceux du lot 0A et ne sont pas
renommés (leurs `rawValue` sont écrits dans `UserDefaults`). `MeetingKPI` de la tâche 7 est le
seul type lu par la tâche 8. `MeetingSpaceLayout.columns` rend un triplet nommé consommé par
la tâche 9. `MeetingEmptyInvite.Catalogue.invite(for:mode:)` est appelé par les tâches 8, 9,
11 et 13 sous cette seule signature.

**Point à vérifier à l'exécution :** le nom exact du champ de responsable sur `ActionTask`
(`assignee` ou `collaborator`) — la tâche 7 en dépend ; le lire avant d'écrire le test.
