# Lot 16 — Atelier : socle des planches et mode Croquis (6a partiel)

**Date :** 2026-09-07 · **Branche :** `feat/refonte-lot-16-atelier-socle` (base `feat/refonte-lot-3-rail-actions`)
**Écran de référence :** `docs/superpowers/specs/refonte-2026-09/ecrans/6a-atelier-planche.png` (fait foi)
**Spec :** `specs-one2one.md` §7.1, §7.2, §7.4 · **Plan directeur :** §5 lot 16, D6, D11
**ADR :** `docs/adr/2026-09-07-moteur-de-planches-excalidraw-embarque.md`

Tout est derrière `AppSettings.workshopEnabled`, défaut `false`.

## Carte des fichiers

**Nouveaux (à moi seul)**

| Fichier | Rôle |
| --- | --- |
| `Scripts/build-excalidraw-bundle.sh` | régénère le bundle, versions épinglées |
| `Scripts/excalidraw-entry.jsx` | point d'entrée React, `window.oneToOneBoard` |
| `Scripts/excalidraw-esbuild.mjs` | construction + allègement (traductions, Mermaid) |
| `OneToOne/Resources/Whiteboard/*` | bundle commité + licence + versions |
| `OneToOne/Services/Workshop/WhiteboardResourceLocator.swift` | localise le bundle (dev + `.app`) |
| `OneToOne/Services/Workshop/WhiteboardHTML.swift` | `page()` : CSP + JS/CSS inlinés |
| `OneToOne/Services/Workshop/WhiteboardBridge.swift` | protocole + double de test |
| `OneToOne/Services/Workshop/BoardStore.swift` | chemins, debounce, index, duplication |
| `OneToOne/Services/Workshop/BoardModeRule.swift` | « changer de mode = nouvelle planche sauf vide » |
| `OneToOne/Views/Meeting/Workshop/WorkshopState.swift` | `@Observable` : `WKWebView` + planche active |
| `OneToOne/Views/Meeting/Workshop/WhiteboardWebView.swift` | `NSViewRepresentable` + `WKScriptMessageHandler` |
| `OneToOne/Views/Meeting/Workshop/WorkshopSpaceView.swift` | grille `52 | 1fr | 314` |
| `OneToOne/Views/Meeting/Workshop/WorkshopToolbar.swift` | 2ᵉ ligne 32 px |
| `OneToOne/Views/Meeting/Workshop/WorkshopToolPalette.swift` | palette verticale 52 px |
| `OneToOne/Views/Meeting/Workshop/WorkshopDock.swift` | dock 314 px, 3 onglets |
| `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot16.swift` | jeu de démonstration atelier |
| `Tests/Whiteboard*Tests.swift`, `Tests/Board*Tests.swift`, `Tests/Workshop*Tests.swift` | |

**Partagés (une touche minimale chacun, conventions anti-conflit)**

| Fichier | Modification |
| --- | --- |
| `MeetingScreenModel.swift` | **une ligne** : `var workshop = WorkshopState()` en fin de type |
| `Views/Meeting/Spaces/MeetingSpaceView.swift` | **une branche** `if estAtelier { WorkshopSpaceView(...) }` |
| `Views/Meeting/MeetingTopChromeBar.swift` | badge `ATELIER` + pilule `● Local · hors ligne` |
| `Models/AppSettings.swift` | `var workshopEnabled: Bool = false` |
| `Views/SettingsView.swift` | un `Toggle` |
| `Services/Maintenance/StorageStatsService.swift` | `boardsBytes`/`boardsCount` |
| `Services/BackupService.swift` | `BoardDTO` + `MeetingDTO.boards` (optionnel) |
| `Views/Menus/MeetingCommands.swift` | une ligne d'appel du semis atelier |
| `STATUS.md` | ma section en tête |

## Tâches (TDD : le test d'abord, `swift build` avant chaque commit)

### 16a — Socle

1. **ADR + bundle.** Écrire l'ADR (D6, alternatives, conséquences). Écrire les trois scripts,
   lancer la construction, vérifier la taille et l'absence de base réseau interrogeable. Commit.
2. **`WhiteboardResourceLocator`.** Tests : le bundle et le CSS existent dans `Bundle.module`
   (ressources **aplaties** à la racine par `.process("Resources")`) ; `packagedResourceURL`
   couvre la disposition du `.app`. Copier la structure de `MermaidResourceLocator`.
3. **`WhiteboardHTML.page()`.** Tests : CSP exacte présente ; aucun `<script src>`/`<link href>` ;
   toute URL de fonte est `data:` ; aucune des bases réseau interrogeables ; le JS et le CSS sont
   bien inlinés ; `window.oneToOneBoard` est mentionné.
4. **`WhiteboardBridge`.** Protocole `async` + `WhiteboardBridgeDouble` (enregistre les appels,
   rend une scène programmable). Tests : la séquence charger → modifier → exporter.
5. **`BoardStore`.** Tests purs sur dossier temporaire : chemins
   `boards/<stableID>.excalidraw.json` / `.png` ; écriture de scène ; debounce vignette 5 s
   (horloge injectée) ; renumérotation d'`index` au réordonnancement et à la suppression ;
   duplication (nouveau `stableID`, `index` +1, titre « … (copie) », scène copiée).
6. **`BoardModeRule`.** Tests : mode identique → même planche ; planche vide → conversion sur
   place ; planche non vide → nouvelle planche à l'index suivant.
7. **`StorageStatsService` + `BackupService`.** Tests : `boards/` compté ; aller-retour d'un
   `BoardDTO` (scène + vignette) sans perte.

### 16b — Écran 6a

8. **`AppSettings.workshopEnabled` + `Toggle`** dans `SettingsView` (section « Fonctionnalites IA »
   n'est pas la bonne : la plus proche est « Capture d'écran » → en réalité une nouvelle ligne dans
   la section existante la plus proche du sujet, cf. code). Test : défaut `false`.
9. **`WorkshopState`** (`@Observable`, `@MainActor`) : planche active, outil, couleur, épaisseur,
   onglet du dock, `WKWebView` mémorisé, `lastChangeAt`. Test : un seul `WKWebView` par réunion.
10. **`WhiteboardWebView`** + `WhiteboardWebBridge` (l'implémentation réelle du protocole).
11. **`WorkshopToolbar`** : segment de mode, 5 couleurs (anneau blanc + contour sur l'active),
    3 épaisseurs, `Planche n sur m · dernière modif. il y a Xs` (`TimelineView`),
    `Exporter PNG / SVG` (`NSSavePanel`). Tests purs sur les libellés et le formatage du délai.
12. **`WorkshopToolPalette`** : 9 outils 32×32 rayon 7, actif `ink/1` plein, `↺ ↻` en pied.
13. **`WorkshopDock`** : onglets `Planches n / Captures n / Pièces n` (les deux derniers portent une
    invite « arrive au lot 17 » non vide, testée), liste (vignette 60×40, mode, titre éditable,
    `mm:ss · auteur`, active bordée `workshop` sur `workshopBg`), `＋ Planche`, `Dupliquer`,
    réordonnancement par glisser, pied assistant + `⌘K`.
14. **`WorkshopSpaceView`** : grille `52 | 1fr | 314`, fond `#fdfcfa`, zoom molette/`⌘±`,
    `⇧⌘0` ajuster. Branchement dans `MeetingSpaceView` et badge/pilule dans `MeetingTopChromeBar`.
15. **Semis** `RefonteDemoSeed+Lot16` : réunion atelier 62 min, 4 participants, 4 planches avec
    scènes minimales reproduisant les boîtes de la capture. Tests : idempotence, 4 planches,
    fichiers de scène écrits.
16. **`swift test` complet**, recette, `STATUS.md`, PR.

## Ce que le lot ne fait pas

Modes Schéma et Manuscrit *complets* (bibliothèque de formes, pression, surligneur, lasso),
onglets `Captures`/`Pièces` du dock, section `SUR CETTE PLANCHE`, `＋ Action depuis la sélection`,
`Épingler à mm:ss`, légende d'assistant, planche de séance 6b, export `.drawio` — lots 17 et 18.
