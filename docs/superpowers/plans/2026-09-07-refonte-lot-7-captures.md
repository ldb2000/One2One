# Lot 7 — Captures Teams / Zoom : sélecteur de source, état visible, bande de captures

**Écran de référence :** `docs/superpowers/specs/refonte-2026-09/ecrans/4a-capture-selecteur.png`
**Spec :** §5.1, §5.2, §5.3, §1.4 (`⌘⇧S`), critères chantier 4 n° 1, 3, 4.
**Programme :** §2.5 (référence Teams-Capture), §3 (`Capture`), §4 (D7), §5 lot 7 tâches 0–7.
**Branche :** `feat/refonte-lot-7-captures`, sur `fix/refonte-1to1-window-crash`.

## Ce qui existe déjà (à ne pas réécrire)

| Acquis | Où |
| --- | --- |
| Moteur de capture (empreinte, polling, détecteur, anti-doublon, OCR détaché, jetons de session) | `Services/SlideCapture/**`, `Services/ScreenCaptureService.swift` |
| `SlideCapture.t / sourceRaw / triggerRaw`, `CaptureSource`, `CaptureTrigger` | lot 0B, `Models/MeetingModels.swift` |
| Marqueur carré de capture sur la frise (`kind: .capture`) | lot 2, `AudioTimelineStrip`, `MeetingTimelineMarkers` |
| Jeton `captureMarker #3d5180` | lot 0A, `One2OneTokens.swift:99` |
| Pilule `◫ mm:ss` d'une action issue d'une capture | lot 3, `ActionCardEditing.libelleSource` |
| Onglet `Captures` du tiroir Ressources, `ResourceItem(SlideCapture)` | lot 6 |
| Doublures de test `ScriptedFrameSource`, `FailingFrameSource`, `SuspendingFrameSource`, `GatedOCR` | `Tests/ScreenCaptureServiceTestDoubles.swift` |

Le lot 7 **complète** : profils par type, périodique, `acknowledge`, `captureNow`, catalogue de
sources, popover 346 px, pilule d'état, bande de vignettes, carte de capture dans une note.

## Tâches

### 1. `CaptureProfile` par type de réunion (tests d'abord)
`Services/SlideCapture/CaptureProfile.swift` : copie de la table de `MeetingType.swift` de
Teams-Capture, transposée sur `MeetingKind` (`work` = Architecture, `manager` = 1:1 Manager).
`SlideCaptureSettings.detectsAutomatically` / `periodicCapture` / `init(meetingKind:)`.
`captureHint` par type (affiché sous les bascules).
Tests : `Tests/CaptureProfileTests.swift` — Globale/Projet auto normal, 1:1 et Note faible sans
auto, Architecture élevée, Atelier élevée + 2 min ; `periodicCapture` n'existe pas sans
`detectsAutomatically`.

### 2. `SlideDetector.acknowledge`
Port du delta Teams-Capture : pose `recorded` (si inconnu), `acknowledged`, `previous`, désarme.
Tests dans `Tests/SlideDetectorTests.swift` : après un `acknowledge`, le tick stable suivant ne
réécrit pas le même contenu (preuve par mutation : retirer `armed = false` fait échouer) ; un
`acknowledge` avant le premier tick n'oblige pas à repasser par `.settling`.

### 3. `TunedField`
`Services/SlideCapture/CaptureTuning.swift` : `CaptureTuning` (`Set<TunedField>` + application
d'un profil qui **épargne** les champs réglés à la main). Fonction pure.
Tests : changer de type ne réécrit pas un champ touché ; réécrit les autres.

### 4. `ScreenCaptureService` : source, trigger, `t`, périodique, `captureNow`
- `SessionConfiguration` + `source: CaptureSource`, `detectsAutomatically`, `periodicCapture`.
- `beginSession(..., timecode:)` : fournisseur de `t` (le `MeetingPlayhead` de la réunion, jamais
  l'horloge de session).
- `now: () -> Date` injectable ; `lastWriteAt` ; l'échéance **arme**, le premier tick non
  `.settling` écrit (`trigger: .interval`).
- `captureNow()` : `acknowledge` **avant** l'écriture, marche boucle arrêtée, ne touche pas
  `state`, publie `lastError`. `snapshot()` y délègue.
- `pauseCause` (`sourceLost` / `failure`) → `isSourceLost`, sans dialogue.
- `lastError` remis à zéro sur **tous** les chemins de succès.
- `windowID == 0` ⇒ `DisplayFrameSource` (écran entier) dans la fabrique par défaut.
Tests : `Tests/CapturePortedCoordinatorTests.swift` (transposition de
`CaptureCoordinatorTests`) — détection coupée n'écrit rien mais signale la fenêtre disparue ;
l'échéance force une écriture sur contenu inchangé ; une capture manuelle repousse l'échéance ;
rien pendant le mouvement puis une seule écriture au premier tick stable ; `t` vient du playhead ;
`trigger`/`source` écrits sur `SlideCapture` ; tick en vol pendant `finish()` n'écrit rien.

### 5. `DisplayFrameSource`
`Services/SlideCapture/DisplayFrameSource.swift` : `SCDisplay` principal, mêmes traductions
d'erreur que `WindowFrameSource`. Non testé contre ScreenCaptureKit (convention du dépôt).

### 6. `CaptureSourceCatalog` (pur)
`Services/CaptureSourceCatalog.swift` : `CaptureSourceOption {source, badge, title, subtitle,
windowID, isActive}` construit depuis `[ShareableWindow]` + titre de fenêtre Teams + nom du
partageur + « le détecteur bouge ». Zoom par bundle `us.zoom.xos`. Écran entier toujours présent.
Tests : `Tests/CaptureSourceCatalogTests.swift` — Teams avec réunion → `Réunion · partage de
Sylvain en cours` + actif ; Teams lancé sans réunion → `Aucune réunion active`, inactif ; Zoom
absent → ligne inactive ; ordre Teams, Zoom, Écran ; l'écran est toujours actif.

### 7. `CaptureState`
`Views/Meeting/Capture/CaptureState.swift` (`@Observable`) : source choisie, options, bascules,
`showPopover`, `selectedCaptureID`, `dejaConfigure`. Dérivations pures pour le critère n° 1
(`pillLabel`, `pillTone`, `counter`) — testables sans vue.
Une ligne dans `MeetingScreenModel` : `var capture = CaptureState()`.
Tests : `Tests/CaptureStateTests.swift` — état armé/source/compteur lisibles sans menu ;
`⌘⇧S` la première fois ouvre le sélecteur, ensuite capture directement.

### 8. `CaptureSourcePopover` 346 px
`Views/Meeting/Capture/CaptureSourcePopover.swift` : reprise de `SourcePopover.swift` (vignette
44×30, libellé, sous-titre, point `ok`, bordure `action` sur la sélection), les deux bascules
(la première indisponible + explication si la source est inactive), la mention de confiance,
`Capturer maintenant` (`PrimaryButtonStyle`).
Jeton `capturePopoverWidth = 346` dans `One2OneTokens`.

### 9. Barre du haut : pilule d'état
`MeetingTopChromeBar.captureButton` remplacé : `● Capture · <Source> n ⌄` (`okBg` bordé `ok`),
`Source perdue` (`warnBg` + lien de reconfiguration), bouton neutre `Capture` sinon. Le chevron
rouvre le sélecteur.

### 10. Frise : dernier marqueur, taille, légende
`Services/Meeting/MeetingTimelineMarkers+Captures.swift` (pur) : `dernierT(_:)`, `legende(_:)`,
`captureMarkerSize = 12`. `AudioTimelineStrip` : le carré de capture passe à 12 px, le dernier
en `action`, légende `■ = capture` après le timecode de fin.
Tests : `Tests/CaptureTimelineMarkersTests.swift` — une capture sans `t` n'a pas de marqueur ;
chaque capture horodatée en a un ; le dernier est désigné ; pas de légende sans capture.

### 11. `CapturesStrip`
`Views/Meeting/Capture/CapturesStrip.swift` + `CaptureThumbnailCache.swift` (cache mémoire, clé =
chemin + mtime) + `CaptureStripModel.swift` (pur : tuiles triées, légende
`mm:ss · auto|⌘⇧S|2 min`, invites de bande vide par type, lignes de la colonne d'état).
`SlideCapture.includeInReport` (colonne neuve à défaut `false`, migration légère).
Monté en pied de colonne principale par **une ligne** de `MeetingLiveSpace`.
Tests : `Tests/CaptureStripModelTests.swift`.

### 12. Carte de capture dans une note
`Views/Meeting/Spaces/Notes/TimedNotesColumn+Capture.swift` : `56×36` + titre + 1re ligne d'OCR +
`Agrandir`. Résolution de la capture depuis `sourceRef {capture, stableID, t}` (fonction pure
`CaptureNoteCard.capture(for:in:)`). Un crochet de trois lignes dans `TimedNotesColumn`.
Insertion depuis la bande (`＋ Note`).
Tests : `Tests/CaptureNoteCardTests.swift` — la note porte le `sourceRef` ; référence morte →
pas de carte ; 1re ligne d'OCR.

### 13. OCR cherchable (critère n° 4)
`rebuildAttachmentText` existant + `TextChunker` + `BM25Index` : test qui prouve qu'un chunk est
créé depuis l'OCR et que la requête le trouve — **sans** appeler `reindexAttachment` (MLX).

### 14. `⌘⇧S`, retraits, semis
`MeetingMenuActions.captureNow` + `MeetingMenuItem.captureNow`, `MeetingCommands` (`⌘⇧S`).
Suppression de `MeetingSlidesPopover.swift` (plus d'appelant depuis le lot 6) et de
`ScreenCaptureConfigView.swift` (remplacé par le popover) ; `MeetingView` : retraits seulement.
`Services/Debug/Seed/RefonteDemoSeed+Lot7.swift` : 3 captures `04:12 auto`, `08:55 auto`,
`12:08 ⌘⇧S`, PNG factices CoreGraphics, OCR `« Reprise AP : 3 j-h · Marine : 21 000 € »`.

## Invariants

- Aucun test ne touche ScreenCaptureKit, MLX ni WebKit : `FrameSource` doublé, `reindex` injecté.
- Aucune couleur ni largeur hors `One2OneTokens`.
- Le code de Teams-Capture est **copié** avec ses tests, jamais lié.
- `swift build` avant chaque commit, `swift test` complet vert avant la PR (réf. 2 402 tests).
