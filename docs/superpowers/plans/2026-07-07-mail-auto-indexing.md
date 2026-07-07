# Indexation automatique des mails + embeddings MLX — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scanner périodiquement les boîtes Mail.app choisies (mails lus, fenêtre limitée), rattacher automatiquement les mails aux projets (heuristiques + Gemma 4), proposer les cas incertains dans une file de validation, et vectoriser via MLX in-process (`MLXEmbedders`) au lieu d'Ollama.

**Architecture:** `EmbeddingService` devient un routeur MLX/Ollama avec préfixes nomic par rôle (document/query) ; un job de maintenance ré-embedde l'index existant. Côté mails : `MailService` gagne un scan AppleScript filtré (lus + cutoff), `MailProjectMatcher` (heuristiques pures) + `MailLLMClassifier` (Gemma 4 via `DirectLLMClient`) produisent un verdict, `MailAutoIndexService` orchestre le tout dans un job `JobQueue` (`.mailScan`), avec 2 nouveaux `@Model` (`MailIndexSuggestion`, `MailScanRecord`) et une sheet de validation.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (SchemaV1, lightweight migration), SwiftPM, MLXEmbedders (`mlx-swift-lm`), DirectLLMClient (Gemma 4 MLX), AppleScript (Apple Mail), XCTest + Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-07-mail-auto-indexing-design.md`

## Global Constraints

- Build : `swift build` ; tests : `swift test` (cible unique `OneToOneTests`, path `Tests/`, pas de sous-dossiers).
- **`swift test` / `swift build` ne compilent PAS les shaders Metal MLX** : aucun test ne doit exercer l'inférence MLX réelle (ni embeddings ni Gemma 4). Toute logique testée doit être pure ou injectable (closure `generate`, textes préfixés, parsing).
- Commentaires et libellés UI en **français** ; code/symboles en anglais.
- Services : `enum` namespace de fonctions statiques pures, ou `class` singleton `@MainActor` `.shared` (état).
- SwiftData : tout nouveau champ a un **default inline** (lightweight migration, pas de SchemaV2) ; enums persistées = `…Raw: String` + wrapper calculé ; listes = `…JSON: String` + accesseur calculé.
- Les modèles (`Models/`) ne référencent jamais les services ni les vues.
- `JobQueue` : tout nouveau `JobKind` doit être ajouté à `maxConcurrentByKind` ET aux switch exhaustifs de `JobQueueSidebar` (`jobKindLabel`, `jobIcon`).
- Fetch SwiftData : `FetchDescriptor` complet + filtre en mémoire (pas de `#Predicate` à travers les relations — convention du repo).
- Réglages d'embedding en `UserDefaults` (clés `onetoone_*`), réglages mails dans `AppSettings` (singleton via `canonicalSettings`).
- Config LLM local : `AppSettings.directModelRepo` (défaut `mlx-community/gemma-4-26b-a4b-it-8bit`).
- Modèle d'embedding MLX par défaut : `nomic-ai/nomic-embed-text-v1.5` (768 dim) ; Ollama legacy : `nomic-embed-text`.
- Seuils par défaut : auto ≥ **0.75**, suggestion ≥ **0.45** ; continuité de fil = **0.95**.

---

### Task 1: MLXEmbeddingEngine (moteur d'embedding MLX in-process)

**Files:**
- Modify: `Package.swift` (dependencies de la cible `OneToOne`, après la ligne `.product(name: "MLXHuggingFace", package: "mlx-swift-lm"),`)
- Create: `OneToOne/Services/MLXEmbeddingEngine.swift`

**Interfaces:**
- Consumes: `EmbedderModelFactory.shared.loadContainer(from:using:configuration:progressHandler:)` (MLXEmbedders), macros `#hubDownloader()` / `#huggingFaceTokenizerLoader()` (MLXHuggingFace).
- Produces: `MLXEmbeddingEngine.embedBatch(_ texts: [String], modelRepo: String) async throws -> [[Float]]` (`@MainActor enum`), utilisé par la Task 2. Les textes passés sont **déjà préfixés** par l'appelant.

⚠️ Pas de TDD possible ici (`swift test` n'a pas les shaders Metal) : critère de succès = compilation. La vérification fonctionnelle réelle se fait en Task 12 via l'app packagée.

- [ ] **Step 1: Ajouter le produit MLXEmbedders dans Package.swift**

Dans les `dependencies` de la cible exécutable `OneToOne`, juste après `.product(name: "MLXHuggingFace", package: "mlx-swift-lm"),` :

```swift
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
```

- [ ] **Step 2: Créer MLXEmbeddingEngine.swift**

⚠️ Pièges connus (vérifiés dans le checkout `mlx-swift-lm`) : la fonction **libre** `loadModelContainer(...)` (utilisée par `DirectLLMClient`) ne charge QUE les LLM — pour un embedder il faut `EmbedderModelFactory.shared.loadContainer(...)`. La surcharge `perform { (model, tokenizer, pooling) in }` du README est dépréciée — utiliser la closure à un paramètre `EmbedderModelContext`. Toute `MLXArray` doit être `eval()`-uée avant de sortir de `perform`.

```swift
import Foundation
import os

#if canImport(MLXEmbedders)
import MLX
import MLXEmbedders
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

private let embedEngineLog = Logger(subsystem: "com.onetoone.app", category: "embed-mlx")

/// Moteur d'embedding MLX in-process (nomic-embed-text-v1.5 par défaut).
/// Cache statique mono-modèle, même pattern que `DirectLLMClient` : le
/// container est rechargé si le repo change. Les textes reçus sont supposés
/// déjà préfixés (`search_document:` / `search_query:`) par l'appelant.
@MainActor
enum MLXEmbeddingEngine {

    enum EngineError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "Embeddings MLX indisponibles dans ce build (MLXEmbedders non lié)."
        }
    }

#if canImport(MLXEmbedders)
    private static var container: EmbedderModelContainer?
    private static var loadedRepo: String?

    private static func ensureContainer(repo: String) async throws -> EmbedderModelContainer {
        if let container, loadedRepo == repo { return container }
        embedEngineLog.info("chargement embedder \(repo, privacy: .public)")
        let loaded = try await EmbedderModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: repo)
        )
        container = loaded
        loadedRepo = repo
        return loaded
    }

    /// Embedde un lot de textes. Retourne un vecteur (768 dim pour nomic v1.5)
    /// par texte, dans l'ordre d'entrée.
    static func embedBatch(_ texts: [String], modelRepo: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let container = try await ensureContainer(repo: modelRepo)
        return try await container.perform { context in
            let tokenizer = context.tokenizer
            let encoded = texts.map { tokenizer.encode(text: $0, addSpecialTokens: true) }
            let padId = tokenizer.eosTokenId ?? 0
            let maxLength = encoded.reduce(into: 16) { $0 = max($0, $1.count) }
            let padded = stacked(encoded.map { ids in
                MLXArray(ids + Array(repeating: padId, count: maxLength - ids.count))
            })
            let mask = (padded .!= padId)
            let tokenTypes = MLXArray.zeros(like: padded)
            let output = context.model(
                padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask)
            // Pooling mean + L2 (stratégie chargée depuis 1_Pooling/config.json du
            // repo nomic) ; mask passé pour exclure le padding de la moyenne ;
            // applyLayerNorm requis par la recette nomic v1.5.
            let result = context.pooling(
                output, mask: mask.asType(.float32),
                normalize: true, applyLayerNorm: true)
            result.eval()
            return result.map { $0.asArray(Float.self) }
        }
    }
#else
    static func embedBatch(_ texts: [String], modelRepo: String) async throws -> [[Float]] {
        throw EngineError.unavailable
    }
#endif
}
```

- [ ] **Step 3: Vérifier la compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Package.swift OneToOne/Services/MLXEmbeddingEngine.swift
git commit -m "feat(rag): moteur d'embedding MLX in-process (MLXEmbedders, nomic v1.5)"
```

---

### Task 2: EmbeddingService — routeur de backends + préfixes nomic par rôle

**Files:**
- Modify: `OneToOne/Services/EmbeddingService.swift`
- Modify: `OneToOne/Services/RAGService.swift:170` (rôle `.query` dans `RAGQuery.search`)
- Test: `Tests/EmbeddingServiceRoutingTests.swift`

**Interfaces:**
- Consumes: `MLXEmbeddingEngine.embedBatch(_:modelRepo:)` (Task 1).
- Produces (utilisé par Tasks 3, 9 et par le code existant sans changement d'appel) :
  - `EmbeddingService.Backend` : `enum Backend: String { case mlx, ollama }`
  - `EmbeddingService.Role` : `enum Role { case document, query }`
  - `static let backendKey = "onetoone_embedding_backend"`, `static var backend: Backend` (défaut `.mlx`)
  - `static let defaultMLXModel = "nomic-ai/nomic-embed-text-v1.5"`, `static var model: String` (dépend du backend si la clé UserDefaults est absente)
  - `static func prefixedText(_ text: String, role: Role, backend: Backend, model: String) -> String` (pur, testable)
  - `static func embed(_ text: String, role: Role = .document) async throws -> [Float]`
  - `static func embedBatch(_ texts: [String], role: Role = .document, concurrency: Int = 4) async throws -> [[Float]]`

Les appels existants (`RAGIndexer.reindex`, `ProjectMailStore.reindex`, `MeetingAttachmentService` ×2) compilent sans modification : `role` a une valeur par défaut `.document`, qui est le bon rôle pour eux. Seule `RAGQuery.search` passe explicitement `.query`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/EmbeddingServiceRoutingTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

// .serialized : les tests mutent les mêmes clés UserDefaults globales —
// l'exécution parallèle par défaut de Swift Testing les rendrait flaky.
@Suite("EmbeddingService — routage backend et préfixes nomic", .serialized)
struct EmbeddingServiceRoutingTests {

    /// Sauvegarde/restaure les clés UserDefaults touchées par un test.
    private func withDefaults(_ values: [String: String?], _ body: () throws -> Void) rethrows {
        let keys = [EmbeddingService.backendKey, EmbeddingService.modelKey]
        let saved = keys.map { ($0, UserDefaults.standard.string(forKey: $0)) }
        defer {
            for (k, v) in saved {
                if let v { UserDefaults.standard.set(v, forKey: k) }
                else { UserDefaults.standard.removeObject(forKey: k) }
            }
        }
        for (k, v) in values {
            if let v { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
        try body()
    }

    @Test("Backend par défaut = mlx, modèle par défaut dépend du backend")
    func defaultBackendAndModel() throws {
        try withDefaults([EmbeddingService.backendKey: nil, EmbeddingService.modelKey: nil]) {
            #expect(EmbeddingService.backend == .mlx)
            #expect(EmbeddingService.model == "nomic-ai/nomic-embed-text-v1.5")
        }
        try withDefaults([EmbeddingService.backendKey: "ollama", EmbeddingService.modelKey: nil]) {
            #expect(EmbeddingService.backend == .ollama)
            #expect(EmbeddingService.model == "nomic-embed-text")
        }
    }

    @Test("Un modèle explicite en UserDefaults prime sur le défaut")
    func explicitModelWins() throws {
        try withDefaults([EmbeddingService.backendKey: "mlx", EmbeddingService.modelKey: "BAAI/bge-m3"]) {
            #expect(EmbeddingService.model == "BAAI/bge-m3")
        }
    }

    @Test("Préfixes nomic appliqués seulement en mlx + modèle nomic")
    func nomicPrefixes() {
        let t = "Compte rendu du copil"
        #expect(EmbeddingService.prefixedText(t, role: .document, backend: .mlx,
                                              model: "nomic-ai/nomic-embed-text-v1.5")
                == "search_document: Compte rendu du copil")
        #expect(EmbeddingService.prefixedText(t, role: .query, backend: .mlx,
                                              model: "nomic-ai/nomic-embed-text-v1.5")
                == "search_query: Compte rendu du copil")
        // Ollama : jamais de préfixe (comportement historique conservé)
        #expect(EmbeddingService.prefixedText(t, role: .document, backend: .ollama,
                                              model: "nomic-embed-text") == t)
        // Modèle non-nomic en mlx : pas de préfixe
        #expect(EmbeddingService.prefixedText(t, role: .query, backend: .mlx,
                                              model: "BAAI/bge-m3") == t)
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter EmbeddingServiceRoutingTests 2>&1 | tail -5`
Expected: FAIL (erreur de compilation : `type 'EmbeddingService' has no member 'backend'` / `prefixedText`)

- [ ] **Step 3: Implémenter le routeur dans EmbeddingService.swift**

Modifier `EmbeddingService.swift`. ⚠️ Piège : `embed()` fait `trimmingCharacters` + `guard !stripped.isEmpty` — le préfixe doit être ajouté **après** ce guard (sinon un texte vide préfixé passerait le guard).

En tête de `struct EmbeddingService` (après `static let modelKey`) :

```swift
    // MARK: - Backend (MLX in-process par défaut, Ollama legacy)

    enum Backend: String { case mlx, ollama }

    /// Rôle du texte pour les modèles asymétriques (nomic) :
    /// `.document` à l'indexation, `.query` pour la recherche.
    enum Role { case document, query }

    static let backendKey = "onetoone_embedding_backend"
    static let defaultMLXModel = "nomic-ai/nomic-embed-text-v1.5"

    static var backend: Backend {
        Backend(rawValue: UserDefaults.standard.string(forKey: backendKey) ?? "") ?? .mlx
    }

    /// Préfixe nomic (search_document: / search_query:) — seulement en backend
    /// MLX avec un modèle nomic. Le chemin Ollama reste sans préfixe
    /// (comportement historique, cohérent avec l'index existant).
    static func prefixedText(_ text: String, role: Role, backend: Backend, model: String) -> String {
        guard backend == .mlx, model.lowercased().contains("nomic") else { return text }
        switch role {
        case .document: return "search_document: " + text
        case .query:    return "search_query: " + text
        }
    }
```

Remplacer la propriété `model` existante :

```swift
    static var model: String {
        if let stored = UserDefaults.standard.string(forKey: modelKey), !stored.isEmpty {
            return stored
        }
        switch backend {
        case .mlx:    return defaultMLXModel
        case .ollama: return defaultModel
        }
    }
```

Renommer l'actuel corps de `embed` en `embedOllama` (fonction privée, corps HTTP inchangé, signature `private static func embedOllama(_ stripped: String) async throws -> [Float]` — elle reçoit le texte déjà strippé), puis :

```swift
    /// Embed un texte selon le backend courant.
    static func embed(_ text: String, role: Role = .document) async throws -> [Float] {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return [] }
        switch backend {
        case .mlx:
            let prefixed = prefixedText(stripped, role: role, backend: .mlx, model: model)
            let vectors = try await MLXEmbeddingEngine.embedBatch([prefixed], modelRepo: model)
            return vectors.first ?? []
        case .ollama:
            return try await embedOllama(stripped)
        }
    }
```

Adapter `embedBatch` : garder le chemin Ollama (task group + `AsyncSemaphore`) tel quel mais en appelant `embed(t, role: role)` ; ajouter le chemin MLX en sous-lots de 16 (borne mémoire GPU), en préservant l'ordre et les vecteurs vides pour textes vides :

```swift
    static func embedBatch(_ texts: [String], role: Role = .document, concurrency: Int = 4) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        if backend == .mlx {
            let currentModel = model
            var results = [[Float]](repeating: [], count: texts.count)
            // Indices des textes non vides, préfixés, envoyés par sous-lots de 16.
            let nonEmpty: [(Int, String)] = texts.enumerated().compactMap { i, t in
                let stripped = t.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stripped.isEmpty else { return nil }
                return (i, prefixedText(stripped, role: role, backend: .mlx, model: currentModel))
            }
            var cursor = 0
            while cursor < nonEmpty.count {
                let slice = Array(nonEmpty[cursor..<min(cursor + 16, nonEmpty.count)])
                let vectors = try await MLXEmbeddingEngine.embedBatch(slice.map(\.1), modelRepo: currentModel)
                for (offset, (originalIndex, _)) in slice.enumerated() where offset < vectors.count {
                    results[originalIndex] = vectors[offset]
                }
                cursor += 16
            }
            return results
        }

        // Chemin Ollama historique (concurrence limitée).
        var results: [Int: [Float]] = [:]
        let sem = AsyncSemaphore(value: max(1, concurrency))
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (i, t) in texts.enumerated() {
                await sem.wait()
                group.addTask {
                    defer { Task { await sem.signal() } }
                    let v = try await embed(t, role: role)
                    return (i, v)
                }
            }
            for try await (i, v) in group {
                results[i] = v
            }
        }
        return texts.indices.map { results[$0] ?? [] }
    }
```

- [ ] **Step 4: Passer le rôle `.query` dans RAGQuery.search**

Dans `OneToOne/Services/RAGService.swift`, ligne ~170 (`RAGQuery.search`) :

```swift
        let queryVec = try await EmbeddingService.embed(query, role: .query)
```

(Les 4 sites d'indexation — `RAGIndexer.reindex`, `ProjectMailStore.reindex`, `MeetingAttachmentService` import + reindex — restent inchangés : le défaut `.document` est correct.)

- [ ] **Step 5: Vérifier que les tests passent**

Run: `swift test --filter EmbeddingServiceRoutingTests 2>&1 | tail -5`
Expected: PASS (4 tests)

Run: `swift test 2>&1 | tail -5`
Expected: PASS (aucune régression — les signatures existantes sont compatibles)

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/EmbeddingService.swift OneToOne/Services/RAGService.swift Tests/EmbeddingServiceRoutingTests.swift
git commit -m "feat(rag): EmbeddingService routeur MLX/Ollama + préfixes nomic par rôle"
```

---

### Task 3: Job de ré-embedding + réglages RAG (Maintenance)

**Files:**
- Modify: `OneToOne/Services/Maintenance/BatchJobsService.swift`
- Modify: `OneToOne/Views/Settings/MaintenanceView.swift`
- Test: `Tests/BatchJobsStaleChunksTests.swift`

**Interfaces:**
- Consumes: `EmbeddingService.model` / `.backend` / `.embedBatch(_:role:)` (Task 2), `TranscriptChunk.embeddingModel` / `.embeddingData` / `.setEmbedding(_:model:)` / `.text`, `JobQueue.shared.start(kind:meetingID:meetingTitle:work:)`, pattern `batchRow(count:label:buttonLabel:action:)` existant de `MaintenanceView`.
- Produces: `BatchJobsService.staleChunks(in context: ModelContext) -> [TranscriptChunk]` ; section UI « EMBEDDINGS / RAG » dans Maintenance (picker backend, champ modèle, bouton « Ré-embedder l'index »).

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/BatchJobsStaleChunksTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class BatchJobsStaleChunksTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_staleChunks_detecteModeleObsoleteEtEmbeddingManquant() throws {
        let current = EmbeddingService.model

        let upToDate = TranscriptChunk(text: "à jour", orderIndex: 0, sourceType: "meeting")
        upToDate.setEmbedding([0.1, 0.2], model: current)
        context.insert(upToDate)

        let oldModel = TranscriptChunk(text: "ancien modèle", orderIndex: 1, sourceType: "meeting")
        oldModel.setEmbedding([0.3, 0.4], model: "un-autre-modele")
        context.insert(oldModel)

        let noEmbedding = TranscriptChunk(text: "sans vecteur", orderIndex: 2, sourceType: "mail")
        context.insert(noEmbedding)

        try context.save()

        let stale = BatchJobsService.staleChunks(in: context)
        XCTAssertEqual(stale.count, 2)
        XCTAssertFalse(stale.contains(where: { $0.text == "à jour" }))
    }

    func test_staleChunks_idempotence_apresReembedding() throws {
        let chunk = TranscriptChunk(text: "obsolète", orderIndex: 0, sourceType: "meeting")
        chunk.setEmbedding([0.1], model: "ancien-modele")
        context.insert(chunk)
        try context.save()
        XCTAssertEqual(BatchJobsService.staleChunks(in: context).count, 1)

        // Simule le ré-embedding (sans MLX) : re-set au modèle courant.
        chunk.setEmbedding([0.2], model: EmbeddingService.model)
        try context.save()
        // Une relance du job serait un no-op : plus rien à traiter.
        XCTAssertTrue(BatchJobsService.staleChunks(in: context).isEmpty)
    }
}
```

- [ ] **Step 2: Vérifier que le test échoue**

Run: `swift test --filter BatchJobsStaleChunksTests 2>&1 | tail -5`
Expected: FAIL (`type 'BatchJobsService' has no member 'staleChunks'`)

- [ ] **Step 3: Implémenter staleChunks**

Dans `BatchJobsService.swift`, ajouter (même style que `meetingsWithoutReport`) :

```swift
    /// Chunks RAG dont l'embedding est absent ou calculé avec un autre modèle
    /// que le modèle courant (`EmbeddingService.model`). Candidats au
    /// ré-embedding après changement de backend/modèle.
    static func staleChunks(in context: ModelContext) -> [TranscriptChunk] {
        let descriptor = FetchDescriptor<TranscriptChunk>()
        let all = (try? context.fetch(descriptor)) ?? []
        let current = EmbeddingService.model
        return all.filter { $0.embeddingData == nil || $0.embeddingModel != current }
    }
```

- [ ] **Step 4: Vérifier que le test passe**

Run: `swift test --filter BatchJobsStaleChunksTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Ajouter la section « EMBEDDINGS / RAG » dans MaintenanceView**

Dans `MaintenanceView.swift` : ajouter en propriétés de la struct (à côté des `@State` existants) :

```swift
    @AppStorage("onetoone_embedding_backend") private var embeddingBackendRaw: String = "mlx"
    @AppStorage("onetoone_embedding_model") private var embeddingModelOverride: String = ""
```

Ajouter une sous-vue et l'insérer dans le `body` (après la section « TRAITEMENTS EN LOT ») :

```swift
    @ViewBuilder
    private var embeddingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("EMBEDDINGS / RAG", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Picker("Backend d'embedding", selection: $embeddingBackendRaw) {
                Text("MLX (in-process)").tag("mlx")
                Text("Ollama (legacy)").tag("ollama")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            LabeledContent("Modèle") {
                EditableTextField(
                    placeholder: embeddingBackendRaw == "mlx"
                        ? EmbeddingService.defaultMLXModel
                        : EmbeddingService.defaultModel,
                    text: $embeddingModelOverride
                )
                .frame(height: 24)
            }
            Text("Vide = modèle par défaut du backend. Changer de backend ou de modèle rend l'index existant obsolète : lancer le ré-embedding ci-dessous.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            batchRow(
                count: BatchJobsService.staleChunks(in: context).count,
                label: "chunks à ré-embedder",
                buttonLabel: "Ré-embedder l'index",
                action: enqueueReembedStaleChunks
            )
        }
    }

    private func enqueueReembedStaleChunks() {
        let queue = JobQueue.shared
        let stale = BatchJobsService.staleChunks(in: context)
        guard !stale.isEmpty else { return }
        _ = queue.start(kind: .maintenance, meetingTitle: "Ré-embedding RAG (\(stale.count) chunks)") { jobID in
            let total = stale.count
            var done = 0
            var cursor = 0
            while cursor < total {
                try Task.checkCancellation()
                let batch = Array(stale[cursor..<min(cursor + 16, total)])
                let vectors = try await EmbeddingService.embedBatch(batch.map(\.text), role: .document)
                await MainActor.run {
                    for (i, chunk) in batch.enumerated() {
                        let v = (i < vectors.count) ? vectors[i] : []
                        if !v.isEmpty {
                            chunk.setEmbedding(v, model: EmbeddingService.model)
                        }
                    }
                    try? context.save()
                }
                done += batch.count
                cursor += 16
                await MainActor.run {
                    queue.updateProgress(jobID, fraction: Double(done) / Double(total),
                                         status: "\(done)/\(total) chunks")
                }
            }
        }
    }
```

- [ ] **Step 6: Vérifier build + tests complets**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` puis PASS

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Services/Maintenance/BatchJobsService.swift OneToOne/Views/Settings/MaintenanceView.swift Tests/BatchJobsStaleChunksTests.swift
git commit -m "feat(rag): job de ré-embedding de l'index + réglages backend/modèle (Maintenance)"
```

---

### Task 4: Modèles SwiftData (MailIndexSuggestion, MailScanRecord) + réglages AppSettings

**Files:**
- Modify: `OneToOne/Models/ProjectMailModels.swift` (nouveaux modèles à la suite)
- Modify: `OneToOne/Models/SchemaVersions.swift` (enregistrement dans SchemaV1, après `ProjectMailAttachment.self,`)
- Modify: `OneToOne/Models/AppSettings.swift` (nouvelle section MARK après `var lastCleanupAt: Date?`)
- Modify: `OneToOne/Services/MailService.swift` (conformance `Codable` de `MailboxRef`)
- Test: `Tests/MailScanModelsTests.swift`

**Interfaces:**
- Produces (utilisé par Tasks 5, 8, 9, 10, 11) :
  - `enum MailScanVerdict: String { case attached, suggested, ignored }` (dans `ProjectMailModels.swift`, hors des classes)
  - `@Model final class MailScanRecord` : `messageId: String`, `verdictRaw: String`, `evaluatedAt: Date`, wrapper `verdict: MailScanVerdict`, `init(messageId:verdict:evaluatedAt:)`
  - `@Model final class MailIndexSuggestion` : `messageId`, `accountName`, `mailbox`, `subject`, `sender`, `preview`, `dateReceived: Date`, `confidence: Double`, `createdAt: Date`, `suggestedProject: Project?`, `init(messageId:accountName:mailbox:subject:sender:dateReceived:preview:confidence:)`
  - `AppSettings` : `mailAutoIndexEnabled: Bool = false`, `mailAutoIndexMailboxesJSON: String = "[]"`, `mailAutoIndexLookbackDays: Int = 90`, `mailAutoIndexIntervalMinutes: Int = 60`, `mailAutoIndexAutoThreshold: Double = 0.75`, `mailAutoIndexSuggestThreshold: Double = 0.45`, `mailAutoIndexLastScanAt: Date?`, `mailAutoIndexLastScanStatus: String = ""`
  - `MailboxRef: Codable` (l'accesseur calculé `[MailboxRef]` est ajouté en Task 9 dans la couche Services — les modèles ne référencent pas les types Services)

Exclusion assumée du backup : `ProjectMail` n'est déjà **pas** sérialisé par `BackupService` (précédent existant — données ré-ingérables depuis Mail.app, dédup `messageId`). `MailIndexSuggestion`/`MailScanRecord` suivent la même règle : rien à faire dans `BackupService`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/MailScanModelsTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailScanModelsTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_mailScanRecord_wrapperVerdict_etPersistance() throws {
        let r = MailScanRecord(messageId: "msg-1", verdict: .suggested)
        context.insert(r)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MailScanRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.verdict, .suggested)

        // Raw inconnu → fallback .ignored
        fetched.first?.verdictRaw = "n-importe-quoi"
        XCTAssertEqual(fetched.first?.verdict, .ignored)
    }

    func test_mailIndexSuggestion_persistanceAvecProjet() throws {
        let project = Project(code: "PRJ1", name: "Refonte SI", domain: "IT", phase: "Cadrage")
        context.insert(project)
        let s = MailIndexSuggestion(
            messageId: "msg-2", accountName: "Pro", mailbox: "INBOX",
            subject: "Re: Refonte SI — planning", sender: "Alice <alice@ex.com>",
            dateReceived: Date(), preview: "aperçu", confidence: 0.6
        )
        s.suggestedProject = project
        context.insert(s)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MailIndexSuggestion>())
        XCTAssertEqual(fetched.first?.suggestedProject?.code, "PRJ1")
        XCTAssertEqual(fetched.first?.confidence ?? 0, 0.6, accuracy: 0.001)
    }

    func test_appSettings_defautsMailAutoIndex() {
        let s = AppSettings()
        XCTAssertFalse(s.mailAutoIndexEnabled)
        XCTAssertEqual(s.mailAutoIndexMailboxesJSON, "[]")
        XCTAssertEqual(s.mailAutoIndexLookbackDays, 90)
        XCTAssertEqual(s.mailAutoIndexIntervalMinutes, 60)
        XCTAssertEqual(s.mailAutoIndexAutoThreshold, 0.75, accuracy: 0.001)
        XCTAssertEqual(s.mailAutoIndexSuggestThreshold, 0.45, accuracy: 0.001)
        XCTAssertNil(s.mailAutoIndexLastScanAt)
    }

    func test_mailboxRef_codableRoundTrip() throws {
        let refs = [MailboxRef(accountName: "Pro", mailboxName: "INBOX")]
        let data = try JSONEncoder().encode(refs)
        let decoded = try JSONDecoder().decode([MailboxRef].self, from: data)
        XCTAssertEqual(decoded, refs)
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailScanModelsTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'MailScanRecord' in scope`)

- [ ] **Step 3: Implémenter les modèles**

À la fin de `OneToOne/Models/ProjectMailModels.swift` :

```swift
// MARK: - Scan automatique des mails

/// Verdict d'évaluation d'un mail par le scan automatique.
enum MailScanVerdict: String {
    case attached   // rattaché automatiquement à un projet (indexé)
    case suggested  // en attente de validation utilisateur
    case ignored    // aucun match projet — non indexé
}

/// Trace d'évaluation d'un mail par le scan automatique : garantit qu'un
/// `messageId` déjà traité n'est jamais ré-évalué. Purgé au-delà de la
/// fenêtre d'historique + 30 jours (cf. `MailScanStore.purgeRecords`).
@Model
final class MailScanRecord {
    var messageId: String
    /// Stocké en String (contournement bug SwiftData sur les enums).
    var verdictRaw: String = MailScanVerdict.ignored.rawValue
    var evaluatedAt: Date = Date()

    var verdict: MailScanVerdict {
        get { MailScanVerdict(rawValue: verdictRaw) ?? .ignored }
        set { verdictRaw = newValue.rawValue }
    }

    init(messageId: String, verdict: MailScanVerdict, evaluatedAt: Date = Date()) {
        self.messageId = messageId
        self.verdictRaw = verdict.rawValue
        self.evaluatedAt = evaluatedAt
    }
}

/// Match incertain en attente de validation utilisateur. Sans corps ni
/// embedding : le corps (fetch AppleScript lent) n'est récupéré qu'à la
/// validation, qui matérialise un `ProjectMail` via `ProjectMailStore.save`.
@Model
final class MailIndexSuggestion {
    var messageId: String
    var accountName: String
    var mailbox: String
    var subject: String
    var sender: String
    var preview: String = ""
    var dateReceived: Date
    /// Score du matcher (0–1) au moment du scan.
    var confidence: Double = 0
    var createdAt: Date = Date()
    /// Relation sans inverse déclaré (même pattern que
    /// `ProjectCollaboratorEntry.collaborator`) : la suppression du projet
    /// laisse une suggestion orpheline, nettoyée par `MailScanStore`.
    var suggestedProject: Project?

    init(
        messageId: String,
        accountName: String,
        mailbox: String,
        subject: String,
        sender: String,
        dateReceived: Date,
        preview: String = "",
        confidence: Double = 0
    ) {
        self.messageId = messageId
        self.accountName = accountName
        self.mailbox = mailbox
        self.subject = subject
        self.sender = sender
        self.dateReceived = dateReceived
        self.preview = preview
        self.confidence = confidence
    }
}
```

- [ ] **Step 4: Enregistrer dans SchemaV1**

Dans `SchemaVersions.swift`, après `ProjectMailAttachment.self,` :

```swift
            MailIndexSuggestion.self,
            MailScanRecord.self,
```

- [ ] **Step 5: Ajouter les réglages AppSettings**

Dans `AppSettings.swift`, après `var lastCleanupAt: Date?` (fin de la section Maintenance, ~ligne 244) :

```swift
    // MARK: - Scan automatique des mails

    /// Active le scan périodique des boîtes Mail.app sélectionnées.
    var mailAutoIndexEnabled: Bool = false
    /// Boîtes scannées, tableau de `MailboxRef` encodé JSON (accesseur calculé
    /// côté Services : les modèles ne référencent pas les types Services).
    var mailAutoIndexMailboxesJSON: String = "[]"
    /// Profondeur d'historique scannée, en jours.
    var mailAutoIndexLookbackDays: Int = 90
    /// Intervalle entre deux passes, en minutes (app ouverte).
    var mailAutoIndexIntervalMinutes: Int = 60
    /// Confiance ≥ seuil → rattachement automatique.
    var mailAutoIndexAutoThreshold: Double = 0.75
    /// Confiance ≥ seuil (et < auto) → file de validation.
    var mailAutoIndexSuggestThreshold: Double = 0.45
    /// Fin de la dernière passe de scan.
    var mailAutoIndexLastScanAt: Date?
    /// Résumé lisible de la dernière passe (« 3 rattachés, 2 suggérés… »).
    var mailAutoIndexLastScanStatus: String = ""
```

- [ ] **Step 6: MailboxRef Codable**

Dans `MailService.swift` :

```swift
struct MailboxRef: Identifiable, Hashable, Codable {
```

- [ ] **Step 7: Vérifier que les tests passent**

Run: `swift test --filter MailScanModelsTests 2>&1 | tail -5`
Expected: PASS (4 tests)

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Models/ProjectMailModels.swift OneToOne/Models/SchemaVersions.swift OneToOne/Models/AppSettings.swift OneToOne/Services/MailService.swift Tests/MailScanModelsTests.swift
git commit -m "feat(mail-scan): modèles MailIndexSuggestion/MailScanRecord + réglages AppSettings"
```

---

### Task 5: MailScanStore (dédup, purge, orphelins)

**Files:**
- Create: `OneToOne/Services/MailScanStore.swift`
- Test: `Tests/MailScanStoreTests.swift`

**Interfaces:**
- Consumes: `MailScanRecord`, `MailIndexSuggestion`, `ProjectMail` (Task 4).
- Produces (utilisé par Task 9) :
  - `MailScanStore.knownMessageIds(in context: ModelContext) -> Set<String>` (union ProjectMail + suggestions + records)
  - `MailScanStore.record(_ messageId: String, verdict: MailScanVerdict, in context: ModelContext)`
  - `MailScanStore.setVerdict(_ messageId: String, verdict: MailScanVerdict, in context: ModelContext)` (upsert : mute le record existant ou en crée un — utilisé à la validation/ignore d'une suggestion)
  - `MailScanStore.purgeRecords(olderThanDays days: Int, in context: ModelContext) -> Int`
  - `MailScanStore.deleteOrphanSuggestions(in context: ModelContext) -> Int`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/MailScanStoreTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailScanStoreTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func makeSuggestion(_ messageId: String) -> MailIndexSuggestion {
        MailIndexSuggestion(messageId: messageId, accountName: "Pro", mailbox: "INBOX",
                            subject: "s", sender: "a@ex.com", dateReceived: Date())
    }

    func test_knownMessageIds_unionDesTroisSources() throws {
        let mail = ProjectMail(messageId: "mail-1", accountName: "Pro", mailbox: "INBOX",
                               subject: "s", sender: "a@ex.com")
        context.insert(mail)
        context.insert(makeSuggestion("sugg-1"))
        context.insert(MailScanRecord(messageId: "rec-1", verdict: .ignored))
        try context.save()

        let known = MailScanStore.knownMessageIds(in: context)
        XCTAssertEqual(known, Set(["mail-1", "sugg-1", "rec-1"]))
    }

    func test_purgeRecords_supprimeSeulementLesVieux() throws {
        let old = MailScanRecord(messageId: "old", verdict: .ignored,
                                 evaluatedAt: Date().addingTimeInterval(-200 * 86_400))
        let recent = MailScanRecord(messageId: "recent", verdict: .attached)
        context.insert(old)
        context.insert(recent)
        try context.save()

        let purged = MailScanStore.purgeRecords(olderThanDays: 120, in: context)
        XCTAssertEqual(purged, 1)
        let remaining = try context.fetch(FetchDescriptor<MailScanRecord>())
        XCTAssertEqual(remaining.map(\.messageId), ["recent"])
    }

    func test_setVerdict_upsert() throws {
        context.insert(MailScanRecord(messageId: "m1", verdict: .suggested))
        try context.save()

        // Record existant → muté.
        MailScanStore.setVerdict("m1", verdict: .attached, in: context)
        // Record absent (ex. purgé) → créé.
        MailScanStore.setVerdict("m2", verdict: .ignored, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<MailScanRecord>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.messageId == "m1" })?.verdict, .attached)
        XCTAssertEqual(all.first(where: { $0.messageId == "m2" })?.verdict, .ignored)
    }

    func test_deleteOrphanSuggestions_supprimeLesSansProjet() throws {
        let project = Project(code: "P1", name: "Alpha", domain: "IT", phase: "Run")
        context.insert(project)
        let withProject = makeSuggestion("s-ok")
        withProject.suggestedProject = project
        let orphan = makeSuggestion("s-orphan") // suggestedProject == nil
        context.insert(withProject)
        context.insert(orphan)
        try context.save()

        let deleted = MailScanStore.deleteOrphanSuggestions(in: context)
        XCTAssertEqual(deleted, 1)
        let remaining = try context.fetch(FetchDescriptor<MailIndexSuggestion>())
        XCTAssertEqual(remaining.map(\.messageId), ["s-ok"])
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailScanStoreTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'MailScanStore' in scope`)

- [ ] **Step 3: Implémenter MailScanStore**

Créer `OneToOne/Services/MailScanStore.swift` :

```swift
import Foundation
import SwiftData

/// Accès aux traces du scan automatique de mails : dédup des messages déjà
/// évalués, purge des vieux records, nettoyage des suggestions orphelines.
@MainActor
enum MailScanStore {

    /// Tous les `messageId` déjà connus : mails rattachés, suggestions en
    /// attente, mails évalués (ignorés inclus). Un mail dans cet ensemble
    /// n'est jamais ré-évalué par le scan.
    static func knownMessageIds(in context: ModelContext) -> Set<String> {
        let mails = (try? context.fetch(FetchDescriptor<ProjectMail>())) ?? []
        let suggestions = (try? context.fetch(FetchDescriptor<MailIndexSuggestion>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<MailScanRecord>())) ?? []
        return Set(mails.map(\.messageId))
            .union(suggestions.map(\.messageId))
            .union(records.map(\.messageId))
    }

    /// Insère la trace d'évaluation d'un mail (sans save : l'appelant groupe).
    static func record(_ messageId: String, verdict: MailScanVerdict, in context: ModelContext) {
        context.insert(MailScanRecord(messageId: messageId, verdict: verdict))
    }

    /// Upsert du verdict d'un mail : mute le record existant, ou en crée un si
    /// absent (ex. purgé entre-temps). Utilisé à la validation / l'ignore d'une
    /// suggestion pour tracer le verdict final sans perdre la dédup.
    static func setVerdict(_ messageId: String, verdict: MailScanVerdict, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<MailScanRecord>())) ?? []
        if let existing = all.first(where: { $0.messageId == messageId }) {
            existing.verdict = verdict
            existing.evaluatedAt = Date()
        } else {
            context.insert(MailScanRecord(messageId: messageId, verdict: verdict))
        }
    }

    /// Purge les records plus vieux que `days` jours. Un mail hors fenêtre de
    /// scan ne peut plus réapparaître : sa trace est inutile.
    @discardableResult
    static func purgeRecords(olderThanDays days: Int, in context: ModelContext) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let all = (try? context.fetch(FetchDescriptor<MailScanRecord>())) ?? []
        let old = all.filter { $0.evaluatedAt < cutoff }
        old.forEach { context.delete($0) }
        return old.count
    }

    /// Supprime les suggestions dont le projet a disparu (relation nullifiée).
    @discardableResult
    static func deleteOrphanSuggestions(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<MailIndexSuggestion>())) ?? []
        let orphans = all.filter { $0.suggestedProject == nil }
        orphans.forEach { context.delete($0) }
        return orphans.count
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `swift test --filter MailScanStoreTests 2>&1 | tail -5`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MailScanStore.swift Tests/MailScanStoreTests.swift
git commit -m "feat(mail-scan): MailScanStore (dédup messageId, purge, suggestions orphelines)"
```

---

### Task 6: MailService — scan des mails lus avec fenêtre d'historique

**Files:**
- Modify: `OneToOne/Services/MailService.swift`
- Test: `Tests/MailAutoScanScriptTests.swift`

**Interfaces:**
- Consumes: `runAppleScript`, `parseList`, `escape` (privés existants — la nouvelle fonction vit dans le même fichier), `MailboxRef`.
- Produces (utilisé par Task 9) :
  - `MailService.listRecentRead(limit: Int = 2000, lookbackDays: Int, mailbox: MailboxRef) async throws -> [MailSnippet]` — `limit` est un garde-fou, pas un réglage : quand il est atteint, l'appelant doit le signaler (cf. Task 9, statut « fenêtre tronquée »)
  - `MailService.buildAutoScanScript(limit: Int, lookbackDays: Int, mailbox: MailboxRef) -> String` (**internal**, pas private, pour être testable)

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/MailAutoScanScriptTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("MailService — script de scan automatique")
struct MailAutoScanScriptTests {

    private let mailbox = MailboxRef(accountName: "Pro \"April\"", mailboxName: "INBOX")

    @Test("Le script filtre sur read status et le cutoff en jours")
    func filtresLusEtCutoff() {
        let script = MailService.buildAutoScanScript(limit: 200, lookbackDays: 90, mailbox: mailbox)
        #expect(script.contains("read status of m) is true"))
        #expect(script.contains("set theCutoff to (current date) - (90 * days)"))
        #expect(script.contains("set theLimit to 200"))
        #expect(script.contains("exit repeat"))
    }

    @Test("Compte et boîte ciblés exactement, avec échappement des guillemets")
    func cibleCompteEtBoite() {
        let script = MailService.buildAutoScanScript(limit: 10, lookbackDays: 30, mailbox: mailbox)
        #expect(script.contains(#"name of acct is "Pro \"April\"""#))
        #expect(script.contains(#"name of mbx is "INBOX""#))
    }

    @Test("Le script émet les 7 champs attendus par parseList")
    func formatDeSortie() {
        let script = MailService.buildAutoScanScript(limit: 10, lookbackDays: 30, mailbox: mailbox)
        // même protocole que buildListScript : messageId, compte, boîte, sujet,
        // expéditeur, date, aperçu — séparés par |⎯| et terminés par ‡
        #expect(script.contains("|⎯|"))
        #expect(script.contains("‡"))
        #expect(script.contains("excerpt of m"))
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailAutoScanScriptTests 2>&1 | tail -5`
Expected: FAIL (`type 'MailService' has no member 'buildAutoScanScript'`)

- [ ] **Step 3: Implémenter buildAutoScanScript + listRecentRead**

Dans `MailService.swift`, après `listRecent` :

```swift
    // MARK: - Scan automatique (mails lus, fenêtre d'historique)

    /// Liste les messages **lus** de `mailbox` reçus dans les `lookbackDays`
    /// derniers jours. Contrairement à `listRecent`, le filtrage (statut lu +
    /// date) se fait côté AppleScript ; les messages étant itérés du plus
    /// récent au plus ancien, l'itération s'arrête au premier message plus
    /// vieux que le cutoff. Le corps n'est pas chargé (preview = excerpt).
    /// `limit` est un garde-fou anti-emballement : s'il est atteint, la fenêtre
    /// est tronquée (les mails les plus anciens ne sont pas vus) — l'appelant
    /// doit le détecter (`count == limit`) et le signaler.
    static func listRecentRead(
        limit: Int = 2000,
        lookbackDays: Int,
        mailbox: MailboxRef
    ) async throws -> [MailSnippet] {
        let script = buildAutoScanScript(limit: limit, lookbackDays: lookbackDays, mailbox: mailbox)
        let raw = try await runAppleScript(script)
        return parseList(raw)
    }

    /// Construit le script du scan automatique. `internal` pour les tests.
    static func buildAutoScanScript(limit: Int, lookbackDays: Int, mailbox: MailboxRef) -> String {
        let sep = "|⎯|"
        let rowEnd = "‡"
        let accountFilter = #"name of acct is "\#(escape(mailbox.accountName))""#
        let mailboxFilter = #"name of mbx is "\#(escape(mailbox.mailboxName))""#

        return """
        tell application "Mail"
            set output to ""
            set theLimit to \(limit)
            set theCutoff to (current date) - (\(lookbackDays) * days)
            set collected to 0
            repeat with acct in accounts
                if \(accountFilter) then
                    set acctName to name of acct
                    repeat with mbx in mailboxes of acct
                        if \(mailboxFilter) then
                            set mbxName to name of mbx
                            set theMsgs to messages of mbx
                            set n to count of theMsgs
                            set i to 1
                            repeat while i <= n and collected < theLimit
                                set m to item i of theMsgs
                                try
                                    set dtv to date received of m
                                    if dtv < theCutoff then exit repeat
                                    if (read status of m) is true then
                                        set subj to subject of m
                                        set snd to (sender of m) as string
                                        set dt to dtv as string
                                        set mid to message id of m
                                        set prev to ""
                                        try
                                            set prev to (excerpt of m) as string
                                        on error
                                            set prev to ""
                                        end try
                                        set output to output & mid & "\(sep)" & acctName & "\(sep)" & mbxName & "\(sep)" & subj & "\(sep)" & snd & "\(sep)" & dt & "\(sep)" & prev & "\(rowEnd)"
                                        set collected to collected + 1
                                    end if
                                end try
                                set i to i + 1
                            end repeat
                        end if
                    end repeat
                end if
            end repeat
            return output
        end tell
        """
    }
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `swift test --filter MailAutoScanScriptTests 2>&1 | tail -5`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MailService.swift Tests/MailAutoScanScriptTests.swift
git commit -m "feat(mail-scan): MailService.listRecentRead (mails lus + fenêtre d'historique)"
```

---

### Task 7: MailProjectMatcher — heuristiques de rattachement (pur)

**Files:**
- Create: `OneToOne/Services/MailProjectMatcher.swift`
- Test: `Tests/MailProjectMatcherTests.swift`

**Interfaces:**
- Consumes: `ProjectMatchService.normalizedTokens(_:)` et `ProjectMatchService.jaroWinkler(_:_:)` (statiques internal, non-@MainActor), `ProjectMailStore.normalizedThreadTopic(for:)` (@MainActor).
- Produces (utilisé par Tasks 8 et 9) :
  - `MailProjectMatcher.ProjectEntry` : `struct { let code: String; let name: String; let collaboratorEmails: [String] }` (emails déjà lowercased)
  - `MailProjectMatcher.Verdict` : `struct Equatable { let projectCode: String?; let confidence: Double; static let none: Verdict }`
  - `MailProjectMatcher.extractEmail(fromSender sender: String) -> String?`
  - `MailProjectMatcher.match(subject: String, sender: String, projects: [ProjectEntry], threadProjectCodes: [String: String]) -> Verdict` — `threadProjectCodes` est indexé par `threadTopic` normalisé **lowercased**
  - `MailProjectMatcher.projectEntries(from projects: [Project]) -> [ProjectEntry]`

L'enum est `@MainActor` (il appelle `ProjectMailStore.normalizedThreadTopic` et lit des `Project`), mais `match` ne touche pas SwiftData : les tests l'exercent avec des fixtures pures.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/MailProjectMatcherTests.swift` :

```swift
import XCTest
@testable import OneToOne

@MainActor
final class MailProjectMatcherTests: XCTestCase {

    private let projects = [
        MailProjectMatcher.ProjectEntry(code: "REFSI", name: "Refonte SI Courtage",
                                        collaboratorEmails: ["alice@april.com"]),
        MailProjectMatcher.ProjectEntry(code: "DATA24", name: "Plateforme Data",
                                        collaboratorEmails: ["bob@april.com"]),
    ]

    func test_extractEmail_formatsCourants() {
        XCTAssertEqual(MailProjectMatcher.extractEmail(fromSender: "Alice Dupont <Alice@April.com>"),
                       "alice@april.com")
        XCTAssertEqual(MailProjectMatcher.extractEmail(fromSender: "bob@april.com"), "bob@april.com")
        XCTAssertNil(MailProjectMatcher.extractEmail(fromSender: "Alice Dupont"))
    }

    func test_continuiteDeFil_gagneAvecConfiance095() {
        let v = MailProjectMatcher.match(
            subject: "Re: Point hebdo courtage",
            sender: "inconnu@ext.com",
            projects: projects,
            threadProjectCodes: ["point hebdo courtage": "DATA24"]
        )
        XCTAssertEqual(v.projectCode, "DATA24")
        XCTAssertEqual(v.confidence, 0.95, accuracy: 0.001)
    }

    func test_matchSujet_nomDeProjetDansLeSujet() {
        let v = MailProjectMatcher.match(
            subject: "Avancement Refonte SI Courtage — sprint 4",
            sender: "inconnu@ext.com",
            projects: projects,
            threadProjectCodes: [:]
        )
        XCTAssertEqual(v.projectCode, "REFSI")
        XCTAssertGreaterThanOrEqual(v.confidence, 0.75)
    }

    func test_codeProjetCiteDansLeSujet_score09() {
        let v = MailProjectMatcher.match(
            subject: "[DATA24] livraison lot 2",
            sender: "inconnu@ext.com",
            projects: projects,
            threadProjectCodes: [:]
        )
        XCTAssertEqual(v.projectCode, "DATA24")
        XCTAssertGreaterThanOrEqual(v.confidence, 0.9)
    }

    func test_bonusEmailExpediteur_rehausseUnMatchSujet() {
        let sans = MailProjectMatcher.match(
            subject: "Question data", sender: "inconnu@ext.com",
            projects: projects, threadProjectCodes: [:]
        )
        let avec = MailProjectMatcher.match(
            subject: "Question data", sender: "Bob <bob@april.com>",
            projects: projects, threadProjectCodes: [:]
        )
        XCTAssertGreaterThan(avec.confidence, sans.confidence)
        XCTAssertEqual(avec.projectCode, "DATA24")
    }

    func test_emailSeul_matchFaible() {
        let v = MailProjectMatcher.match(
            subject: "Déjeuner demain ?", sender: "alice@april.com",
            projects: projects, threadProjectCodes: [:]
        )
        XCTAssertEqual(v.projectCode, "REFSI")
        XCTAssertEqual(v.confidence, 0.4, accuracy: 0.001)
    }

    func test_aucunMatch_verdictNone() {
        let v = MailProjectMatcher.match(
            subject: "Newsletter hebdomadaire", sender: "news@externe.com",
            projects: projects, threadProjectCodes: [:]
        )
        XCTAssertNil(v.projectCode)
        XCTAssertEqual(v.confidence, 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailProjectMatcherTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'MailProjectMatcher' in scope`)

- [ ] **Step 3: Implémenter MailProjectMatcher**

Créer `OneToOne/Services/MailProjectMatcher.swift` :

```swift
import Foundation

/// Heuristiques de rattachement mail → projet (étage 1 du matching, sans LLM).
/// Trois signaux, le meilleur score gagne :
///   1. continuité de fil (threadTopic déjà rattaché) — confiance 0.95 ;
///   2. sujet ↔ nom/code projet (tokens + Jaro-Winkler, code cité = 0.9) ;
///   3. expéditeur ↔ emails des collaborateurs du projet (bonus +0.2, ou
///      match faible seul à 0.4).
/// Fonctions pures sur des entrées préparées — testables sans ModelContext.
@MainActor
enum MailProjectMatcher {

    struct ProjectEntry: Equatable {
        let code: String
        let name: String
        /// Emails des collaborateurs rattachés, déjà lowercased.
        let collaboratorEmails: [String]
    }

    struct Verdict: Equatable {
        let projectCode: String?
        let confidence: Double
        static let none = Verdict(projectCode: nil, confidence: 0)
    }

    static let threadContinuityConfidence = 0.95
    static let codeInSubjectConfidence = 0.9
    static let senderEmailBonus = 0.2
    static let senderEmailOnlyConfidence = 0.4

    /// Extrait l'adresse email d'un champ expéditeur Mail.app
    /// (« Nom <email> » ou email nu). Retourne nil si aucune adresse.
    static func extractEmail(fromSender sender: String) -> String? {
        if let lt = sender.firstIndex(of: "<"), let gt = sender.firstIndex(of: ">"), lt < gt {
            let inner = String(sender[sender.index(after: lt)..<gt])
                .trimmingCharacters(in: .whitespaces)
            return inner.contains("@") ? inner.lowercased() : nil
        }
        let trimmed = sender.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") ? trimmed.lowercased() : nil
    }

    /// Prépare les entrées de matching depuis les projets actifs.
    static func projectEntries(from projects: [Project]) -> [ProjectEntry] {
        projects.filter { !$0.isArchived }.map { p in
            var emails = p.collaboratorEntries.compactMap { entry in
                entry.collaborator.map { $0.email.lowercased() }
            }
            if let e = p.projectManager?.email.lowercased() { emails.append(e) }
            if let e = p.technicalArchitect?.email.lowercased() { emails.append(e) }
            return ProjectEntry(code: p.code, name: p.name,
                                collaboratorEmails: emails.filter { !$0.isEmpty })
        }
    }

    /// Verdict heuristique pour un mail. `threadProjectCodes` : threadTopic
    /// normalisé lowercased → code projet (fils déjà rattachés).
    static func match(
        subject: String,
        sender: String,
        projects: [ProjectEntry],
        threadProjectCodes: [String: String]
    ) -> Verdict {
        // 1. Continuité de fil.
        let topic = ProjectMailStore.normalizedThreadTopic(for: subject).lowercased()
        if !topic.isEmpty, let code = threadProjectCodes[topic] {
            return Verdict(projectCode: code, confidence: threadContinuityConfidence)
        }

        // 2 + 3. Sujet et expéditeur, meilleur projet gagnant.
        let senderEmail = extractEmail(fromSender: sender)
        let subjectTokens = ProjectMatchService.normalizedTokens(subject)
        let subjectSet = Set(subjectTokens)

        var best = Verdict.none
        for project in projects {
            var score = 0.0

            let nameTokens = ProjectMatchService.normalizedTokens(project.name)
            let nameSet = Set(nameTokens)
            if !subjectSet.isEmpty, !nameSet.isEmpty {
                let overlap = Double(subjectSet.intersection(nameSet).count)
                    / Double(min(subjectSet.count, nameSet.count))
                // ⚠️ jaroWinkler n'est jamais ≈0 entre deux phrases quelconques
                // (0.5–0.65 sur des sujets sans aucun rapport) : il n'est
                // compté que si au moins un token est commun — sinon 0.
                // (Le repo applique la même prudence : bestProjectMatch n'est
                // accepté qu'à ≥ 0.7 côté appelant.)
                if overlap > 0 {
                    let jw = ProjectMatchService.jaroWinkler(
                        subjectTokens.joined(separator: " "),
                        nameTokens.joined(separator: " "))
                    score = max(overlap, jw)
                }
            }

            // Code projet cité tel quel dans le sujet (ex. « [DATA24] … »).
            let codeTokens = Set(ProjectMatchService.normalizedTokens(project.code))
            if !codeTokens.isEmpty, codeTokens.isSubset(of: subjectSet) {
                score = max(score, codeInSubjectConfidence)
            }

            // Expéditeur membre du projet : bonus, ou match faible seul.
            if let email = senderEmail, project.collaboratorEmails.contains(email) {
                score = score > 0 ? min(1.0, score + senderEmailBonus)
                                  : senderEmailOnlyConfidence
            }

            if score > best.confidence {
                best = Verdict(projectCode: project.code, confidence: score)
            }
        }
        return best
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `swift test --filter MailProjectMatcherTests 2>&1 | tail -5`
Expected: PASS (7 tests)

⚠️ Le gate `overlap > 0` avant de compter le Jaro-Winkler est **essentiel** : sans lui, `jaroWinkler` retourne 0.5–0.65 entre phrases sans aucun rapport et deux tests échouent (`test_emailSeul` : 0.768 au lieu de 0.4 ; `test_aucunMatch` : DATA24/0.635 au lieu de nil/0) — et en production, des mails hors sujet seraient rattachés automatiquement. Scores attendus avec le gate (vérifiés par simulation) : matchSujet 1.0, code 0.9, bonus 0.5→0.7, emailSeul 0.4, aucunMatch 0.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MailProjectMatcher.swift Tests/MailProjectMatcherTests.swift
git commit -m "feat(mail-scan): MailProjectMatcher — heuristiques fil/sujet/expéditeur"
```

---

### Task 8: MailLLMClassifier — étage Gemma 4 pour les cas ambigus

**Files:**
- Create: `OneToOne/Services/MailLLMClassifier.swift`
- Test: `Tests/MailLLMClassifierTests.swift`

**Interfaces:**
- Consumes: `DirectLLMClient.send(prompt:modelRepo:onProgress:)`, `AppSettings.directModelRepo`, `MailProjectMatcher.Verdict` (Task 7).
- Produces (utilisé par Task 9) :
  - `MailLLMClassifier.Candidate` : `struct { let code: String; let name: String; let collaborators: [String] }` (le spec exige code + nom + collaborateurs dans le prompt)
  - `MailLLMClassifier.ClassifyResult` : `enum Equatable { case verdict(MailProjectMatcher.Verdict); case unparseable; case unavailable }` — sémantique spec §4 : réponse LLM inexploitable → le mail sera **ignoré** ; LLM indisponible (erreur de chargement/génération) → repli sur le verdict heuristique
  - `MailLLMClassifier.buildPrompt(subject:sender:preview:candidates:) -> String`
  - `MailLLMClassifier.parseVerdict(_ raw: String, knownCodes: Set<String>) -> MailProjectMatcher.Verdict?`
  - `MailLLMClassifier.classify(subject: String, sender: String, preview: String, candidates: [Candidate], settings: AppSettings, generate: ((String) async throws -> String)? = nil) async -> ClassifyResult` — `generate` nil = Gemma 4 réel via `DirectLLMClient` ; injecté dans les tests.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/MailLLMClassifierTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("MailLLMClassifier — parsing et classification")
@MainActor
struct MailLLMClassifierTests {

    private let codes: Set<String> = ["REFSI", "DATA24"]
    private let candidates = [
        MailLLMClassifier.Candidate(code: "REFSI", name: "Refonte SI Courtage",
                                    collaborators: ["alice@april.com"]),
        MailLLMClassifier.Candidate(code: "DATA24", name: "Plateforme Data",
                                    collaborators: ["bob@april.com"]),
    ]

    @Test("JSON strict")
    func jsonStrict() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": "REFSI", "confidence": 0.8}"#,
                                               knownCodes: codes)
        #expect(v == MailProjectMatcher.Verdict(projectCode: "REFSI", confidence: 0.8))
    }

    @Test("Fences markdown et texte autour")
    func fencesMarkdown() {
        let raw = """
        Voici mon analyse :
        ```json
        {"projectCode": "DATA24", "confidence": 0.55}
        ```
        """
        let v = MailLLMClassifier.parseVerdict(raw, knownCodes: codes)
        #expect(v == MailProjectMatcher.Verdict(projectCode: "DATA24", confidence: 0.55))
    }

    @Test("projectCode null → verdict sans projet")
    func codeNull() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": null, "confidence": 0.9}"#,
                                               knownCodes: codes)
        #expect(v?.projectCode == nil)
    }

    @Test("Code inconnu → traité comme aucun projet")
    func codeInconnu() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": "HALLUCINATION", "confidence": 0.9}"#,
                                               knownCodes: codes)
        #expect(v?.projectCode == nil)
    }

    @Test("Confiance bornée à [0, 1]")
    func confianceBornee() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": "REFSI", "confidence": 7}"#,
                                               knownCodes: codes)
        #expect(v?.confidence == 1.0)
    }

    @Test("JSON invalide → nil")
    func jsonInvalide() {
        #expect(MailLLMClassifier.parseVerdict("désolé, je ne peux pas", knownCodes: codes) == nil)
    }

    @Test("Le prompt contient les candidats (code, nom, collaborateurs) et exige un JSON")
    func promptComplet() {
        let p = MailLLMClassifier.buildPrompt(subject: "Su", sender: "a@b.c",
                                              preview: "Pv", candidates: candidates)
        #expect(p.contains("REFSI"))
        #expect(p.contains("Plateforme Data"))
        #expect(p.contains("bob@april.com"))
        #expect(p.contains("projectCode"))
        #expect(p.contains("Su"))
    }

    @Test("classify passe par generate injecté et parse le résultat")
    func classifyAvecStub() async {
        let settings = AppSettings()
        let r = await MailLLMClassifier.classify(
            subject: "Su", sender: "a@b.c", preview: "Pv",
            candidates: candidates, settings: settings,
            generate: { _ in #"{"projectCode": "REFSI", "confidence": 0.7}"# }
        )
        #expect(r == .verdict(MailProjectMatcher.Verdict(projectCode: "REFSI", confidence: 0.7)))
    }

    @Test("Réponse inexploitable → .unparseable (le mail sera ignoré)")
    func classifyInexploitable() async {
        let settings = AppSettings()
        let r = await MailLLMClassifier.classify(
            subject: "Su", sender: "a@b.c", preview: "Pv",
            candidates: candidates, settings: settings,
            generate: { _ in "désolé, je ne peux pas répondre en JSON" }
        )
        #expect(r == .unparseable)
    }

    @Test("LLM indisponible → .unavailable (repli heuristique)")
    func classifyErreur() async {
        let settings = AppSettings()
        let r = await MailLLMClassifier.classify(
            subject: "Su", sender: "a@b.c", preview: "Pv",
            candidates: candidates, settings: settings,
            generate: { _ in throw NSError(domain: "stub", code: -1) }
        )
        #expect(r == .unavailable)
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailLLMClassifierTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'MailLLMClassifier' in scope`)

- [ ] **Step 3: Implémenter MailLLMClassifier**

Il n'existe **pas** de helper JSON-LLM partagé dans le repo (trois copies privées) — on réplique le pattern le plus robuste (`AIReportService` : strip fence + extraction `{…}` équilibrée).

Créer `OneToOne/Services/MailLLMClassifier.swift` :

```swift
import Foundation
import os

private let mailLLMLog = Logger(subsystem: "com.onetoone.app", category: "mail-llm")

/// Étage 2 du matching mail → projet : classification par le LLM local
/// (Gemma 4 via `DirectLLMClient`) des mails que les heuristiques n'ont pas
/// tranchés. Réponse attendue : JSON strict {"projectCode": ..., "confidence": ...}.
@MainActor
enum MailLLMClassifier {

    struct Candidate {
        let code: String
        let name: String
        /// Emails des collaborateurs du projet (signal expéditeur ↔ équipe).
        let collaborators: [String]
    }

    /// Résultat de classification (sémantique spec §4) :
    /// `.verdict` remplace le verdict heuristique ; `.unparseable` → le mail
    /// sera ignoré ; `.unavailable` (LLM en échec) → repli heuristique.
    enum ClassifyResult: Equatable {
        case verdict(MailProjectMatcher.Verdict)
        case unparseable
        case unavailable
    }

    /// Prompt de classification. Les candidats sont limités par l'appelant
    /// (tous les projets actifs — volume faible pour un portefeuille).
    static func buildPrompt(
        subject: String,
        sender: String,
        preview: String,
        candidates: [Candidate]
    ) -> String {
        let list = candidates
            .map { c in
                let team = c.collaborators.isEmpty ? "" : " (équipe : \(c.collaborators.joined(separator: ", ")))"
                return "- \(c.code) : \(c.name)\(team)"
            }
            .joined(separator: "\n")
        return """
        Tu classes un email professionnel vers un projet d'un portefeuille.

        Email :
        - Sujet : \(subject)
        - Expéditeur : \(sender)
        - Aperçu : \(preview)

        Projets candidats (code : nom, équipe) :
        \(list)

        Réponds UNIQUEMENT avec un objet JSON, sans autre texte :
        {"projectCode": "<code du projet>" ou null si aucun ne correspond, "confidence": <nombre entre 0 et 1>}
        """
    }

    /// Parse la réponse du LLM. Tolère les fences markdown et le texte autour
    /// (extraction du premier bloc {…} équilibré). Un code inconnu du
    /// portefeuille (hallucination) est traité comme « aucun projet ».
    /// Retourne nil si aucun JSON exploitable.
    static func parseVerdict(_ raw: String, knownCodes: Set<String>) -> MailProjectMatcher.Verdict? {
        struct Resp: Decodable {
            let projectCode: String?
            let confidence: Double?
        }
        let cleaned = stripCodeFence(raw)
        guard let block = extractJSONBlock(from: cleaned),
              let data = block.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
            return nil
        }
        let confidence = min(1.0, max(0.0, resp.confidence ?? 0))
        guard let code = resp.projectCode, knownCodes.contains(code) else {
            return MailProjectMatcher.Verdict(projectCode: nil, confidence: confidence)
        }
        return MailProjectMatcher.Verdict(projectCode: code, confidence: confidence)
    }

    /// Classifie un mail ambigu. `generate` nil → Gemma 4 réel
    /// (`DirectLLMClient`, repo = `settings.directModelRepo`).
    /// Réponse illisible → `.unparseable` (spec : le mail sera ignoré) ;
    /// erreur LLM (chargement/génération) → `.unavailable` (repli heuristique,
    /// le scan continue). Tout est loggé.
    static func classify(
        subject: String,
        sender: String,
        preview: String,
        candidates: [Candidate],
        settings: AppSettings,
        generate: ((String) async throws -> String)? = nil
    ) async -> ClassifyResult {
        let prompt = buildPrompt(subject: subject, sender: sender,
                                 preview: preview, candidates: candidates)
        do {
            let raw: String
            if let generate {
                raw = try await generate(prompt)
            } else {
                raw = try await DirectLLMClient.send(
                    prompt: prompt,
                    modelRepo: settings.directModelRepo,
                    onProgress: nil
                )
            }
            guard let verdict = parseVerdict(raw, knownCodes: Set(candidates.map(\.code))) else {
                mailLLMLog.error("classify: réponse inexploitable — \(String(raw.prefix(200)), privacy: .public)")
                return .unparseable
            }
            return .verdict(verdict)
        } catch {
            mailLLMLog.error("classify: échec LLM — \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    // MARK: - Helpers JSON (pattern AIReportService, dupliqué faute de helper partagé)

    private static func stripCodeFence(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("```") else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONBlock(from s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = start
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" {
                depth -= 1
                if depth == 0 { return String(s[start...i]) }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `swift test --filter MailLLMClassifierTests 2>&1 | tail -5`
Expected: PASS (10 tests)

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MailLLMClassifier.swift Tests/MailLLMClassifierTests.swift
git commit -m "feat(mail-scan): MailLLMClassifier — classification Gemma 4 des mails ambigus"
```

---

### Task 9: MailAutoIndexService + JobKind.mailScan + bootstrap AppDelegate

**Files:**
- Modify: `OneToOne/Services/JobQueue.swift` (case `mailScan` + concurrence)
- Modify: `OneToOne/Views/JobQueueSidebar.swift` (`jobKindLabel` + `jobIcon`)
- Create: `OneToOne/Services/MailAutoIndexService.swift`
- Modify: `OneToOne/AppDelegate.swift` (bootstrap après le bloc ContactPhotoService)
- Test: `Tests/MailAutoIndexServiceTests.swift`

**Interfaces:**
- Consumes: tout ce qui précède — `MailService.listRecentRead` (T6), `MailScanStore` (T5), `MailProjectMatcher` (T7), `MailLLMClassifier` (T8), `ProjectMailStore.save(snippet:body:attachments:to:context:)`, `MailService.fetchBody(messageId:accountName:mailbox:)`, `MailService.saveAttachments(messageId:accountName:mailbox:)`, `JobQueue.shared.start(kind:meetingTitle:work:)`, réglages `AppSettings` (T4).
- Produces (utilisé par Tasks 10, 11) :
  - `JobQueue.JobKind.mailScan`
  - `MailAutoIndexService.shared` (`@MainActor final class`)
  - `MailAutoIndexService.Outcome` : `enum Equatable { case attach, suggest, ignore }`
  - `static func outcome(confidence: Double, autoThreshold: Double, suggestThreshold: Double) -> Outcome` (pur)
  - `func reschedule(context: ModelContext, settings: AppSettings)` (annule et ré-arme la boucle ; désactivé → stop)
  - `func scanNow(context: ModelContext, settings: AppSettings)` (enfile un job `.mailScan` ; no-op si un scan est déjà actif)
  - `extension AppSettings { var mailAutoIndexMailboxes: [MailboxRef] }` (accesseur JSON, déclaré ici côté Services)

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/MailAutoIndexServiceTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailAutoIndexServiceTests: XCTestCase {

    func test_outcome_seuils() {
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.8, autoThreshold: 0.75, suggestThreshold: 0.45), .attach)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.75, autoThreshold: 0.75, suggestThreshold: 0.45), .attach)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.6, autoThreshold: 0.75, suggestThreshold: 0.45), .suggest)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.45, autoThreshold: 0.75, suggestThreshold: 0.45), .suggest)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.2, autoThreshold: 0.75, suggestThreshold: 0.45), .ignore)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0, autoThreshold: 0.75, suggestThreshold: 0.45), .ignore)
    }

    func test_appSettings_mailboxesAccesseurJSON() {
        let s = AppSettings()
        XCTAssertEqual(s.mailAutoIndexMailboxes, [])
        let refs = [MailboxRef(accountName: "Pro", mailboxName: "INBOX"),
                    MailboxRef(accountName: "Perso", mailboxName: "INBOX")]
        s.mailAutoIndexMailboxes = refs
        XCTAssertEqual(s.mailAutoIndexMailboxes, refs)
        // JSON invalide → tableau vide, pas de crash
        s.mailAutoIndexMailboxesJSON = "{pas-du-json"
        XCTAssertEqual(s.mailAutoIndexMailboxes, [])
    }

    func test_threadProjectCodes_construitDepuisProjectMail() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: cfg)
        let context = container.mainContext

        let project = Project(code: "REFSI", name: "Refonte SI", domain: "IT", phase: "Run")
        context.insert(project)
        let mail = ProjectMail(messageId: "m1", accountName: "Pro", mailbox: "INBOX",
                               subject: "Re: Point hebdo", sender: "a@ex.com",
                               threadTopic: "Point hebdo")
        mail.project = project
        context.insert(mail)
        try context.save()

        let map = MailAutoIndexService.threadProjectCodes(in: context)
        XCTAssertEqual(map["point hebdo"], "REFSI")
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailAutoIndexServiceTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'MailAutoIndexService' in scope`)

- [ ] **Step 3: Ajouter le JobKind mailScan**

Dans `JobQueue.swift` :

```swift
    enum JobKind: String { case transcription, report, audioEdit, diarization, maintenance, mailScan }
```

Dans `maxConcurrentByKind` :

```swift
        .maintenance:   1,
        .mailScan:      1
```

Dans `JobQueueSidebar.swift`, compléter les deux switch exhaustifs :

```swift
    // jobKindLabel
    case .mailScan:      return "Scan mails"
    // jobIcon (branche .running)
    case .mailScan:      Image(systemName: "envelope.badge")
```

(Adapter la forme exacte de `jobIcon` au style des cases voisins du fichier.)

- [ ] **Step 4: Implémenter MailAutoIndexService**

Créer `OneToOne/Services/MailAutoIndexService.swift` :

```swift
import Foundation
import SwiftData
import os

private let mailScanLog = Logger(subsystem: "com.onetoone.app", category: "mail-scan")

// MARK: - Accesseur réglage boîtes (côté Services : AppSettings ne connaît pas MailboxRef)

extension AppSettings {
    /// Boîtes scannées par le scan automatique (round-trip JSON).
    var mailAutoIndexMailboxes: [MailboxRef] {
        get {
            (try? JSONDecoder().decode([MailboxRef].self,
                                       from: Data(mailAutoIndexMailboxesJSON.utf8))) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                mailAutoIndexMailboxesJSON = json
            }
        }
    }
}

// MARK: - MailAutoIndexService

/// Orchestrateur du scan automatique de mails : boucle périodique (pattern
/// ContactPhotoService), pipeline scan → matching (heuristiques puis Gemma 4)
/// → décision (rattacher / suggérer / ignorer) exécuté dans un job `.mailScan`.
@MainActor
final class MailAutoIndexService {

    static let shared = MailAutoIndexService()
    private init() {}

    private var scanTask: Task<Void, Never>?
    private var activeScanJobID: UUID?

    enum Outcome: Equatable {
        case attach, suggest, ignore
    }

    /// Décision par seuils — pur, testé.
    static func outcome(confidence: Double, autoThreshold: Double, suggestThreshold: Double) -> Outcome {
        if confidence >= autoThreshold { return .attach }
        if confidence >= suggestThreshold { return .suggest }
        return .ignore
    }

    /// Carte threadTopic (lowercased) → code projet des fils déjà rattachés.
    static func threadProjectCodes(in context: ModelContext) -> [String: String] {
        let mails = (try? context.fetch(FetchDescriptor<ProjectMail>())) ?? []
        var map: [String: String] = [:]
        for mail in mails {
            guard let code = mail.project?.code else { continue }
            let topic = mail.threadTopic.lowercased()
            guard !topic.isEmpty, map[topic] == nil else { continue }
            map[topic] = code
        }
        return map
    }

    /// Annule et ré-arme la boucle périodique selon les réglages.
    /// Désactivé → arrêt. Lance aussi une passe immédiate si la dernière
    /// remonte à plus d'un intervalle (ou n'a jamais eu lieu).
    func reschedule(context: ModelContext, settings: AppSettings) {
        scanTask?.cancel()
        scanTask = nil
        guard settings.mailAutoIndexEnabled else { return }

        let interval = max(5, settings.mailAutoIndexIntervalMinutes)
        let due = settings.mailAutoIndexLastScanAt
            .map { Date().timeIntervalSince($0) > Double(interval) * 60 } ?? true
        if due { scanNow(context: context, settings: settings) }

        let nanos = UInt64(interval) * 60 * 1_000_000_000
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                await MainActor.run { self?.scanNow(context: context, settings: settings) }
            }
        }
    }

    /// Enfile une passe de scan dans la JobQueue. No-op si une passe est déjà
    /// active ou si aucune boîte n'est sélectionnée.
    func scanNow(context: ModelContext, settings: AppSettings) {
        let queue = JobQueue.shared
        if let id = activeScanJobID,
           queue.jobs.contains(where: { $0.id == id && !$0.status.isTerminal }) {
            return
        }
        let mailboxes = settings.mailAutoIndexMailboxes
        guard settings.mailAutoIndexEnabled, !mailboxes.isEmpty else { return }

        let jobID = queue.start(kind: .mailScan, meetingTitle: "Scan des mails") { jobID in
            try await MailAutoIndexService.shared.runScan(
                jobID: jobID, mailboxes: mailboxes,
                context: context, settings: settings
            )
        }
        activeScanJobID = jobID
    }

    /// Corps du job de scan. Erreurs par mail non fatales (comptées, le mail
    /// reste sans record → re-tenté à la prochaine passe) ; le job échoue en
    /// fin de passe si des erreurs ont eu lieu, avec un statut explicite.
    private func runScan(
        jobID: UUID,
        mailboxes: [MailboxRef],
        context: ModelContext,
        settings: AppSettings
    ) async throws {
        let queue = JobQueue.shared
        let autoThreshold = settings.mailAutoIndexAutoThreshold
        let suggestThreshold = settings.mailAutoIndexSuggestThreshold
        let lookback = settings.mailAutoIndexLookbackDays

        MailScanStore.deleteOrphanSuggestions(in: context)

        // Entrées de matching préparées une fois par passe.
        // ⚠️ Project.code n'a pas de contrainte d'unicité : uniquingKeysWith
        // obligatoire (uniqueKeysWithValues crasherait sur un doublon), et on
        // exclut les archivés (cohérent avec projectEntries).
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let entries = MailProjectMatcher.projectEntries(from: projects)
        let projectByCode = Dictionary(
            projects.filter { !$0.isArchived }.map { ($0.code, $0) },
            uniquingKeysWith: { first, _ in first })
        let candidates = entries.map {
            MailLLMClassifier.Candidate(code: $0.code, name: $0.name,
                                        collaborators: $0.collaboratorEmails)
        }
        var threadCodes = Self.threadProjectCodes(in: context)
        // `var` + insertions au fil de la passe : un même messageId présent
        // dans deux boîtes sélectionnées n'est évalué qu'une fois.
        var known = MailScanStore.knownMessageIds(in: context)

        var attached = 0, suggested = 0, ignored = 0, errors = 0
        var truncatedMailboxes: [String] = []

        for (boxIndex, mailbox) in mailboxes.enumerated() {
            try Task.checkCancellation()
            queue.updateProgress(jobID, fraction: Double(boxIndex) / Double(mailboxes.count),
                                 status: "Lecture de \(mailbox.displayName)…")

            let scanLimit = 2000
            let snippets: [MailSnippet]
            do {
                snippets = try await MailService.listRecentRead(
                    limit: scanLimit, lookbackDays: lookback, mailbox: mailbox)
            } catch {
                // Permission Automation refusée / Mail indisponible → échec franc.
                throw error
            }
            if snippets.count >= scanLimit {
                // Garde-fou atteint : les mails les plus anciens de la fenêtre
                // n'ont pas été vus — signalé, jamais silencieux.
                truncatedMailboxes.append(mailbox.displayName)
                mailScanLog.warning("scan \(mailbox.displayName, privacy: .public): garde-fou 2000 mails atteint, fenêtre tronquée")
            }
            let fresh = snippets.filter { !known.contains($0.messageId) }
            mailScanLog.info("scan \(mailbox.displayName, privacy: .public): \(snippets.count) lus, \(fresh.count) nouveaux")

            for (i, snippet) in fresh.enumerated() {
                try Task.checkCancellation()
                queue.updateProgress(
                    jobID,
                    fraction: (Double(boxIndex) + Double(i) / Double(max(1, fresh.count)))
                        / Double(mailboxes.count),
                    status: "\(mailbox.displayName) — \(i + 1)/\(fresh.count)")

                // Étage 1 : heuristiques.
                var verdict = MailProjectMatcher.match(
                    subject: snippet.subject, sender: snippet.sender,
                    projects: entries, threadProjectCodes: threadCodes)
                var forceIgnore = false

                // Étage 2 : Gemma 4, seulement sous le seuil auto. Sémantique
                // spec §4 : le verdict LLM REMPLACE l'heuristique (il peut
                // rétrograder un match douteux) ; réponse inexploitable →
                // ignoré ; LLM indisponible → repli heuristique.
                if verdict.confidence < autoThreshold, !candidates.isEmpty {
                    switch await MailLLMClassifier.classify(
                        subject: snippet.subject, sender: snippet.sender,
                        preview: snippet.preview, candidates: candidates,
                        settings: settings) {
                    case .verdict(let llm): verdict = llm
                    case .unparseable:      forceIgnore = true
                    case .unavailable:      break // verdict heuristique conservé
                    }
                }

                let project = verdict.projectCode.flatMap { projectByCode[$0] }
                let decision: Outcome = (forceIgnore || project == nil)
                    ? .ignore
                    : Self.outcome(confidence: verdict.confidence,
                                   autoThreshold: autoThreshold,
                                   suggestThreshold: suggestThreshold)

                switch decision {
                case .attach:
                    do {
                        let body = try await MailService.fetchBody(
                            messageId: snippet.messageId,
                            accountName: snippet.accountName,
                            mailbox: snippet.mailbox)
                        let attachments = (try? await MailService.saveAttachments(
                            messageId: snippet.messageId,
                            accountName: snippet.accountName,
                            mailbox: snippet.mailbox)) ?? []
                        _ = try await ProjectMailStore.save(
                            snippet: snippet, body: body,
                            attachments: attachments,
                            to: project!, context: context)
                        MailScanStore.record(snippet.messageId, verdict: .attached, in: context)
                        known.insert(snippet.messageId)
                        // Le fil devient un signal de continuité pour la suite de la passe.
                        let topic = ProjectMailStore.normalizedThreadTopic(for: snippet.subject).lowercased()
                        if !topic.isEmpty, threadCodes[topic] == nil {
                            threadCodes[topic] = project!.code
                        }
                        attached += 1
                    } catch {
                        // Embedding indisponible, AppleScript en échec… :
                        // PAS de record → re-tenté à la prochaine passe.
                        // ⚠️ ProjectMailStore.save persiste le ProjectMail AVANT
                        // l'embedding (reindex) : si l'embedding a échoué, un
                        // ProjectMail sans chunks a pu être sauvé — il rendrait
                        // le messageId « connu » à jamais sans jamais être
                        // indexé. On l'annule explicitement.
                        if let halfSaved = ((try? context.fetch(FetchDescriptor<ProjectMail>())) ?? [])
                            .first(where: { $0.messageId == snippet.messageId && $0.chunks.isEmpty }) {
                            context.delete(halfSaved)
                            try? context.save()
                        }
                        errors += 1
                        mailScanLog.error("rattachement échoué \(snippet.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                case .suggest:
                    let suggestion = MailIndexSuggestion(
                        messageId: snippet.messageId,
                        accountName: snippet.accountName,
                        mailbox: snippet.mailbox,
                        subject: snippet.subject,
                        sender: snippet.sender,
                        dateReceived: snippet.dateReceived,
                        preview: snippet.preview,
                        confidence: verdict.confidence)
                    suggestion.suggestedProject = project
                    context.insert(suggestion)
                    MailScanStore.record(snippet.messageId, verdict: .suggested, in: context)
                    known.insert(snippet.messageId)
                    suggested += 1
                case .ignore:
                    MailScanStore.record(snippet.messageId, verdict: .ignored, in: context)
                    known.insert(snippet.messageId)
                    ignored += 1
                }
                try? context.save()
            }
        }

        MailScanStore.purgeRecords(olderThanDays: lookback + 30, in: context)
        let status = "\(attached) rattaché(s), \(suggested) suggéré(s), \(ignored) ignoré(s)"
            + (errors > 0 ? ", \(errors) erreur(s)" : "")
            + (truncatedMailboxes.isEmpty ? "" : " — fenêtre tronquée : \(truncatedMailboxes.joined(separator: ", "))")
        settings.mailAutoIndexLastScanAt = Date()
        settings.mailAutoIndexLastScanStatus = status
        try? context.save()
        mailScanLog.info("scan terminé: \(status, privacy: .public)")

        if errors > 0 {
            struct ScanError: LocalizedError {
                let message: String
                var errorDescription: String? { message }
            }
            throw ScanError(message: "\(errors) mail(s) en erreur — re-tentés à la prochaine passe (\(status))")
        }
        queue.updateProgress(jobID, fraction: 1.0, status: status)
    }
}
```

⚠️ Notes d'implémentation : `runScan` est `@MainActor` (classe) mais tout le travail lourd (`listRecentRead`, `fetchBody`, LLM, embeddings) est `await` sur des services off-main ou des containers MLX — la main queue n'est pas bloquée. `ProjectMailStore.save` gère l'upsert + chunking + embedding (pipeline existant, inchangé).

- [ ] **Step 5: Bootstrap dans AppDelegate**

Dans `AppDelegate.applicationDidFinishLaunching`, après le bloc ContactPhotoService :

```swift
        // Scan automatique des mails (si activé dans les Réglages)
        Task { @MainActor in
            let ctx = container.mainContext
            if let settings = (try? ctx.fetch(FetchDescriptor<AppSettings>()))?.canonicalSettings {
                MailAutoIndexService.shared.reschedule(context: ctx, settings: settings)
            }
        }
```

- [ ] **Step 6: Vérifier tests + build**

Run: `swift test --filter MailAutoIndexServiceTests 2>&1 | tail -5`
Expected: PASS (3 tests)

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` puis PASS (les switch exhaustifs de JobQueueSidebar compilent)

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Services/JobQueue.swift OneToOne/Views/JobQueueSidebar.swift OneToOne/Services/MailAutoIndexService.swift OneToOne/AppDelegate.swift Tests/MailAutoIndexServiceTests.swift
git commit -m "feat(mail-scan): MailAutoIndexService — pipeline scan/matching/décision + job .mailScan"
```

---

### Task 10: Réglages — section « Mails »

**Files:**
- Create: `OneToOne/Views/Settings/MailSettingsView.swift`
- Modify: `OneToOne/Views/SettingsView.swift` (nouveau GroupBox après « Manager (1:1 manager) »)

**Interfaces:**
- Consumes: `AppSettings.mailAutoIndex*` (T4), `AppSettings.mailAutoIndexMailboxes` (T9), `MailService.listMailboxes()`, `MailAutoIndexService.shared.reschedule/scanNow` (T9), pattern `canonicalSettings`.
- Produces: `struct MailSettingsView: View`.

- [ ] **Step 1: Créer MailSettingsView**

Créer `OneToOne/Views/Settings/MailSettingsView.swift` :

```swift
import SwiftUI
import SwiftData

/// Réglages du scan automatique des mails (section « Mails » des Paramètres).
struct MailSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    @State private var availableMailboxes: [MailboxRef] = []
    @State private var isLoadingMailboxes = false
    @State private var mailboxStatus: String?

    private var settings: AppSettings { settingsList.canonicalSettings ?? AppSettings() }

    /// Binding générique : écrit dans AppSettings, sauve et ré-arme la boucle.
    private func binding<T>(_ get: @escaping (AppSettings) -> T,
                            _ set: @escaping (AppSettings, T) -> Void) -> Binding<T> {
        Binding(
            get: { get(settings) },
            set: { newValue in
                set(settings, newValue)
                try? context.save()
                MailAutoIndexService.shared.reschedule(context: context, settings: settings)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Scanner automatiquement mes mails (mails lus uniquement)",
                   isOn: binding({ $0.mailAutoIndexEnabled }, { $0.mailAutoIndexEnabled = $1 }))

            // Boîtes scannées
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Boîtes scannées").font(.callout.bold())
                    Spacer()
                    Button {
                        loadMailboxes()
                    } label: {
                        Label("Recharger", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingMailboxes)
                }
                if availableMailboxes.isEmpty {
                    Text(mailboxStatus ?? "Cliquer sur « Recharger » pour lister les boîtes (autorisation Automation → Mail requise).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableMailboxes) { box in
                        Toggle(box.displayName, isOn: Binding(
                            get: { settings.mailAutoIndexMailboxes.contains(box) },
                            set: { on in
                                var boxes = settings.mailAutoIndexMailboxes
                                if on { boxes.append(box) } else { boxes.removeAll { $0 == box } }
                                settings.mailAutoIndexMailboxes = boxes
                                try? context.save()
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }

            HStack(spacing: 20) {
                Stepper("Historique : \(settings.mailAutoIndexLookbackDays) jours",
                        value: binding({ $0.mailAutoIndexLookbackDays },
                                       { $0.mailAutoIndexLookbackDays = $1 }),
                        in: 7...365, step: 7)
                Stepper("Intervalle : \(settings.mailAutoIndexIntervalMinutes) min",
                        value: binding({ $0.mailAutoIndexIntervalMinutes },
                                       { $0.mailAutoIndexIntervalMinutes = $1 }),
                        in: 15...480, step: 15)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Seuil rattachement auto : \(settings.mailAutoIndexAutoThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(value: binding({ $0.mailAutoIndexAutoThreshold },
                                          { $0.mailAutoIndexAutoThreshold = $1 }),
                           in: 0.5...1.0)
                        .frame(maxWidth: 220)
                }
                HStack {
                    Text("Seuil suggestion : \(settings.mailAutoIndexSuggestThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(value: binding({ $0.mailAutoIndexSuggestThreshold },
                                          { $0.mailAutoIndexSuggestThreshold = $1 }),
                           in: 0.1...0.75)
                        .frame(maxWidth: 220)
                }
                Text("≥ seuil auto : rattaché et indexé sans confirmation. Entre les deux : file de validation. En dessous : ignoré.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Scanner maintenant") {
                    MailAutoIndexService.shared.scanNow(context: context, settings: settings)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.mailAutoIndexEnabled || settings.mailAutoIndexMailboxes.isEmpty)

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
        }
        .onAppear { if settings.mailAutoIndexEnabled { loadMailboxes() } }
    }

    private func loadMailboxes() {
        isLoadingMailboxes = true
        mailboxStatus = nil
        Task {
            do {
                let boxes = try await MailService.listMailboxes()
                await MainActor.run {
                    availableMailboxes = boxes
                    isLoadingMailboxes = false
                    if boxes.isEmpty { mailboxStatus = "Aucune boîte trouvée dans Mail." }
                }
            } catch {
                await MainActor.run {
                    isLoadingMailboxes = false
                    mailboxStatus = "Erreur : \(error.localizedDescription)"
                }
            }
        }
    }
}
```

- [ ] **Step 2: Insérer dans SettingsView**

Dans `SettingsView.swift`, après le `GroupBox("Manager (1:1 manager)") { ... }` :

```swift
                GroupBox("Mails (scan automatique & RAG)") {
                    MailSettingsView().padding(8)
                }
```

- [ ] **Step 3: Vérifier build + tests**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` puis PASS

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Settings/MailSettingsView.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(mail-scan): section Réglages « Mails » (boîtes, fenêtre, seuils, scan manuel)"
```

---

### Task 11: File de validation des suggestions (service + sheet)

**Files:**
- Create: `OneToOne/Services/MailSuggestionService.swift`
- Create: `OneToOne/Views/MailSuggestionReviewSheet.swift`
- Modify: `OneToOne/Views/MailBrowserView.swift` (badge + sheet dans la commandBar)
- Test: `Tests/MailSuggestionServiceTests.swift`

**Interfaces:**
- Consumes: `MailIndexSuggestion` (T4), `MailScanStore.setVerdict` (T5), `MailService.fetchBody`/`saveAttachments`, `ProjectMailStore.save`, pattern `ManagerActionReviewSheet` (`.sheet(isPresented:)`).
- Produces:
  - `MailSuggestionService` (`@MainActor enum`) : `struct Fetchers` (closures injectables `fetchBody`, `fetchAttachments`, `materialize` + `static let live`), `static func validate(_ suggestion: MailIndexSuggestion, in context: ModelContext, fetchers: Fetchers = .live) async throws`, `static func ignore(_ suggestion: MailIndexSuggestion, in context: ModelContext)`, `enum ValidationError: LocalizedError { case missingProject }`
  - `struct MailSuggestionReviewSheet: View` (liste **groupée par projet suggéré**, tri par date dans chaque groupe — spec §6)

La logique validation/ignore vit dans le **service** (testable en container in-memory avec fetchers stubs, exigence spec §10) ; la View ne fait que l'appeler.

- [ ] **Step 1: Écrire les tests du service qui échouent**

Créer `Tests/MailSuggestionServiceTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailSuggestionServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func makeFixture() throws -> (MailIndexSuggestion, Project) {
        let project = Project(code: "P1", name: "Alpha", domain: "IT", phase: "Run")
        context.insert(project)
        let suggestion = MailIndexSuggestion(
            messageId: "msg-1", accountName: "Pro", mailbox: "INBOX",
            subject: "Sujet", sender: "a@ex.com", dateReceived: Date())
        suggestion.suggestedProject = project
        context.insert(suggestion)
        context.insert(MailScanRecord(messageId: "msg-1", verdict: .suggested))
        try context.save()
        return (suggestion, project)
    }

    /// Fetchers stubs : pas d'AppleScript, matérialisation minimale (le
    /// pipeline chunk+embedding réel de ProjectMailStore est hors de portée
    /// des tests — MLX indisponible sous swift test).
    private func stubFetchers() -> MailSuggestionService.Fetchers {
        MailSuggestionService.Fetchers(
            fetchBody: { _ in "corps du mail" },
            fetchAttachments: { _ in [] },
            materialize: { snippet, body, _, project, context in
                let mail = ProjectMail(messageId: snippet.messageId,
                                       accountName: snippet.accountName,
                                       mailbox: snippet.mailbox,
                                       subject: snippet.subject,
                                       sender: snippet.sender,
                                       dateReceived: snippet.dateReceived,
                                       body: body)
                mail.project = project
                context.insert(mail)
                try context.save()
            }
        )
    }

    func test_validate_materialiseEtSupprimeLaSuggestion() async throws {
        let (suggestion, project) = try makeFixture()
        try await MailSuggestionService.validate(suggestion, in: context, fetchers: stubFetchers())

        let mails = try context.fetch(FetchDescriptor<ProjectMail>())
        XCTAssertEqual(mails.count, 1)
        XCTAssertEqual(mails.first?.messageId, "msg-1")
        XCTAssertEqual(mails.first?.project?.code, project.code)
        XCTAssertEqual(mails.first?.body, "corps du mail")

        XCTAssertTrue(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).isEmpty)
        let record = try context.fetch(FetchDescriptor<MailScanRecord>()).first
        XCTAssertEqual(record?.verdict, .attached)
    }

    func test_validate_sansProjet_leveEtConserveLaSuggestion() async throws {
        let (suggestion, _) = try makeFixture()
        suggestion.suggestedProject = nil

        do {
            try await MailSuggestionService.validate(suggestion, in: context, fetchers: stubFetchers())
            XCTFail("validate aurait dû lever")
        } catch { /* attendu */ }
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).count, 1)
    }

    func test_validate_echecFetch_conserveLaSuggestionEtLeRecord() async throws {
        let (suggestion, _) = try makeFixture()
        var fetchers = stubFetchers()
        fetchers.fetchBody = { _ in throw NSError(domain: "stub", code: -1) }

        do {
            try await MailSuggestionService.validate(suggestion, in: context, fetchers: fetchers)
            XCTFail("validate aurait dû lever")
        } catch { /* attendu */ }
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailScanRecord>()).first?.verdict, .suggested)
    }

    func test_ignore_supprimeEtTraceLeVerdict() throws {
        let (suggestion, _) = try makeFixture()
        MailSuggestionService.ignore(suggestion, in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailScanRecord>()).first?.verdict, .ignored)
    }
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `swift test --filter MailSuggestionServiceTests 2>&1 | tail -5`
Expected: FAIL (`cannot find 'MailSuggestionService' in scope`)

- [ ] **Step 3: Implémenter MailSuggestionService**

Créer `OneToOne/Services/MailSuggestionService.swift` :

```swift
import Foundation
import SwiftData

/// Validation / ignore des suggestions du scan automatique. Logique extraite
/// de la vue pour être testable : les accès Mail.app et la matérialisation
/// (ProjectMailStore) sont injectés via `Fetchers`.
@MainActor
enum MailSuggestionService {

    enum ValidationError: LocalizedError {
        case missingProject
        var errorDescription: String? { "Aucun projet sélectionné pour ce mail." }
    }

    struct Fetchers {
        var fetchBody: (MailIndexSuggestion) async throws -> String
        var fetchAttachments: (MailIndexSuggestion) async throws -> [MailAttachmentFile]
        var materialize: (MailSnippet, String, [MailAttachmentFile], Project, ModelContext) async throws -> Void

        static let live = Fetchers(
            fetchBody: { s in
                try await MailService.fetchBody(messageId: s.messageId,
                                                accountName: s.accountName,
                                                mailbox: s.mailbox)
            },
            fetchAttachments: { s in
                try await MailService.saveAttachments(messageId: s.messageId,
                                                      accountName: s.accountName,
                                                      mailbox: s.mailbox)
            },
            materialize: { snippet, body, attachments, project, context in
                _ = try await ProjectMailStore.save(snippet: snippet, body: body,
                                                    attachments: attachments,
                                                    to: project, context: context)
            }
        )
    }

    /// Valide une suggestion : fetch corps + PJ, matérialise un `ProjectMail`
    /// (pipeline chunk + embedding), trace le verdict, supprime la suggestion.
    /// En cas d'échec (fetch, embedding), lève SANS rien supprimer : la
    /// suggestion reste dans la file, re-tentable.
    static func validate(
        _ suggestion: MailIndexSuggestion,
        in context: ModelContext,
        fetchers: Fetchers = .live
    ) async throws {
        guard let project = suggestion.suggestedProject else {
            throw ValidationError.missingProject
        }
        let body = try await fetchers.fetchBody(suggestion)
        let attachments = (try? await fetchers.fetchAttachments(suggestion)) ?? []
        let snippet = MailSnippet(
            messageId: suggestion.messageId,
            accountName: suggestion.accountName,
            mailbox: suggestion.mailbox,
            subject: suggestion.subject,
            sender: suggestion.sender,
            dateReceived: suggestion.dateReceived,
            preview: suggestion.preview,
            body: nil)
        try await fetchers.materialize(snippet, body, attachments, project, context)
        MailScanStore.setVerdict(suggestion.messageId, verdict: .attached, in: context)
        context.delete(suggestion)
        try context.save()
    }

    /// Écarte une suggestion : verdict `.ignored` tracé (dédup conservée),
    /// suggestion supprimée.
    static func ignore(_ suggestion: MailIndexSuggestion, in context: ModelContext) {
        MailScanStore.setVerdict(suggestion.messageId, verdict: .ignored, in: context)
        context.delete(suggestion)
        try? context.save()
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `swift test --filter MailSuggestionServiceTests 2>&1 | tail -5`
Expected: PASS (4 tests)

- [ ] **Step 5: Créer MailSuggestionReviewSheet**

Créer `OneToOne/Views/MailSuggestionReviewSheet.swift` :

```swift
import SwiftUI
import SwiftData

/// File de validation des mails suggérés par le scan automatique.
/// Chaque ligne : sujet/expéditeur/date + projet (modifiable) + Valider/Ignorer.
/// « Valider » récupère le corps + PJ puis matérialise un `ProjectMail`
/// (pipeline `ProjectMailStore.save`, chunking + embedding inclus).
struct MailSuggestionReviewSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MailIndexSuggestion.dateReceived, order: .reverse)
    private var suggestions: [MailIndexSuggestion]
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var busyIDs: Set<PersistentIdentifier> = []
    @State private var errorMessage: String?

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mails à valider").font(.headline)
            Text("Le scan automatique a trouvé des mails probablement liés à un projet. Valider indexe le mail (RAG) ; Ignorer l'écarte définitivement.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }

            if suggestions.isEmpty {
                Text("Aucune suggestion en attente.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Groupées par projet suggéré (spec §6), tri par date dans
                // chaque groupe (le @Query trie déjà par date desc).
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedSuggestions, id: \.0) { projectName, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(projectName)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(items) { suggestion in
                                    row(suggestion)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }

            HStack {
                Spacer()
                Button("Fermer", action: onClose)
            }
        }
        .padding(20)
        .frame(minWidth: 680)
    }

    /// Groupes (nom de projet, suggestions) triés par nom ; l'ordre par date
    /// est préservé à l'intérieur de chaque groupe.
    private var groupedSuggestions: [(String, [MailIndexSuggestion])] {
        Dictionary(grouping: suggestions) { $0.suggestedProject?.name ?? "Sans projet" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    @ViewBuilder
    private func row(_ suggestion: MailIndexSuggestion) -> some View {
        let isBusy = busyIDs.contains(suggestion.persistentModelID)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.subject).font(.callout.bold()).lineLimit(1)
                Text("\(suggestion.sender) · \(suggestion.dateReceived.formatted(date: .abbreviated, time: .shortened)) · conf. \(suggestion.confidence, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !suggestion.preview.isEmpty {
                    Text(suggestion.preview).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { suggestion.suggestedProject },
                set: { suggestion.suggestedProject = $0; try? context.save() }
            )) {
                ForEach(projects) { project in
                    Text(project.name).tag(project as Project?)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Button("Valider") {
                Task { await validate(suggestion) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || suggestion.suggestedProject == nil)

            Button("Ignorer") {
                ignore(suggestion)
            }
            .disabled(isBusy)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        .overlay(alignment: .trailing) {
            if isBusy { ProgressView().controlSize(.small).padding(.trailing, 6) }
        }
    }

    private func validate(_ suggestion: MailIndexSuggestion) async {
        busyIDs.insert(suggestion.persistentModelID)
        defer { busyIDs.remove(suggestion.persistentModelID) }
        do {
            try await MailSuggestionService.validate(suggestion, in: context)
            errorMessage = nil
        } catch {
            errorMessage = "Validation échouée : \(error.localizedDescription)"
        }
    }

    private func ignore(_ suggestion: MailIndexSuggestion) {
        MailSuggestionService.ignore(suggestion, in: context)
    }
}
```

- [ ] **Step 6: Badge + sheet dans MailBrowserView**

Dans `MailBrowserView.swift`, ajouter aux propriétés :

```swift
    @Query private var pendingSuggestions: [MailIndexSuggestion]
    @State private var showSuggestionReview = false
```

Dans la `commandBar` (à côté du bouton Actualiser) :

```swift
            Button {
                showSuggestionReview = true
            } label: {
                Label("À valider (\(pendingSuggestions.count))", systemImage: "tray.full")
            }
            .disabled(pendingSuggestions.isEmpty)
            .help("Mails suggérés par le scan automatique, en attente de validation")
```

Sur le conteneur racine de la vue (après `.navigationTitle("Mails")`) :

```swift
        .sheet(isPresented: $showSuggestionReview) {
            MailSuggestionReviewSheet(onClose: { showSuggestionReview = false })
        }
```

- [ ] **Step 7: Vérifier build + tests**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` puis PASS

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Services/MailSuggestionService.swift OneToOne/Views/MailSuggestionReviewSheet.swift OneToOne/Views/MailBrowserView.swift Tests/MailSuggestionServiceTests.swift
git commit -m "feat(mail-scan): file de validation des suggestions (service testable + sheet groupée)"
```

---

### Task 12: Documentation + vérification de bout en bout

**Files:**
- Modify: `docs/architecture.md` (§6.1 IA, §6.5/6.6 selon sections existantes : mentionner MLXEmbedders, MailAutoIndexService, nouveaux modèles ; mettre à jour la date de dernière mise à jour)
- Modify: `CLAUDE.md` (une ligne dans la section provider IA : embeddings via MLXEmbedders par défaut, Ollama legacy)

- [ ] **Step 1: Mettre à jour docs/architecture.md**

Ajouter : dans la table Stack (§2) la ligne embeddings MLX ; dans §6.1 remplacer « EmbeddingService (Ollama nomic-embed-text) » par le routeur MLX/Ollama ; dans §6.5 ou 6.6 un paragraphe « Scan automatique des mails » décrivant `MailAutoIndexService` (pipeline, seuils, JobKind `.mailScan`), `MailProjectMatcher`, `MailLLMClassifier`, `MailScanStore` et les modèles `MailIndexSuggestion`/`MailScanRecord` ; ajouter les 2 modèles dans l'inventaire §5.

- [ ] **Step 2: Mettre à jour CLAUDE.md**

Dans la section « Provider IA "Directe" », ajouter :

```markdown
- **Embeddings** : `EmbeddingService` route vers **MLXEmbedders** in-process par défaut
  (`nomic-ai/nomic-embed-text-v1.5`, préfixes `search_document:`/`search_query:`) ;
  Ollama reste disponible en legacy (`onetoone_embedding_backend` = `ollama`).
```

- [ ] **Step 3: Suite de tests complète + build**

Run: `swift test 2>&1 | tail -5`
Expected: PASS (tous les tests, anciens + nouveaux)

- [ ] **Step 4: Vérification fonctionnelle dans l'app packagée**

```bash
Scripts/bump-and-build.sh dev
```

Puis, manuellement dans l'app (MLX exige le `default.metallib` embarqué — impossible via `swift run`) :
1. Réglages → Maintenance → vérifier le compteur « chunks à ré-embedder » > 0 (index Ollama existant) → « Ré-embedder l'index » → job visible dans la sidebar, compteur retombe à 0.
2. Réglages → Mails → activer, recharger les boîtes (accorder l'autorisation Automation), cocher une boîte, « Scanner maintenant » → job « Scan des mails », statut de fin.
3. Navigateur de mails → badge « À valider (N) » → valider une suggestion → le mail apparaît dans les sources RAG du projet.
4. RAG : poser une question dans le chat RAG d'un projet ayant des mails indexés → citations mails.
5. Robustesse (spec §5) : lancer un scan avec un modèle d'embedding invalide (Réglages → Maintenance → champ modèle → valeur bidon) → le job doit finir en échec avec le compte d'erreurs, ET aucun `ProjectMail` sans chunks ne doit rester (vérifier dans les sources du projet) ; remettre le modèle correct → la passe suivante rattache les mails re-tentés.

- [ ] **Step 5: Commit final**

```bash
git add docs/architecture.md CLAUDE.md
git commit -m "docs: architecture + CLAUDE.md — embeddings MLX et scan automatique des mails"
```
