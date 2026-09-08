# Lot 8 — Pastille flottante (écran 4b)

**Branche :** `feat/refonte-lot-8-pastille`, sur `feat/refonte-lot-7-captures` (base
`f3dc30c`, mémorisée dans `.lot8-base-sha`).
**Écran :** `docs/superpowers/specs/refonte-2026-09/ecrans/4b-pastille-flottante.png`.
**Spec :** `specs-one2one.md` §5.4, §1.4 (`⌘⇧S`, `⌘⇧N`), critère chantier 4 n° 2.
**Programme :** §2.5 (ligne « Pastille flottante » et « Raccourci global »), §5 lot 8, §7, §8.
**Référence copiée (jamais liée) :** `Teams-Capture/Sources/TeamsCapture/Pill/*`,
`Sources/CaptureDesign/ScreenCorner.swift` + `Tests/CaptureDesignTests/ScreenCornerTests.swift`,
`Sources/CaptureCore/PillMode.swift` + ses tests, `Sources/TeamsCapture/GlobalHotKey.swift`
(leçons seulement : le service Carbon de OneToOne est **réutilisé**).

---

## 1. Ce que le lot doit rendre vrai

1. Pendant une séance, une pastille sombre 300 × 40 (rayon 22, fond `rgba(20,18,15,.94)`)
   flotte au-dessus de Teams en plein écran, déplaçable, magnétisée aux quatre coins, le
   coin persisté.
2. Elle affiche `● mm:ss | ◫ Capturer | ✎ Note | n` : point rouge pulsant, chrono du
   `MeetingPlayhead` de la **réunion active**, compteur de captures de la séance.
3. `◫ Capturer` (ou `⌘⇧S`, sans focus) capture, insère la vignette dans les notes au
   timecode courant et ouvre une confirmation de 4 s — **sans jamais activer
   l'application ni changer d'espace** (critère chantier 4 n° 2).
4. La confirmation porte `CAPTURÉ · mm:ss`, la vignette, la première ligne d'OCR
   (« Texte en cours d'extraction… » tant qu'elle n'est pas arrivée) et
   `＋ Action depuis la capture`.
5. `✎ Note` (ou `⌘⇧N`) déplie un mini-champ dans la pastille ; `⌘⏎` crée une `MeetingNote`
   au `t` courant, `Esc` referme.
6. L'échec d'enregistrement d'un raccourci global est **dit** dans les réglages.
7. `⌥⌘⇧S` (ou l'entrée `Zone…`) trace une zone à la souris → `CaptureSource.region`.

## 2. Architecture retenue

### 2.1 La réunion active (`Services/Capture/ActiveMeetingRegistry.swift`)

La pastille vit hors de toute hiérarchie SwiftUI : il lui faut la réunion, son
`MeetingScreenModel`, son `ScreenCaptureService` et un `ModelContext`. Ces quatre objets
n'existent que dans `MeetingView` (`@StateObject private var captureService`), qui est
**interdit** à ce lot. D'où un registre :

- `ActiveMeetingHandle` : la poignée (réunion, modèle d'écran, coordinateur de capture,
  contexte, instant d'entrée en séance).
- `ActiveMeetingRegistry` (`@MainActor @Observable`, `.shared`) : la table des poignées,
  plus le miroir de `AudioRecorderService.shared.activeMeetingID` (abonnement
  `objectWillChange`, sans lequel un enregistrement démarré depuis une autre surface ne
  réveillerait rien).
- **Règle pure** `ActiveMeetingRegistry.activeID(recording:sessions:)` : la réunion qui
  **enregistre** d'abord, sinon la **dernière entrée en séance**, sinon aucune. Testée
  seule, sans SwiftData.
- Enregistrement : un modificateur `.sessionPill(...)` posé **une fois** sur
  `MeetingSpaceView`, exactement comme le lot 4 y pose `.sessionFullscreen(...)` (le seul
  endroit de l'application qui tienne à la fois la réunion, son écran et son
  coordinateur de capture). C'est la seule ligne ajoutée à un fichier partagé de vue.

### 2.2 La règle d'affichage (`Views/Capture/Pill/SessionPillPresentation.swift`)

Copie de l'idée de `CaptureCore/PillMode.swift` : une **fonction pure** décide, jamais la
vue ni le contrôleur.

```swift
enum SessionPillMode: String { case always, sessionOnly, never }   // toujours / séance seulement / jamais
struct SessionPillConditions { var hasActiveMeeting, isSessionFullscreen, isRecording: Bool }
func shouldPresentPill(mode:conditions:isAppActive:) -> Bool
func sessionPillPanelHeight(hasConfirmation:isEditingNote:) -> CGFloat
```

- `.never` → jamais. Sans réunion active → jamais (une pastille sans chrono ni source ne
  dit rien).
- `.sessionOnly` (défaut) → plein écran de séance, **ou** enregistrement en cours alors que
  OneToOne n'est pas au premier plan (`NSApp.isActive == false`).
- `.always` → dès qu'une réunion est active.

### 2.3 Le panneau (`Views/Capture/Pill/SessionPillPanelController.swift`)

Copie adaptée de `PillPanelController` : `NSPanel [.borderless, .nonactivatingPanel]`,
`level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
`isMovableByWindowBackground`, vue hébergée bâtie **une seule fois**, état porté par des
objets `@Observable` (mode, confirmation, note) et non par des `@State`, observation par
`withObservationTracking` **réarmé**, magnétisation par débounce de 250 ms sur
`didMoveNotification`, `snap` gardé contre sa propre notification, **un seul panneau
agrandi** (`sessionPillPanelHeight`), coin persisté (`AppSettings.sessionPillCorner`).

### 2.4 Le contenu (`FloatingPill.swift`)

Copie de la mise en page de Teams-Capture, adaptée : `TimelineView(.periodic)` pour le
chrono (le `t` se calcule depuis une horloge, aucune observation ne le rafraîchirait),
point pulsant réarmé par `onChange(of: isRecording)`, `PrimaryButtonStyle` existant.
`✎ Note` et `＋ Action depuis la capture` sont **propres à OneToOne** (Teams-Capture n'a ni
notes ni actions et refusait un bouton mort).

### 2.5 Le pilotage (`SessionPillModel.swift` + `MeetingPillTarget.swift`)

Le critère n° 2 (« aucun aller-retour dans l'app ») se teste : `SessionPillModel` parle à un
**protocole** `SessionPillTarget`, doublé dans les tests. Le double compte les appels à
`activateApp()` — le test exige **zéro**. L'implémentation réelle
(`MeetingPillTarget`) délègue à `CaptureSessionCoordinator.captureNow()`,
`CaptureNoteInsertion` (lot 7), `MeetingNoteStore.append` et `ActionComposerService`.

L'OCR arrive après l'écriture : la confirmation part avec
`ocrLine == nil` (« Texte en cours d'extraction… ») et un **sondage** court
(intervalle et échéance injectés) la complète dès que la première ligne existe.

### 2.6 Raccourcis globaux (`Services/Capture/CaptureHotkeys.swift`)

`GlobalHotkeyService` (Carbon, signature `ONET`) est **réutilisé** tel quel. Deux leçons de
`GlobalHotKey.swift` reprises : l'échec d'enregistrement (`register` rend déjà `false`) est
**publié** (`CaptureHotkeyFailures.shared`) et affiché dans les réglages ; le registre ne
retient pas d'instance. `⌥` enfoncé au moment du `⌘⇧S` bascule sur le tracé de zone.

### 2.7 Zone à la souris (`Views/Capture/RegionSelectorWindow.swift`)

`NSPanel` plein écran, `level = .screenSaver`, fond `scrim`, tracé à la souris. La géométrie
est pure (`RegionSelection.rect(from:to:in:)` → `NormalizedRect`, origine haut-gauche comme
`NormalizedRect`), la fenêtre n'est qu'un capteur. Le rectangle ouvre une session
`CaptureSource.region` avec ce `crop` (`CaptureSessionCoordinator+Pill.swift`).

## 3. Tâches (TDD : le test d'abord, `swift build` avant chaque commit)

| # | Tâche | Tests |
| --- | --- | --- |
| 1 | `ScreenCorner` copié + ses 5 tests portés | `ScreenCornerTests` |
| 2 | `SessionPillPresentation` : modes, `shouldPresentPill`, hauteur du panneau | `SessionPillPresentationTests` |
| 3 | `ActiveMeetingRegistry` : règle pure + poignées | `ActiveMeetingRegistryTests` |
| 4 | `CaptureHotkeys` : specs `⌘⇧S`/`⌘⇧N`, libellé d'échec, registre des échecs | `CaptureHotkeysTests` |
| 5 | `SessionPillModel` + `SessionPillTarget` : chaîne de capture, note, action, OCR | `SessionPillModelTests` |
| 6 | `MeetingPillTarget` réel (coordinateur, notes, actions) | `SessionPillTargetIntegrationTests` |
| 7 | Jetons pastille dans `One2OneTokens` | `One2OneTokensTests` (complété) |
| 8 | `FloatingPill` + `SessionPillPanelController` (aucun test de panneau réel) | — |
| 9 | `.sessionPill(...)` sur `MeetingSpaceView`, contrôleur créé dans `OneToOneApp` | — |
| 10 | Réglages : mode + deux cases + message d'échec | — |
| 11 | `RegionSelection` pur + `RegionSelectorWindow` | `RegionSelectionTests` |
| 12 | `STATUS.md`, `swift test` complet, PR | — |

## 4. Ce que le lot ne fait pas

- Aucune recette graphique (consigne du 2026-09-07 : une passe dédiée pilote le bureau).
  La procédure est écrite dans `STATUS.md`.
- Aucun test ne crée de `NSPanel` réel ni n'enregistre de raccourci Carbon.
- La zone à la souris est capturée sur l'**écran principal** (`SessionConfiguration` ne
  porte pas d'identifiant d'écran) : écart noté.
