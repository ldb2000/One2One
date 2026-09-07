# Lot 17 — Atelier : modes Schéma et Manuscrit, pièces et captures

> **Pour les exécutants agentiques :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`.
> Les étapes sont des cases à cocher (`- [ ]`).

**But :** compléter l'écran `6a-atelier-planche.png` — les modes `diagram` et `ink` avec leur
palette, la section `SUR CETTE PLANCHE` (annotations, action, épinglage) et
`PIÈCES & CAPTURES` (copie locale verrouillée) — sur le socle du lot 16.

**Architecture :** toute la règle est **pure Swift** et testée contre `WhiteboardBridgeDouble` ;
la page Excalidraw ne reçoit que des ordres (`setLibrary`, `insertShape`, `moveElements`,
`setSelectionKind`, `insertImage`, `setPressure`). Les formes de la bibliothèque et
l'alignement sont calculés en Swift, pas délégués à Excalidraw : `excalidrawAPI` **n'expose
pas** `actionManager` (vérifié dans le bundle 0.18.1 — l'objet impératif ne porte que
`registerAction`), et une règle géométrique doit se tester sans WebKit.

**Pile :** SwiftUI, SwiftData, Swift Testing, WebKit (doublé), Excalidraw 0.18.1 embarqué.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §7.1, §7.2, §7.4, §8,
critères chantier 6 n° 2, 3, 4. Capture : `ecrans/6a-atelier-planche.png`.
Plan directeur : `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 lot 17.

## Contraintes globales

- Libellés UI et commentaires en **français**, symboles en anglais.
- Aucune couleur hors `One2OneToken` (règle du programme §7).
- Énum persistée SwiftData → `…Raw: String` + wrapper calculé.
- Image insérée : **copie locale**, `≤ 2 048 px` sur le grand côté, élément `locked: true`,
  jamais une référence au fichier d'origine (spec §7.4, §8, D5).
- Aucune requête réseau : la page garde sa CSP `default-src 'none'`.
- Aucun test ne charge WebKit (plan §8).
- Fichiers interdits : `Views/Capture/**`, `Services/Capture/**`, `OneOnOne/**`,
  `Services/Report/**`, `Rail/**`, `Notes/**`, `Review/**`, `Project/**`, `Session/**`.
  `MeetingTopChromeBar.swift` : **uniquement** la correction du badge.
- `WorkshopState` : nouvelles propriétés **en fin de type**.
- `swift build` avant chaque commit, `swift test` complet vert avant la PR.
- Aucune recette graphique, aucun lancement de l'application.

## Fichiers

| Fichier | Responsabilité |
| --- | --- |
| `Services/Workshop/BoardShapeLibrary.swift` (créé) | les 5 formes `.excalidrawlib`, dessinées en JSON Excalidraw |
| `Services/Workshop/BoardAlignment.swift` (créé) | alignement / répartition, pur |
| `Services/Workshop/BoardAnnotation.swift` (créé) | `customData.kind` : lecture, écriture, libellés |
| `Services/Workshop/InkPressure.swift` (créé) | normalisation de `NSEvent.pressure` + moniteur |
| `Services/Workshop/BoardImageInsertion.swift` (créé) | copie ≤ 2 048 px + élément `image` verrouillé |
| `Services/Workshop/WhiteboardBridge.swift` (modifié) | outils par mode, nouveaux appels, double |
| `Services/Workshop/BoardScene.swift` (modifié) | connecteurs liés, annotations |
| `Services/Meeting/MeetingTimelineMarkers+Boards.swift` (créé) | repère de planche épinglée |
| `Views/Meeting/Workshop/WorkshopPalette.swift` (modifié) | table pure `tools(for:)` / `shapes(for:)` |
| `Views/Meeting/Workshop/WorkshopToolPalette.swift` (modifié) | palette par mode |
| `Views/Meeting/Workshop/WorkshopBoardInspector.swift` (créé) | `SUR CETTE PLANCHE` |
| `Views/Meeting/Workshop/WorkshopAttachmentsSection.swift` (créé) | `PIÈCES & CAPTURES` |
| `Views/Meeting/Workshop/WorkshopDock.swift` (modifié) | montage des sections, onglets |
| `Views/Meeting/Workshop/WorkshopState.swift` (modifié) | orchestration (fin de type) |
| `Views/Meeting/Workshop/WhiteboardWebView.swift` (modifié) | menu contextuel natif, appels |
| `Views/Meeting/MeetingTopChromeBar.swift` (modifié) | **badge `ATELIER` non tronqué, rien d'autre** |
| `Scripts/excalidraw-entry.jsx` (modifié) | nouvelles fonctions du pont |
| `Resources/Whiteboard/excalidraw.bundle.js` (régénéré) | bundle recommité |
| `Services/Debug/Seed/RefonteDemoSeed+Lot17.swift` (créé) | jeu de démo |
| `Tests/WorkshopModesTests.swift` (créé) | modes, formes, alignement, pression |
| `Tests/WorkshopDockTests.swift` (créé) | annotations, action, épinglage, image |
| `Tests/WorkshopSpaceTests.swift` (modifié) | table des outils, invites du dock |

---

## Étape A — Modes (17a)

### Tâche 1 : table des palettes par mode

**Produit :** `WhiteboardTool` gagne `note`, `highlighter`, `ruler`, `lasso`, `selection`,
`connector` et perd `frame` ; `WorkshopPalette.tools(for: BoardMode) -> [WhiteboardTool]` et
`WorkshopPalette.shapes(for: BoardMode) -> [BoardShapeLibrary.Shape]`.

- [ ] Test : `tools(for: .sketch)` == les neuf outils de la spec §7.1 (crayon, rectangle,
      ellipse, flèche, ligne, texte, post-it, image, gomme) ; `.diagram` == sélection,
      connecteur, texte, gomme ; `.ink` == stylo, surligneur, gomme, règle, lasso ; chaque
      outil porte un libellé et un symbole non vides ; `shapes(for:)` est vide hors `.diagram`.
- [ ] Vérifier l'échec, implémenter, vérifier le vert, mettre à jour `nineTools`, commit.

### Tâche 2 : bibliothèque de formes

**Produit :** `BoardShapeLibrary.Shape` (`server`, `database`, `queue`, `actor`, `zone`),
`libraryJSON()`, `elements(for:at:)`.

- [ ] Test : `libraryJSON()` est un JSON `{"type":"excalidrawlib","version":2,"libraryItems":[…]}`
      de **cinq** items, chacun avec un `name` français et au moins deux éléments dont un texte ;
      `elements(for: .database, at: .init(x: 100, y: 50))` place la forme à ces coordonnées ;
      aucune couleur hors `WorkshopPalette`/`One2OneToken`.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 3 : alignement et répartition, purs

**Produit :** `BoardAlignment.Operation` (8 cas), `moves(scene:selectedIDs:operation:)`.

- [ ] Test : trois boîtes à x = 0/40/90 alignées à gauche donnent x = 0 ; centrées
      horizontalement partagent le même centre ; réparties horizontalement ont des écarts
      égaux ; moins de deux (align) ou trois (distribute) éléments ne produit **aucun**
      mouvement ; un identifiant inconnu est ignoré.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 4 : pression du stylet

**Produit :** `InkPressure.normalized(raw:isTablet:) -> Double?` (nil = souris → épaisseur
fixe), `InkPressure.strokeWidth(base:pressure:)`, `StylusPressureMonitor` à fabrique de
moniteur injectable.

- [ ] Test : `normalized(raw: 0.5, isTablet: false)` == nil ; `raw: 0` tablette == 0 ;
      `raw: 2` tablette borné à 1 ; `strokeWidth(base: 2, pressure: nil)` == 2 et croît avec
      la pression ; le moniteur doublé publie la dernière valeur et se retire à `stop()`.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 5 : nouveaux appels du pont

**Produit :** au protocole — `setLibrary(_:)`, `insertShape(_:)`, `selection()`,
`moveElements(_:)`, `setSelectionKind(_:)`, `insertImage(dataURL:fileID:width:height:)`,
`setPressure(_:)`, `setInkTool(_:)` ; le double les enregistre dans `calls`.

- [ ] Test : chaque appel s'enregistre une fois avec ses arguments ; `nextError` le fait
      échouer sans corrompre `calls`.
- [ ] Vérifier l'échec, implémenter (protocole, double, `WhiteboardWebBridge`), vérifier, commit.

### Tâche 6 : orchestration des modes

**Produit :** en fin de `WorkshopState` — la bibliothèque poussée au passage en `.diagram`,
`insert(shape:meeting:)`, `align(_:meeting:)`, `pressure`, et l'outil qui retombe sur le
premier de la palette du mode.

- [ ] Test : `requestMode(.diagram, …)` sur planche vide appelle `setMode(.diagram)` **puis**
      `setLibrary` ; `.ink` ne charge pas la bibliothèque ; changer de mode remplace l'outil ;
      `insert(shape: .server, …)` appelle `insertShape` ; `align(.left, …)` lit la sélection
      puis appelle `moveElements`, et ne l'appelle pas pour un seul objet sélectionné.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 7 : entrée JSX et régénération du bundle

- [ ] Étendre `makeBridge` : `setLibrary`, `insertShape`, `getSelection`, `moveElements`
      (avec `captureUpdate: "IMMEDIATELY"` pour que `↺` défasse l'alignement),
      `setSelectionKind`, `insertImage`, `setPressure`, `setInkTool` (surligneur = opacité 40,
      gomme, règle) ; `MODE_DEFAULTS.diagram` pose `isBindingEnabled` et
      `objectsSnapModeEnabled` ; la pression native remplace `pressures` du dernier tracé
      `freedraw` et pose `simulatePressure: false`.
- [ ] `bash Scripts/build-excalidraw-bundle.sh`, relever la taille,
      `swift test --filter WhiteboardHTML`.
- [ ] Commit du bundle et de l'entrée.

---

## Étape B — Dock (17b)

### Tâche 8 : annotations question / risque

**Produit :** `BoardAnnotation.Kind` (`question`, `risk`) avec `label`, `chipTone`, `color` ;
`BoardAnnotation.list(in:)` ; `BoardScene.scene(boxes:connectors:)` avec `annotation:`.

- [ ] Test : une scène avec `annotation: .risk` et `.question` se relit en deux annotations,
      dans l'ordre, avec le texte de la boîte (y compris porté par l'élément lié) ; une scène
      sans `customData` en rend zéro ; un `kind` inconnu est ignoré ; les connecteurs demandés
      portent `startBinding`/`endBinding`.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 9 : action depuis la sélection, épinglage

**Produit :** `WorkshopState.createAction(title:screen:meeting:context:)` (action avec
`sourceRef.kind == .board`), `pinActiveBoard(screen:meeting:context:)` (note « ◫ Planche n · titre »),
`MeetingTimelineMarkers.boardMarkers(for:)` + `allMarkersIncludingBoards(for:)`.

- [ ] Test : l'action apparaît dans `meeting.tasks` **sans rail monté**, porte
      `sourceRef.kind == .board`, le `stableID` de la planche active et le `t` de la tête de
      lecture ; un titre vide ne crée rien ; épingler pose une note horodatée contenant
      `◫ Planche` et le titre ; `boardMarkers` rend un repère par note de planche, trié.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 10 : insertion d'image copiée et verrouillée

**Produit :** `BoardImageInsertion.fittedSize(_:limit:)`, `copy(source:…)` vers
`recordings/<uuid>/boards/assets/<stableID>.png`, `element(fileID:size:at:)` (`locked: true`),
`WorkshopState.insertImage(from:meeting:context:)`.

- [ ] Test : `fittedSize(.init(width: 3000, height: 1500), limit: 2048)` == 2048 × 1024, une
      petite image n'est pas agrandie ; copier un PNG écrit sous `boards/assets/` et
      **supprimer l'original ne change rien** (critère n° 3) ; l'élément porte `locked == true`
      et un `fileId` local ; `insertImage` appelle le pont.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 11 : sections du dock et menu contextuel natif

- [ ] `SUR CETTE PLANCHE` : puce `warn`/`report`, `＋ Action depuis la sélection`,
      `Épingler à mm:ss`. `PIÈCES & CAPTURES` : `ResourceItem`, `Sur la planche` / `Insérer`,
      zone `Glissez un fichier — il est copié dans la réunion`
      (`AttachmentImporter.Bucket.meetingDocuments`). Onglets `Captures` / `Pièces` alimentés
      par `ResourceItem.filtered`, invite quand la liste est vide. `BoardWebView` (sous-classe
      de `WKWebView`) rend `menu(for:)` avec « Marquer comme question » / « Marquer comme
      risque ».
- [ ] Test : les lignes du dock sont produites par une fonction pure qui distingue « déjà sur
      la planche » ; le menu contextuel porte les deux titres français ; aucune invite n'est
      vide.
- [ ] Vérifier l'échec, implémenter, vérifier, commit.

### Tâche 12 : badge `ATELIER`, présence, jeu de démo, STATUS

- [ ] Badge : `.fixedSize()` sur `badgeAtelier` et priorité de compression au titre — le titre
      se comprime, le badge garde sa largeur intrinsèque. Rien d'autre dans ce fichier.
- [ ] Vérifier qu'aucun reliquat n'affiche la pilule de présence (D11).
- [ ] Semis : `Flux réseau` en `diagram` avec deux boîtes bleues et un connecteur lié,
      `Notes de Patrice` en `ink`, annotations `Jenkins…` risque / `Qui porte…` question,
      pièce `Archi_cible_Cléva.pdf` déposée par Yann, capture `21:10`.
- [ ] Test : le semis rend deux annotations, un connecteur lié, une pièce et une capture.
- [ ] `swift test` complet, STATUS daté, commit.
