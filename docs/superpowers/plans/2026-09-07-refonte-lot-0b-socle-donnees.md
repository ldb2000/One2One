# Lot 0B — Socle de données : schéma V3, axe temps, confidentialité

> **Pour les exécutants agentiques :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`
> ou `superpowers:subagent-driven-development` (TDD via `superpowers:test-driven-development`).
> Les étapes sont des cases à cocher (`- [ ]`).

**Objectif :** créer une fois pour toutes les tables du modèle cible (spec §1.3), la tête de
lecture partagée d'une réunion et le filtre unique de confidentialité, câblé aux cinq lecteurs
de texte existants.

**Architecture :** `SchemaV3` ajoute neuf `@Model` vides plus des colonnes à valeur par défaut sur
cinq modèles existants — donc migration légère, sans `MigrationStage` custom, comme V1→V2.
`MeetingPlayhead` devient l'unique propriétaire d'un `AudioPlayerService` par réunion
(`MeetingView` et `AudioWaveformEditor` en deviennent consommateurs). `ConfidentialityFilter`
porte la règle `isExportable(item, audience)` et `MeetingNoteStore` la met en forme ; les cinq
lecteurs (prompt de rapport, HTML, export markdown, chunks RAG, contexte des deux chats)
appellent ces deux services et ne réimplémentent rien.

**Pile technique :** Swift 6, SwiftUI, SwiftData (lightweight migration), Swift Testing
(`@Suite`/`@Test`), XCTest pour l'existant. Aucune dépendance SwiftPM nouvelle.

**Spécifications :**
- `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §2.2, §3, §4 (D1, D3, D4, D5, D9), §5 « Lot 0B », §7, §8
- `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §1.3, §3.2, §8

## Contraintes globales

- Énums persistées SwiftData : colonne `…Raw: String` + wrapper calculé (bug SwiftData).
- Identité externe : `stableID: UUID?` (optionnel, pour la migration légère) + `ensuredStableID`.
- Services : `enum` namespace de fonctions pures, ou `class` singleton `@MainActor .shared`.
- Migration **légère uniquement** : aucun champ supprimé, renommé, ni rendu non-optionnel sans défaut.
- `CurrentSchema` pointe sur la dernière `SchemaVN`. Les schémas antérieurs restent déclarés.
- Commentaires et libellés UI en **français**, symboles de code en **anglais**.
- Aucun test ne dépend de MLX, de ScreenCaptureKit, du réseau ni d'une session graphique.
- `swift build` avant chaque commit ; `swift test` complet vert avant la PR (≈ 1 655 tests).
- Commits conventionnels, un par tâche, avec `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Modifications de `MeetingView.swift` réduites au strict minimum (le lot 0A y travaille en parallèle).
- Interdit de toucher : `Views/DesignSystem/**`, `Resources/Fonts`, `Package.swift`, `Info.plist`,
  `Views/Meeting/MeetingScreenModel.swift`.

---

## Carte des fichiers

| Fichier | Rôle |
| --- | --- |
| `OneToOne/Models/MeetingNote.swift` (créé) | `@Model MeetingNote`, `MeetingNoteKind`, `MeetingSide` |
| `OneToOne/Models/Board.swift` (créé) | `@Model Board`, `BoardMode` |
| `OneToOne/Models/ProjectCardModels.swift` (créé) | `@Model ProjectMilestone`, `@Model ProjectContact`, `MilestoneState` |
| `OneToOne/Models/OneOnOneModels.swift` (créé) | `@Model OneOnOneThread/Commitment/OneOnOneAgendaItem/MoodEntry/OneOnOneObjective` + énums |
| `OneToOne/Models/SourceRef.swift` (créé) | `struct SourceRef`, protocole `SourceRefCarrying` + accesseur par défaut |
| `OneToOne/Models/SchemaVersions.swift` | `SchemaV3`, `CurrentSchema`, plan de migration |
| `OneToOne/Models/OtherModels.swift` | colonnes de `ActionTask` et `Meeting`, `textualContent` |
| `OneToOne/Models/MeetingModels.swift` | `MeetingKind.workshop`, colonnes de `MeetingAttachment` et `SlideCapture` |
| `OneToOne/Models/Project.swift` | `scopeText`, `tagsJSON` + façade `tags` |
| `OneToOne/Services/ConfidentialityFilter.swift` (créé) | `Audience`, `Visibility`, `Confidential`, `ConfidentialityFilter` |
| `OneToOne/Services/MeetingNoteStore.swift` (créé) | tri/regroupement/filtrage purs, bloc de contexte, import de `liveNotes` |
| `OneToOne/Services/Live/MeetingPlayhead.swift` (créé) | tête de lecture partagée + registre |
| `OneToOne/Services/AIReportService.swift` | seam `assembleTemplatePrompt`, bloc de notes filtré |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` | bloc HTML des notes filtré |
| `OneToOne/Services/ExportService.swift` | section markdown des notes filtrée |
| `OneToOne/Services/RAGService.swift` | seam `RAGIndexer.sourceText`, notes privées jamais chunkées |
| `OneToOne/Services/NoteFactory.swift` | garde sur les nouvelles relations |
| `OneToOne/Views/ChatbotView.swift` | `buildDatabaseContext` + bloc de notes `.projectTeam` |
| `OneToOne/Views/Meeting/MeetingChatView.swift` | `makePrompt` + bloc de notes `.projectTeam` |
| `OneToOne/Views/MeetingView.swift` | playhead au lieu de `AudioPlayerService`, `recordingStartedAt`, import des notes |
| `OneToOne/Views/AudioWaveformEditor.swift` + `AudioEditorSheet.swift` | consomment le lecteur du playhead |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | `compatibleTemplates` → `.workshop` |
| `Tests/SchemaV3MigrationTests.swift` (créé) | ouverture/réouverture d'un store SQLite temporaire |
| `Tests/MeetingPlayheadTests.swift` (créé) | `t`, `seek`, `follow`, `formatted`, registre |
| `Tests/ConfidentialityFilterTests.swift` (créé) | règles + les cinq flux |
| `Tests/MeetingNoteStoreTests.swift` (créé) | fonctions pures + import idempotent |
| `Tests/SwiftDataTests.swift` | liste explicite de modèles à compléter |

---

## Task 1 : `SourceRef` et les énums de confidentialité

**Fichiers :**
- Créer : `OneToOne/Models/SourceRef.swift`
- Créer : `OneToOne/Services/ConfidentialityFilter.swift`
- Test : `Tests/ConfidentialityFilterTests.swift`

**Interfaces produites :**
- `struct SourceRef: Codable, Hashable { enum Kind: String, Codable { transcript, note, capture, board }; var kind: Kind; var stableID: UUID; var t: Double? }`
- `protocol SourceRefCarrying: AnyObject { var sourceKindRaw: String? { get set }; var sourceStableID: UUID? { get set }; var sourceT: Double? { get set } }` + `var sourceRef: SourceRef?` par défaut
- `enum Audience { me, collaborator, manager, projectTeam, hr }`
- `enum Visibility: String, Codable, CaseIterable { `private`, shared, escalated }`
- `protocol Confidential { var visibility: Visibility { get } }`
- `enum ConfidentialityFilter { static func isExportable(_ item: some Confidential, for audience: Audience) -> Bool ; static func isIndexable(_ item: some Confidential) -> Bool ; static func audience(for kind: MeetingKind) -> Audience }`

- [ ] **Étape 1 : écrire les tests rouges des règles** dans `Tests/ConfidentialityFilterTests.swift`
  (suite « Confidentialité — la règle unique d'exportabilité ») : `private` exportable pour `.me`
  seulement ; `shared` pour `.me/.collaborator/.manager/.projectTeam` mais pas `.hr` ;
  `escalated` pour `.me/.manager/.hr` mais pas `.collaborator/.projectTeam` ; `isIndexable` vrai
  sauf pour `private` ; `audience(for:)` = `.collaborator` pour `.oneToOne`, `.manager` pour
  `.manager`, `.projectTeam` pour les cinq autres types (dont `.workshop`, ajouté en tâche 3).
- [ ] **Étape 2 : `swift test --filter ConfidentialityFilterTests`** → échec de compilation (types absents).
- [ ] **Étape 3 : écrire `SourceRef.swift` et `ConfidentialityFilter.swift`** avec les signatures
  ci-dessus. `isExportable` est une table `switch (visibility, audience)` exhaustive, sans `default`.
- [ ] **Étape 4 : `swift test --filter ConfidentialityFilterTests`** → vert. `swift build` propre.
- [ ] **Étape 5 : commit** `feat(refonte): SourceRef et filtre de confidentialité unique`.

---

## Task 2 : les neuf `@Model` et les colonnes ajoutées

**Fichiers :**
- Créer : `OneToOne/Models/MeetingNote.swift`, `Board.swift`, `ProjectCardModels.swift`, `OneOnOneModels.swift`
- Modifier : `OneToOne/Models/OtherModels.swift` (`ActionTask`, `Meeting`), `MeetingModels.swift`
  (`MeetingAttachment`, `SlideCapture`), `Project.swift`, `SchemaVersions.swift`, `Tests/SwiftDataTests.swift`
- Test : `Tests/SchemaV3MigrationTests.swift`

**Interfaces consommées :** `Visibility`, `Confidential`, `SourceRefCarrying` (tâche 1).

**Interfaces produites :**
- `MeetingNote(t:text:kind:visibility:)` avec `stableID`, `authorSide`, `orderIndex`, `createdAt`, `meeting`; conforme `Confidential`, `SourceRefCarrying`
- `Meeting.timedNotes: [MeetingNote]`, `Meeting.boards: [Board]`, `Meeting.recordingStartedAt: Date?`, `Meeting.notesMigrated: Bool`
- `ActionTask.priority: ActionPriority`, `.status: ActionStatus`, `.effortMinutes`, `.deferralCount`, `.carriedFromMeeting`, `.sourceRef`
- `MeetingAttachment.scope`, `.mimeType`, `.byteCount`, `.addedByName`, `.pinnedAtT`, `.citationCount`
- `SlideCapture.t`, `.source`, `.trigger`
- `Project.scopeText`, `Project.tags: [String]`
- `OneOnOneThread.commitments/agendaItems/moodEntries/objectives`, `Commitment`, `OneOnOneAgendaItem` conformes `Confidential`
- `SchemaV3`, `CurrentSchema = SchemaV3`

- [ ] **Étape 1 : écrire le test de migration rouge** `Tests/SchemaV3MigrationTests.swift` : store
  SQLite dans un dossier temporaire ouvert avec `Schema(versionedSchema: SchemaV2.self)`,
  insertion d'un `Meeting` + `ActionTask` + `MeetingAttachment`, `save`, libération du conteneur ;
  réouverture avec `Schema(versionedSchema: CurrentSchema.self)` + `migrationPlan: OneToOneMigrationPlan.self` ;
  vérifier que les trois lignes sont là et que `notesMigrated == false`, `recordingStartedAt == nil`,
  `status == .open`, `priority == .normal`, `deferralCount == 0`, `attachment.scope == .meeting`,
  `byteCount == 0`, `timedNotes.isEmpty`.
- [ ] **Étape 2 : `swift test --filter SchemaV3MigrationTests`** → échec (types absents).
- [ ] **Étape 3 : écrire les quatre fichiers de modèles** (champs de §3 du plan directeur,
  énums en `…Raw`, `stableID` + `ensuredStableID`, relations `.cascade` avec inverse depuis
  `Meeting`/`Project`/`OneOnOneThread`, `.nullify` sans inverse pour les liens de traçabilité
  vers `Meeting`).
- [ ] **Étape 4 : ajouter les colonnes** sur `ActionTask`, `Meeting`, `MeetingAttachment`,
  `SlideCapture`, `Project`. `ActionTask.priority` et `.status` sont des wrappers dont la
  **source de vérité reste** `isUrgent`/`isCompleted` (la colonne est un miroir requêtable
  synchronisé à l'écriture ; `dropped` n'existe que dans la colonne).
- [ ] **Étape 5 : `SchemaV3`** = `SchemaV2.models + [MeetingNote, Board, ProjectMilestone,
  ProjectContact, OneOnOneThread, Commitment, OneOnOneAgendaItem, MoodEntry, OneOnOneObjective]`,
  `CurrentSchema = SchemaV3`, `schemas` complété, `stages: []` documenté (V2→V3 n'ajoute que des
  tables et des colonnes à défaut). Compléter la liste explicite de `Tests/SwiftDataTests.swift`.
- [ ] **Étape 6 : `swift test --filter SchemaV3MigrationTests`** puis `swift test --filter SwiftData`
  → verts ; `swift build` propre.
- [ ] **Étape 7 : commit** `feat(refonte): schéma V3 — neuf modèles et colonnes du modèle cible`.

---

## Task 3 : `MeetingKind.workshop`

**Fichiers :**
- Modifier : `OneToOne/Models/MeetingModels.swift`, `OneToOne/Views/Meeting/MeetingTopChromeBar.swift:512`,
  `OneToOne/Services/AIReportService.swift:422`
- Test : `Tests/ConfidentialityFilterTests.swift` (cas `.workshop` déjà écrit en tâche 1)

- [ ] **Étape 1 : écrire le test rouge** dans `Tests/MeetingKindWorkshopTests.swift` :
  `MeetingKind(rawValue: "workshop") == .workshop`, `label == "Atelier"`, symbole SF non vide,
  et les six valeurs brutes historiques (`global`, `project`, `oneToOne`, `work`, `manager`,
  `note`) inchangées.
- [ ] **Étape 2 : `swift test --filter MeetingKindWorkshop`** → rouge.
- [ ] **Étape 3 : ajouter le cas** `case workshop = "workshop"` avec label « Atelier » et symbole
  `person.3.sequence` ; compléter les `switch` exhaustifs signalés par le compilateur —
  `compatibleTemplates` (`.workshop: .workshop`) et `AIReportService.defaultTemplate`
  (`case .workshop: templateKind = .workshop`).
- [ ] **Étape 4 : `swift build`** puis `swift test --filter MeetingKindWorkshop` → vert.
- [ ] **Étape 5 : commit** `feat(refonte): type de réunion Atelier`.

---

## Task 4 : `MeetingPlayhead`

**Fichiers :**
- Créer : `OneToOne/Services/Live/MeetingPlayhead.swift`
- Modifier : `OneToOne/Views/MeetingView.swift` (le `@StateObject player` seulement),
  `OneToOne/Views/AudioWaveformEditor.swift`, `OneToOne/Views/AudioEditorSheet.swift`
- Test : `Tests/MeetingPlayheadTests.swift`

**Interfaces produites :**
- `@Observable @MainActor final class MeetingPlayhead` : `let player: AudioPlayerService`,
  `enum Source { idle, recording(startedAt: Date), playback }`, `var now: () -> Date`,
  `private(set) var t: Double`, `var duration: Double`, `var isPlaying: Bool`, `var follow: Bool`,
  `var markers: [Marker]`, `var formatted: String`, `func beginRecording(startedAt:)`,
  `func beginPlayback()`, `func refresh()`, `func seek(to:)`,
  `static func mmss(_ t: Double) -> String`, `static func `for`(meeting:) -> MeetingPlayhead`

- [ ] **Étape 1 : écrire les tests rouges** `Tests/MeetingPlayheadTests.swift` (suite
  « Tête de lecture — l'axe temps d'une réunion », `@MainActor`, horloge injectée) :
  en enregistrement `t = now − startedAt` après `refresh()` ; `t` jamais négatif si l'horloge
  recule ; `seek(to:)` borne dans `0…duration` ; `follow` vaut `true` par défaut et se bascule ;
  `formatted` rend `04:12` pour 252 s et `00:00` pour 0 ; `mmss` d'une valeur > 1 h rend
  `1:05:00` ; `for(meeting:)` rend deux fois la même instance pour la même réunion et une
  instance distincte pour une autre.
- [ ] **Étape 2 : `swift test --filter MeetingPlayheadTests`** → rouge.
- [ ] **Étape 3 : écrire `MeetingPlayhead.swift`.** Le registre est un cache **fort borné**
  (les 4 dernières réunions demandées, LRU, `pause()` à l'éviction) : un cache faible se
  viderait immédiatement, `MeetingView` étant une `struct` qui ne peut retenir l'instance sans
  init explicite — fichier que le lot 0A réécrit en parallèle. Écart documenté dans `STATUS.md`.
- [ ] **Étape 4 : `swift test --filter MeetingPlayheadTests`** → vert.
- [ ] **Étape 5 : brancher les consommateurs.** `MeetingView` : supprimer
  `@StateObject private var player = AudioPlayerService()`, ajouter
  `private var playhead: MeetingPlayhead { MeetingPlayhead.for(meeting: meeting) }` et
  `private var player: AudioPlayerService { playhead.player }` (aucun autre changement : les
  sous-vues reçoivent déjà `player` en `@ObservedObject`) ; dans `startRecording()`, après
  `meeting.wavFilePath = url.path`, poser `meeting.recordingStartedAt` si `nil` et appeler
  `playhead.beginRecording(startedAt:)`. `AudioWaveformEditor` : remplacer son
  `@StateObject private var player` par un paramètre `@ObservedObject var player: AudioPlayerService` ;
  `AudioEditorSheet` passe `MeetingPlayhead.for(meeting: meeting).player`.
- [ ] **Étape 6 : `swift build`** propre, `swift test --filter Audio` vert.
- [ ] **Étape 7 : commit** `feat(refonte): tête de lecture partagée par réunion`.

---

## Task 5 : `MeetingNoteStore` — fonctions pures et import de `liveNotes`

**Fichiers :**
- Créer : `OneToOne/Services/MeetingNoteStore.swift`
- Modifier : `OneToOne/Models/OtherModels.swift` (`Meeting.textualContent`),
  `OneToOne/Services/NoteFactory.swift`, `OneToOne/Views/MeetingView.swift` (un seul appel)
- Test : `Tests/MeetingNoteStoreTests.swift`

**Interfaces consommées :** `MeetingNote`, `Visibility`, `Audience`, `ConfidentialityFilter`, `MeetingPlayhead.mmss`.

**Interfaces produites :**
- `enum MeetingNoteStore` : `static func sorted(_:) -> [MeetingNote]`,
  `static func grouped(by:_:) -> [MeetingNoteKind: [MeetingNote]]`,
  `static func filtered(_:kind:) -> [MeetingNote]`,
  `static func exportable(_:for:) -> [MeetingNote]`,
  `static func indexable(_:) -> [MeetingNote]`,
  `static func markdown(_:) -> String`,
  `static func contextBlock(for:audience:) -> String`,
  `static func defaultVisibility(for:) -> Visibility`,
  `@MainActor static func importLiveNotesIfNeeded(_:in:) -> MeetingNote?`

- [ ] **Étape 1 : écrire les tests rouges** `Tests/MeetingNoteStoreTests.swift` (suite
  « Notes horodatées — tri, filtres et reprise des notes libres ») : `sorted` classe par `t`
  puis `orderIndex` ; `filtered(kind:)` ne rend que le kind demandé ; `grouped` couvre tous les
  kinds présents ; `markdown` rend `- [04:12] texte` ; `defaultVisibility` rend `shared` pour
  `.manager` (côté manager), `private` pour `.oneToOne`, `shared` pour les autres ;
  `importLiveNotesIfNeeded` crée **une** note `t = 0, kind = .note` avec la visibilité par défaut
  du type, laisse `liveNotes` intact, pose `notesMigrated = true`, et un second appel ne crée
  rien (idempotence) ; une réunion sans `liveNotes` pose quand même `notesMigrated = true` sans
  créer de note.
- [ ] **Étape 2 : `swift test --filter MeetingNoteStoreTests`** → rouge.
- [ ] **Étape 3 : écrire `MeetingNoteStore.swift`.**
- [ ] **Étape 4 : déclarer le nouveau texte** dans `Meeting.textualContent`
  (`("note horodatée", $0.text)` pour chaque note triée) et ajouter `timedNotes`/`boards` à la
  garde des relations de `NoteFactory.isDiscardableEmptyNote`, plus les quatre nouvelles
  références sans inverse (`Commitment.promisedInMeeting`, `OneOnOneAgendaItem.meeting` et
  `.deferredToMeeting`, `MoodEntry.meeting`) dans `hasAttachedContentWithoutInverse`.
- [ ] **Étape 5 : brancher l'import** dans le `.onAppear` existant de `MeetingView`
  (`MeetingNoteStore.importLiveNotesIfNeeded(meeting, in: context)`), juste après
  `MeetingScreenRegistry.shared.screenAppeared` — un seul point d'appel, idempotent.
- [ ] **Étape 6 : `swift build`** propre ; `swift test --filter MeetingNoteStoreTests`,
  `--filter NoteFactory`, `--filter MeetingTextualContent` verts.
- [ ] **Étape 7 : commit** `feat(refonte): magasin de notes horodatées et reprise des notes libres`.

---

## Task 6 : câblage du filtre aux cinq flux

**Fichiers :**
- Modifier : `OneToOne/Services/AIReportService.swift`, `OneToOne/Services/Report/ReportHTMLBuilder.swift`,
  `OneToOne/Services/ExportService.swift`, `OneToOne/Services/RAGService.swift`,
  `OneToOne/Views/ChatbotView.swift`, `OneToOne/Views/Meeting/MeetingChatView.swift`
- Test : `Tests/ConfidentialityFilterTests.swift` (seconde suite)

**Interfaces produites :**
- `AIReportService.assembleTemplatePrompt(meeting:in:additionalContext:) -> String` (seam interne,
  appelée par `generate(meeting:…)` avant `AIClient.send`)
- `RAGIndexer.sourceText(for meeting: Meeting) -> String` (pure, sans embedding)
- `MeetingChatView.makePrompt(question:historicalContext:history:)` inclut les notes filtrées

- [ ] **Étape 1 : écrire le test rouge obligatoire** (spec chantier 2, critère 1), suite
  « Confidentialité — une note privée ne sort par aucun des cinq flux » : une réunion `.oneToOne`
  avec deux notes (`private` « salaire confidentiel », `shared` « point d'architecture ») ;
  vérifier que le texte privé est absent et le partagé présent de
  (1) `AIReportService.assembleTemplatePrompt`, (2) `ReportHTMLBuilder.build`,
  (3) `ExportService().exportMeetingMarkdown`, (4) `RAGIndexer.sourceText`,
  (5) `MeetingChatView(meeting:).makePrompt(...)`. Aucun appel réseau ni MLX.
- [ ] **Étape 2 : `swift test --filter ConfidentialityFilterTests`** → rouge sur les cinq flux.
- [ ] **Étape 3 : extraire les deux seams** : dans `AIReportService`, sortir l'assemblage du
  prompt de `generate(meeting:…)` vers `assembleTemplatePrompt` (comportement inchangé) ; dans
  `RAGIndexer`, sortir le calcul du texte source vers `sourceText(for:)`.
- [ ] **Étape 4 : insérer le bloc de notes filtré** dans les cinq flux —
  `MeetingNoteStore.contextBlock(for: meeting, audience: ConfidentialityFilter.audience(for: meeting.kind))`
  pour le prompt de rapport, l'HTML et l'export markdown ; `MeetingNoteStore.indexable` pour le
  texte source RAG ; `audience: .projectTeam` pour `ChatbotView.buildDatabaseContext` et
  `MeetingChatView.makePrompt`.
- [ ] **Étape 5 : `swift test --filter ConfidentialityFilterTests`** → vert ;
  `swift test --filter "Report"`, `--filter Export`, `--filter Chatbot`, `--filter MeetingChatView`
  verts ; `swift build` propre.
- [ ] **Étape 6 : commit** `feat(refonte): filtre de confidentialité câblé aux cinq lecteurs`.

---

## Task 7 : suite complète, `STATUS.md`, PR

**Fichiers :** `STATUS.md`

- [ ] **Étape 1 : `swift test`** complet ; corriger toute régression avant d'aller plus loin.
- [ ] **Étape 2 : vérification de migration sur une copie du store réel** si `~/Library/…/default.store`
  existe : copier dans un dossier temporaire, ouvrir avec `CurrentSchema` + `OneToOneMigrationPlan`,
  compter les réunions/actions avant/après. Consigner le résultat (ou l'absence de store).
- [ ] **Étape 3 : `STATUS.md`** — nouvelle section en tête : état, fichiers, tests avec les
  chiffres réels, écarts (registre fort borné, snapshot V2 non nested, `BackupService` non étendu),
  prochaine action = lot 1, date 2026-09-07.
- [ ] **Étape 4 : commit** `docs(status): consigner le lot 0B` puis
  `git push -u origin feat/refonte-lot-0b-socle-donnees`.
- [ ] **Étape 5 : PR** `gh pr create` vers `master`, titre
  `feat(refonte): lot 0B — schéma V3, tête de lecture, confidentialité`, corps = critères cochés,
  résultat de `swift test`, note sur le test de migration. **Ne pas merger.**

---

## Auto-revue

**Couverture de la spec.** §1.3 : `Note` → tâche 2 (`MeetingNote`) ; `Action` → tâche 2 (colonnes) ;
`Ref` → tâche 1 (`SourceRef`) ; `Attachment`/`Capture` → tâche 2 ; `Board`, `ProjectCard`,
`OneOnOneThread`, `Commitment`, `AgendaItem`, `moodHistory`, `objectives` → tâche 2 ;
`MeetingType.workshop` → tâche 3 ; axe temps `t` → tâche 4 ; §3.2 et §8 (filtre unique) → tâches 1 et 6 ;
critère chantier 2 n° 1 → tâche 6 étape 1. `recurringTopics` est calculé au lot 10 (pas de table),
`Meeting.mode` n'est pas persisté (lot 0A).

**Écarts assumés, notés dans `STATUS.md`** : registre du playhead à cache fort borné plutôt que
faible ; test de migration sans snapshot nested de V2 (les types Swift sont partagés, cf.
l'en-tête de `SchemaVersions.swift`) ; DTO `BackupService` des neuf nouvelles tables non écrits
(non trivial, tables vides à ce stade).
