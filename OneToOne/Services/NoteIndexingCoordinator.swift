import Foundation
import SwiftData
import os

private let noteIndexingLog = Logger(subsystem: "com.onetoone.app", category: "rag")

/// Auto-indexation RAG des notes libres (`Meeting.kind == .note`) au fil de
/// l'édition. Un `scheduleReindex` annule et redémarre le minuteur de
/// debounce en cours pour la même note plutôt que d'en cumuler plusieurs —
/// sans ça, chaque frappe clavier déclencherait un reindex complet
/// (chunking + embedding).
///
/// Un reindex déjà en vol pour la même note est annulé avant d'en lancer un
/// nouveau : `RAGIndexer.reindex` vérifie `Task.checkCancellation()` aux
/// points de coupure (avant le clear des chunks, après l'embedding) pour
/// abandonner proprement sans laisser d'état incohérent.
@MainActor
final class NoteIndexingCoordinator {
    static let shared = NoteIndexingCoordinator()

    private init() {}

    /// Délai de debounce avant de lancer le reindex. `var` pour permettre aux
    /// tests de raccourcir l'attente sans changer le comportement par défaut.
    var debounceDelay: TimeInterval = 2.0

    /// Point d'injection pour les tests : la production laisse la valeur par
    /// défaut (`RAGIndexer.reindexNote`, qui appelle le pipeline MLX réel).
    /// Les tests substituent un double pour éviter de dépendre de MLX/GPU
    /// (indisponible dans `swift test`, cf. CLAUDE.md).
    var reindexHandler: (Meeting, ModelContext) async throws -> Void = { meeting, context in
        try await RAGIndexer.reindexNote(meeting: meeting, context: context)
    }

    private var debounceTasks: [PersistentIdentifier: Task<Void, Never>] = [:]
    private var reindexTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    /// Programme un reindex de `meeting`, `debounceDelay` secondes après le
    /// dernier appel pour la même note (identifiée par `persistentModelID`).
    /// Sans effet si `meeting.kind != .note` — le gate vit dans
    /// `RAGIndexer.reindexNote`, appelé à l'échéance.
    func scheduleReindex(meeting: Meeting, context: ModelContext) {
        let pid = meeting.persistentModelID
        debounceTasks[pid]?.cancel()
        let delay = debounceDelay
        debounceTasks[pid] = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.debounceTasks[pid] = nil
            self.startReindex(meeting: meeting, context: context, pid: pid)
        }
    }

    /// Annule un éventuel reindex en cours pour cette note avant d'en lancer
    /// un nouveau — `reindexHandler` (par défaut `RAGIndexer.reindexNote`)
    /// coopère via `Task.checkCancellation()`.
    private func startReindex(meeting: Meeting, context: ModelContext, pid: PersistentIdentifier) {
        reindexTasks[pid]?.cancel()
        reindexTasks[pid] = Task {
            defer { self.reindexTasks[pid] = nil }
            do {
                try await self.reindexHandler(meeting, context)
            } catch is CancellationError {
                noteIndexingLog.info("reindexNote: annulé (nouvelle édition en cours)")
            } catch {
                noteIndexingLog.error("reindexNote: échec \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Nombre de reindex actuellement en vol — utilisé par les tests pour
    /// observer le débounce sans dépendre de timings serrés.
    var pendingReindexCount: Int { reindexTasks.count }
}
