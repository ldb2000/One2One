# Visibilité de la progression d'indexation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Montrer la progression du scan mails et du ré-embedding directement dans les vues qui les déclenchent, et afficher un résumé de l'état de l'index.

**Architecture:** `IndexStatsService` (namespace pur) fournit les comptages ; un `JobKind.embedding` dédié rend le job de ré-embedding identifiable ; `MailSettingsView` et `MaintenanceView` observent `JobQueue.shared` et affichent progression + Annuler pendant les jobs.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SwiftPM. Spec : `docs/superpowers/specs/2026-07-08-indexing-visibility-design.md`.

## Global Constraints

- Aucun nouveau modèle SwiftData, aucune migration. Aucun test n'exerce MLX.
- `swift test` : lancer avec `--skip CalendarImportEventTests` (crash pré-existant qui avorte le process) ; l'échec `MenuBarStatsTests.test_badge_twelve_compact` est pré-existant (dépendant de la date).
- Libellés UI en français ; services = `enum` namespace `@MainActor` ; fetch-all + filtre mémoire.
- `JobQueue` : tout nouveau `JobKind` → entrée dans `maxConcurrentByKind` ET cases dans les deux switch exhaustifs de `JobQueueSidebar` (`jobKindLabel`, `jobIcon`).
- `JobQueue.Job` expose `id: UUID`, `kind`, `status: JobStatus` (`.isTerminal`), `progress: Double?`, `statusText: String?` ; `JobQueue` expose `@Published private(set) var jobs`, `func cancel(_ id: UUID)`.

---

### Task 1: IndexStatsService

**Files:**
- Create: `OneToOne/Services/Maintenance/IndexStatsService.swift`
- Test: `Tests/IndexStatsServiceTests.swift`

**Interfaces:**
- Consumes: `ProjectMail`, `MailIndexSuggestion`, `TranscriptChunk`, `BatchJobsService.staleChunks(in:)`, `EmbeddingService.model`.
- Produces: `IndexStatsService.Stats` (`struct Equatable { var indexedMails: Int = 0; var pendingSuggestions: Int = 0; var totalChunks: Int = 0; var staleChunks: Int = 0 }`) et `static func snapshot(in context: ModelContext) -> Stats` — consommés par la Task 3.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/IndexStatsServiceTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class IndexStatsServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_snapshot_storeVide_zeros() throws {
        XCTAssertEqual(IndexStatsService.snapshot(in: context), IndexStatsService.Stats())
    }

    func test_snapshot_compteMailsSuggestionsEtChunks() throws {
        let mail = ProjectMail(messageId: "m1", accountName: "Pro", mailbox: "INBOX",
                               subject: "s", sender: "a@ex.com")
        context.insert(mail)
        context.insert(MailIndexSuggestion(
            messageId: "s1", accountName: "Pro", mailbox: "INBOX",
            subject: "s", sender: "a@ex.com", dateReceived: Date()))

        let fresh = TranscriptChunk(text: "t", orderIndex: 0, sourceType: "meeting")
        fresh.setEmbedding([0.1], model: EmbeddingService.model)
        context.insert(fresh)
        let stale = TranscriptChunk(text: "t2", orderIndex: 1, sourceType: "mail")
        stale.setEmbedding([0.2], model: "ancien-modele")
        context.insert(stale)
        try context.save()

        let s = IndexStatsService.snapshot(in: context)
        XCTAssertEqual(s, IndexStatsService.Stats(
            indexedMails: 1, pendingSuggestions: 1, totalChunks: 2, staleChunks: 1))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter IndexStatsServiceTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'IndexStatsService' in scope`)

- [ ] **Step 3: Implémenter**

Créer `OneToOne/Services/Maintenance/IndexStatsService.swift` :

```swift
import Foundation
import SwiftData

/// Comptages d'état de l'index RAG (mails, suggestions, chunks) pour les vues
/// de réglages. Namespace pur — fetch-all + comptage en mémoire (volume
/// faible ; à revoir si l'index dépasse ~50k chunks).
@MainActor
enum IndexStatsService {

    struct Stats: Equatable {
        var indexedMails: Int = 0
        var pendingSuggestions: Int = 0
        var totalChunks: Int = 0
        var staleChunks: Int = 0
    }

    static func snapshot(in context: ModelContext) -> Stats {
        let mails = (try? context.fetch(FetchDescriptor<ProjectMail>())) ?? []
        let suggestions = (try? context.fetch(FetchDescriptor<MailIndexSuggestion>())) ?? []
        let chunks = (try? context.fetch(FetchDescriptor<TranscriptChunk>())) ?? []
        return Stats(
            indexedMails: mails.count,
            pendingSuggestions: suggestions.count,
            totalChunks: chunks.count,
            staleChunks: BatchJobsService.staleChunks(in: context).count
        )
    }
}
```

- [ ] **Step 4: Vérifier le pass**

Run: `swift test --filter IndexStatsServiceTests 2>&1 | tail -5`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Maintenance/IndexStatsService.swift Tests/IndexStatsServiceTests.swift
git commit -m "feat(index): IndexStatsService — comptages d'état de l'index RAG"
```

---

### Task 2: JobKind.embedding dédié

**Files:**
- Modify: `OneToOne/Services/JobQueue.swift` (case + concurrence)
- Modify: `OneToOne/Views/JobQueueSidebar.swift` (2 switch)
- Modify: `OneToOne/Views/Settings/MaintenanceView.swift` (`enqueueReembedStaleChunks` : kind)

**Interfaces:**
- Produces: `JobQueue.JobKind.embedding` — consommé par la Task 3 (`activeEmbeddingJob`).

- [ ] **Step 1: JobKind + concurrence**

Dans `JobQueue.swift` :

```swift
    enum JobKind: String { case transcription, report, audioEdit, diarization, maintenance, mailScan, embedding }
```

Dans `maxConcurrentByKind`, ajouter :

```swift
        .embedding:     1
```

- [ ] **Step 2: Sidebar**

Dans `JobQueueSidebar.swift`, compléter les deux switch exhaustifs (adapter à la forme exacte des cases voisins du fichier) :

```swift
    // jobKindLabel
    case .embedding:     return "Ré-embedding"
    // jobIcon (branche .running)
    case .embedding:     Image(systemName: "point.3.connected.trianglepath.dotted")
```

- [ ] **Step 3: MaintenanceView — enqueue en .embedding**

Dans `enqueueReembedStaleChunks`, remplacer :

```swift
        _ = queue.start(kind: .maintenance, meetingTitle: "Ré-embedding RAG (\(stale.count) chunks)") { jobID in
```

par :

```swift
        _ = queue.start(kind: .embedding, meetingTitle: "Ré-embedding RAG (\(stale.count) chunks)") { jobID in
```

- [ ] **Step 4: Vérifier build + tests**

Run: `swift build 2>&1 | tail -2 && swift test --skip CalendarImportEventTests 2>&1 | grep -E "Executed|Test run with" | tail -3`
Expected: `Build complete!` ; mêmes résultats que la base (seul échec : `MenuBarStatsTests.test_badge_twelve_compact`, pré-existant).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/JobQueue.swift OneToOne/Views/JobQueueSidebar.swift OneToOne/Views/Settings/MaintenanceView.swift
git commit -m "feat(index): JobKind.embedding dédié pour le job de ré-embedding"
```

---

### Task 3: Progression en direct + ligne d'état (UI)

**Files:**
- Modify: `OneToOne/Views/Settings/MailSettingsView.swift`
- Modify: `OneToOne/Views/Settings/MaintenanceView.swift` (section EMBEDDINGS / RAG)

**Interfaces:**
- Consumes: `IndexStatsService.snapshot(in:)` (T1), `JobQueue.JobKind.embedding` (T2), `JobQueue.Job.progress/.statusText/.status.isTerminal`, `queue.cancel(_:)`.

- [ ] **Step 1: MailSettingsView — observation de la queue + helpers**

Ajouter aux propriétés :

```swift
    @ObservedObject private var queue = JobQueue.shared
```

Ajouter en propriété calculée :

```swift
    /// Job de scan en cours (au plus un : concurrence 1 sur .mailScan).
    private var activeScanJob: JobQueue.Job? {
        queue.jobs.first { $0.kind == .mailScan && !$0.status.isTerminal }
    }
```

- [ ] **Step 2: MailSettingsView — ligne d'état de l'index**

Insérer en tête du `VStack` du `body` (avant le `Toggle` d'activation) :

```swift
            // État de l'index — recalculé à chaque rendu (transitions de jobs
            // incluses, via l'observation de la queue).
            let stats = IndexStatsService.snapshot(in: context)
            Text("\(stats.indexedMails) mail(s) indexé(s) · \(stats.pendingSuggestions) suggestion(s) en attente · \(stats.totalChunks) chunks vectorisés (dont \(stats.staleChunks) obsolète(s))")
                .font(.caption)
                .foregroundStyle(.secondary)
```

- [ ] **Step 3: MailSettingsView — progression du scan**

Remplacer le contenu du `HStack(spacing: 12)` final (bouton « Scanner maintenant » + dernière passe) par :

```swift
            HStack(spacing: 12) {
                if let job = activeScanJob {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let p = job.progress {
                                ProgressView(value: max(0, min(1, p)))
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 220)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 220)
                            }
                            Button("Annuler") { queue.cancel(job.id) }
                        }
                        Text(job.statusText?.isEmpty == false ? job.statusText! : "Scan en cours…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Scanner maintenant") {
                        MailAutoIndexService.shared.scanNow(context: context, settings: settings)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.mailAutoIndexEnabled || settings.mailAutoIndexMailboxes.isEmpty)
                }

                if let last = settings.mailAutoIndexLastScanAt {
                    Text("Dernière passe : \(last.formatted(date: .abbreviated, time: .shortened)) — \(settings.mailAutoIndexLastScanStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Aucune passe effectuée.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
```

- [ ] **Step 4: MaintenanceView — progression du ré-embedding**

Ajouter aux propriétés (si pas déjà présent) :

```swift
    @ObservedObject private var queue = JobQueue.shared
```

Ajouter la propriété calculée :

```swift
    /// Job de ré-embedding en cours (au plus un : concurrence 1 sur .embedding).
    private var activeEmbeddingJob: JobQueue.Job? {
        queue.jobs.first { $0.kind == .embedding && !$0.status.isTerminal }
    }
```

Dans `embeddingSection`, remplacer l'appel `batchRow(...)` par :

```swift
            if let job = activeEmbeddingJob {
                HStack(spacing: 8) {
                    if let p = job.progress {
                        ProgressView(value: max(0, min(1, p)))
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    if let s = job.statusText, !s.isEmpty {
                        Text(s).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                    Button("Annuler") { queue.cancel(job.id) }
                }
            } else {
                batchRow(
                    count: BatchJobsService.staleChunks(in: context).count,
                    label: "chunks à ré-embedder",
                    buttonLabel: "Ré-embedder l'index",
                    action: enqueueReembedStaleChunks
                )
            }
```

⚠️ Si `enqueueReembedStaleChunks` référence `queue` localement (`let queue = JobQueue.shared`), la nouvelle propriété `@ObservedObject` du même nom peut entrer en conflit — dans ce cas garder la propriété et supprimer le `let` local.

- [ ] **Step 5: Vérifier build + tests**

Run: `swift build 2>&1 | tail -2 && swift test --skip CalendarImportEventTests 2>&1 | grep -E "Executed|Test run with" | tail -3`
Expected: `Build complete!` ; résultats identiques à la base.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/Settings/MailSettingsView.swift OneToOne/Views/Settings/MaintenanceView.swift
git commit -m "feat(index): progression en direct + état de l'index dans Réglages"
```
