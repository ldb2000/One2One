# Lot 6 — Ressources en séance : tiroir, « À l'écran », épinglage

**Date :** 2026-09-07 · **Branche :** `feat/refonte-lot-6-ressources` (sur
`feat/refonte-lot-3-rail-actions`)
**Programme :** `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 6 »
**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §4.1, §4.2, §8, §1.4
**Capture qui fait foi :** `docs/superpowers/specs/refonte-2026-09/ecrans/3a-tiroir-ressources.png`

## Décisions déjà prises (programme §4)

- **D5 validée** : copie, jamais référence. Les `MeetingAttachment` existants sont copiés
  **paresseusement** à la première ouverture de l'espace Ressources si la source existe
  encore, sinon marqués `orphelin`. ADR à écrire.
- Colonnes déjà créées au lot 0B : `scopeRaw`, `mimeType`, `byteCount`, `addedByName`,
  `pinnedAtT`, `citationCount`.
- Aucune nouvelle version de schéma : seules des colonnes à valeur par défaut.

## Ce qui existe et sert de base

| Élément | Fichier | Rôle |
| --- | --- | --- |
| `MeetingAttachment` (+ colonnes cibles) | `Models/MeetingModels.swift:245` | modèle |
| `ProjectAttachment` (copié, `resolvedURL()`) | `Models/Project.swift:155` | pièces du projet |
| `SlideCapture` (`t`, `source`, `trigger`) | `Models/MeetingModels.swift:209` | captures |
| `AttachmentImporter` (`Bucket.project`) | `Services/AttachmentImporter.swift` | copie disque |
| `MeetingAttachmentService.importDocument` | `Services/MeetingAttachmentService.swift` | import + RAG |
| `MeetingPlayhead` (`t`, `seek`, `Marker`) | `Services/Live/MeetingPlayhead.swift` | axe temps |
| `MeetingTimelineMarkers.markers(for:)` | `Services/Meeting/MeetingTimelineMarkers.swift` | repères de frise, **un seul appelant** (`MeetingLiveSpace.swift:79`) |
| `MeetingNoteStore` (`append`, `nextOrderIndex`) | `Services/MeetingNoteStore.swift` | notes horodatées |
| `SourceRef` (`kind/stableID/t`, 3 colonnes plates) | `Models/SourceRef.swift` | chaîne de citation |
| Primitives `SectionLabel`/`Chip`/`Pill`/`SegmentedMode` | `Views/DesignSystem/Components/Refonte/` | rendu |
| `One2OneToken.resourcesDrawerWidth = 396` | `Views/DesignSystem/One2OneTokens.swift` | géométrie |

## Carte des fichiers

**Créés**

- `docs/adr/2026-09-07-pieces-copiees-jamais-referencees.md`
- `OneToOne/Services/AttachmentCopyPolicy.swift` — pur : dossier de destination, MIME,
  `kind`, poids lisible, type de vignette.
- `OneToOne/Services/AttachmentMigration.swift` — migration paresseuse + état orphelin.
- `OneToOne/Services/AttachmentLinkImporter.swift` — URL collée → titre, sans réseau.
- `OneToOne/Services/AttachmentPinning.swift` — épingler / citer / `pinnedAttachments`.
- `OneToOne/Services/AttachmentReportOptions.swift` — les 3 cases du pied, en JSON.
- `OneToOne/Services/ResourceItem.swift` — adaptateur pur des trois sources + filtres.
- `OneToOne/Services/MeetingSharingState.swift` — état de partage dérivable, pur.
- `OneToOne/Services/Meeting/MeetingTimelineMarkers+Pins.swift`
- `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot6.swift`
- `OneToOne/Views/Meeting/Resources/ResourcesState.swift`
- `OneToOne/Views/Meeting/Resources/ResourcesDrawer.swift`
- `OneToOne/Views/Meeting/Resources/ResourceTile.swift`
- `OneToOne/Views/Meeting/Resources/ResourceTypeIcon.swift`
- `OneToOne/Views/Meeting/Resources/ResourceDropZone.swift`
- `OneToOne/Views/Meeting/Resources/ReportAttachmentFooter.swift`
- `OneToOne/Views/Meeting/Resources/ResourceImportCoordinator.swift`
- `OneToOne/Views/Meeting/Resources/OnScreenCard.swift`
- `OneToOne/Views/Meeting/Resources/DocumentPreview.swift`
- `OneToOne/Views/Meeting/Resources/AnnotationOverlay.swift`
- `OneToOne/Views/Meeting/Resources/PinnedInSessionStrip.swift`
- tests : `Tests/AttachmentCopyPolicyTests.swift`, `Tests/AttachmentCopyImportTests.swift`,
  `Tests/AttachmentMigrationTests.swift`, `Tests/ResourceItemTests.swift`,
  `Tests/AttachmentLinkImporterTests.swift`, `Tests/ResourcesStateTests.swift`,
  `Tests/AttachmentReportOptionsTests.swift`, `Tests/MeetingSharingStateTests.swift`,
  `Tests/AttachmentPinningTests.swift`, `Tests/StorageStatsDocumentsTests.swift`

**Modifiés** (partagés — au minimum, cf. conventions anti-conflit)

- `Models/MeetingModels.swift` : `stableID` sur `MeetingAttachment` (colonne optionnelle).
- `Models/OtherModels.swift` : `reportAttachmentOptionsJSON` sur `Meeting`.
- `Services/AttachmentImporter.swift` : cas `.meetingDocuments(meetingStableID:)`.
- `Services/MeetingAttachmentService.swift` : copie + métadonnées, liens, captures.
- `Services/Maintenance/StorageStatsService.swift`, `OrphanCleanupService.swift`
- `Services/BackupService.swift` : DTO enrichi (champs optionnels).
- `Views/Meeting/MeetingScreenModel.swift` : **une ligne** (`var resources`).
- `Views/Meeting/Spaces/MeetingSpaceView.swift` : **deux** (overlay tiroir + `onDrop`).
- `Views/Meeting/Spaces/MeetingResourcesSpace.swift` : recomposé.
- `Views/Meeting/Spaces/MeetingLiveSpace.swift` : **une ligne** (repères + épingles).
- `Views/Meeting/MeetingTopChromeBar.swift` : la pilule de partage uniquement.
- `Views/MeetingView.swift` : **retraits** + câblage du coordinateur.
- `Views/Menus/{MeetingCommands,MeetingMenuActions}.swift` : `⌘⇧V`.

## Tâches

### 1 — ADR et plan
Écrire `docs/adr/2026-09-07-pieces-copiees-jamais-referencees.md` (contexte, décision,
alternatives, conséquences dont la migration paresseuse) et ce plan. Aucun code.

### 2 — `AttachmentCopyPolicy`, pure (tests d'abord)
`Tests/AttachmentCopyPolicyTests.swift` : sous-chemin `recordings/<uuid>/documents`,
nom horodaté `yyyyMMdd-HHmmss_<nom>` assaini, MIME depuis l'extension via `UTType`,
`kind` (pdf/pptx/docx/xlsx/image/markdown/text/link/capture/document), poids lisible
(`84 Ko`), type de vignette (`XLS`/`PDF`/`PNG`/`URL`/…) et son fond.
Puis `OneToOne/Services/AttachmentCopyPolicy.swift`.

### 3 — Copie systématique à l'import
`Tests/AttachmentCopyImportTests.swift` : import depuis un dossier temporaire → le
fichier est **sous `recordings/<uuid>/documents/`**, `byteCount` et `mimeType` sont
renseignés, `addedByName` vaut `AppSettings.ownerName`, `scope == .meeting` ; supprimer
l'original ne rend pas la pièce illisible.
`AttachmentImporter.Bucket.meetingDocuments(meetingStableID:)` ;
`MeetingAttachmentService.importDocument` copie **avant** d'insérer la ligne.

### 4 — Migration paresseuse et état orphelin
`Tests/AttachmentMigrationTests.swift` : pièce référencée dont la source existe → copiée,
`filePath` mis à jour, idempotent ; source absente → `isOrphan == true`, aucune exception ;
une pièce déjà copiée n'est pas retouchée.
`Services/AttachmentMigration.swift` + `stableID` sur `MeetingAttachment`.

### 5 — Maintenance et sauvegarde
`Tests/StorageStatsDocumentsTests.swift` : le nouveau dossier est compté.
`StorageStatsService` scanne `recordings/*/documents` ; `OrphanCleanupService` ignore
les pièces copiées (sous `Application Support/OneToOne`) ; `BackupService` ajoute les
six colonnes cibles en champs **optionnels** (les anciens JSON restent décodables).
`OrphanCleanupServiceTests` mis à jour.

### 6 — `ResourceItem`, adaptateur pur
`Tests/ResourceItemTests.swift` : les trois sources (`MeetingAttachment`,
`ProjectAttachment`, `SlideCapture`) produisent un `ResourceItem` ; les quatre filtres
(`Cette séance`, `Le projet`, `Captures`, `Liens`) sélectionnent ce qu'il faut ; les
compteurs `n séance` / `n projet` sont dérivés.

### 7 — Liens collés et pont vers les captures
`Tests/AttachmentLinkImporterTests.swift` : titre = dernier segment sinon domaine,
aucune requête réseau, `about:`/texte non-URL refusés, `kind == "link"`.
`Services/AttachmentLinkImporter.swift` + création de la pièce lien ;
les `SlideCapture` existantes remontent en `ResourceItem` (`kind: capture`), sans
duplication de ligne en base.

### 8 — `ResourcesState`, options du pied
`Tests/ResourcesStateTests.swift` (critère chantier 3 n° 1) : ouvrir le tiroir ne change
ni `space`, ni `mode`, ni `noteComposerFocusToken` ; déposer un fichier non plus.
`Tests/AttachmentReportOptionsTests.swift` : deux premières cases cochées par défaut,
round-trip JSON, JSON illisible → défauts.
`Views/Meeting/Resources/ResourcesState.swift`, `Services/AttachmentReportOptions.swift`,
`Meeting.reportAttachmentOptionsJSON`, **une ligne** dans `MeetingScreenModel`.

### 9 — Le tiroir
`ResourcesDrawer` (396 px), `ResourceTile`, `ResourceTypeIcon` (34 × 40), `ResourceDropZone`,
`ReportAttachmentFooter`. `MeetingResourcesSpace` recomposé : le **même** contenu en pleine
largeur. Bordure `accent/action` sur la pièce présentée, `À l'écran` plein.

### 10 — Les quatre ouvertures
Overlay dans `MeetingSpaceView` (colonne principale interactive), `onDrop` au niveau de la
fenêtre (une ligne), `⌘⇧V` (`MeetingMenuActions` + `MeetingCommands` + test), bouton
`Capture` → tiroir sur le filtre Captures. `ResourceImportCoordinator` reçoit le
`fileImporter` retiré de `MeetingView`.

### 11 — État de partage dérivable
`Tests/MeetingSharingStateTests.swift` (critère chantier 3 n° 2) : `n voient` = présents
moins soi, jamais négatif ; sans partage, pas de pilule. Puis la pilule dans
`MeetingTopChromeBar`.

### 12 — `OnScreenCard`
Nom + page courante, aperçu (`PDFKit` paginé, `NSImage`, sinon icône + « Aperçu
indisponible »), légende **sous** le document, boutons `Annoter` / `Épingler à mm:ss` /
`Arrêter le partage`.

### 13 — `Annoter`
Calque rectangle / flèche / texte au-dessus de l'aperçu, enregistré en PNG sous
`recordings/<uuid>/slides/` comme `SlideCapture` dérivée (`t` = playhead). Le fichier
source n'est **jamais** modifié.

### 14 — Épinglage, citation, jeu de démo
`Tests/AttachmentPinningTests.swift` (critère chantier 3 n° 3) : `pinnedAtT` posé,
`Meeting.pinnedAttachments` triées par `t`, puce `◫ <nom> · p.n` présente dans les notes
avec `sourceRef(kind: .capture, stableID:)`, `citationCount` incrémenté par `Citer` **et**
par l'épinglage, repère de frise via `MeetingTimelineMarkers+Pins`.
Bande `ÉPINGLÉ DANS LA SÉANCE` (chips horodatées, celle du moment en `accent/action`,
clic → `seek`). `Envoyer` = `NSSharingServicePicker`.
`RefonteDemoSeed+Lot6.swift` : 4 pièces de séance, 17 du projet, 2 épinglées.
STATUS + recette.

## Critères de sortie

- `swift build` propre (avertissements préexistants seuls).
- `swift test` complet vert, ≥ 1 931 tests.
- `OrphanCleanupServiceTests`, `IndexStatsServiceTests`, `BackupWithoutInterviewTests`,
  `SchemaV3MigrationTests` verts.
- Recette comparée à `3a-tiroir-ressources.png`, écarts dans `STATUS.md`.
