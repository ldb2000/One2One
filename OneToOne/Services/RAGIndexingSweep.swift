import Foundation
import SwiftData
import os

private let ragSweepLog = Logger(subsystem: "com.onetoone.app", category: "rag-sweep")

/// Batch d'indexation globale au démarrage (ADR
/// `docs/adr/2026-09-05-rag-pipeline-inventaire.md`, section D) : rattrape les
/// `TranscriptChunk` qui n'ont jamais été indexés ou dont l'embedding est
/// obsolète (modèle changé, bug d'indexation passé, restore de backup…).
///
/// Contrairement à `NoteIndexingCoordinator` (debounce à l'édition) ou aux
/// hooks d'ingestion (`MeetingAttachmentService`, `ProjectMailStore`), ce
/// balayage est *pull* : il relit tout l'index à chaque lancement et ne
/// dépend d'aucun événement applicatif. Volontairement sans persistance de
/// « qui a été traité » — un re-run est un no-op dès que les chunks sont à
/// jour (voir `runIfNeeded`), donc idempotent par construction plutôt que par
/// un journal explicite.
@MainActor
struct RAGIndexingSweep {
    static let shared = RAGIndexingSweep()

    /// Clé UserDefaults mémorisant le dernier modèle d'embedding pour lequel
    /// un sweep complet s'est terminé. Sert à détecter un changement de
    /// modèle global (ex. e5-base → autre) et à forcer, dans ce cas, le
    /// ré-indexage de tous les chunks — même ceux dont `embeddingModel`
    /// correspondrait déjà au modèle courant (vecteurs sinon incompatibles).
    static let lastIndexedEmbeddingModelKey = "lastIndexedEmbeddingModel"

    /// Point d'injection pour les tests : store UserDefaults dédié afin de ne
    /// jamais lire/écrire dans les préférences réelles de l'utilisateur ni
    /// polluer les autres suites (comme `NoteIndexingCoordinator.reindexHandler`).
    static var userDefaults: UserDefaults = .standard

    /// Points d'injection pour les tests — la production laisse les valeurs
    /// par défaut, qui appellent le pipeline réel (MLX inclus, cf. CLAUDE.md :
    /// `swift test` n'embarque pas `default.metallib`, donc les tests
    /// substituent un double plutôt que d'appeler ces fermetures pour de vrai).
    static var reindexMeetingHandler: (Meeting, ModelContext) async throws -> Void = { meeting, context in
        if meeting.kind == .note {
            try await RAGIndexer.reindexNote(meeting: meeting, context: context)
        } else {
            try await RAGIndexer.reindex(meeting: meeting, context: context)
        }
    }
    static var reindexAttachmentHandler: (MeetingAttachment, ModelContext) async throws -> Void = { attachment, context in
        try await MeetingAttachmentService.reindexAttachment(attachment, context: context)
    }
    static var reindexMailHandler: (ProjectMail, ModelContext) async throws -> Void = { mail, context in
        try await ProjectMailStore.reindex(mail: mail, context: context)
    }

    /// Balaie tous les `TranscriptChunk`, regroupe ceux à ré-indexer par
    /// parent (réunion/note, attachment, mail), puis déclenche un reindex par
    /// parent distinct. Ne fait rien si aucun chunk n'est concerné. Pensé pour
    /// tourner en tâche de fond au démarrage : chaque parent est traité l'un
    /// après l'autre (pas de parallélisme), une erreur sur l'un n'interrompt
    /// pas les suivants.
    func runIfNeeded(context: ModelContext) async {
        let currentModel = RAGService.embeddingModel
        let defaults = Self.userDefaults
        let previousModel = defaults.string(forKey: Self.lastIndexedEmbeddingModelKey)
        let modelChanged = previousModel != nil && previousModel != currentModel

        let allChunks = (try? context.fetch(FetchDescriptor<TranscriptChunk>())) ?? []
        guard !allChunks.isEmpty else {
            defaults.set(currentModel, forKey: Self.lastIndexedEmbeddingModelKey)
            return
        }

        let staleChunks = allChunks.filter { chunk in
            modelChanged || chunk.embeddingData == nil || chunk.embeddingModel != currentModel
        }

        guard !staleChunks.isEmpty else {
            defaults.set(currentModel, forKey: Self.lastIndexedEmbeddingModelKey)
            return
        }

        ragSweepLog.info("sweep: \(staleChunks.count, privacy: .public)/\(allChunks.count, privacy: .public) chunk(s) à ré-indexer (modèle=\(currentModel, privacy: .public), modelChanged=\(modelChanged, privacy: .public))")

        // Regroupement par parent : un chunk d'attachment porte aussi une
        // relation `meeting` (celle de la réunion hôte) — tester `attachment`
        // puis `mail` avant `meeting` évite de le router à tort vers un
        // reindex de réunion (qui ne toucherait pas ses chunks à lui).
        var meetings: [PersistentIdentifier: Meeting] = [:]
        var attachments: [PersistentIdentifier: MeetingAttachment] = [:]
        var mails: [PersistentIdentifier: ProjectMail] = [:]
        var orphanCount = 0

        for chunk in staleChunks {
            if let attachment = chunk.attachment {
                attachments[attachment.persistentModelID] = attachment
            } else if let mail = chunk.mail {
                mails[mail.persistentModelID] = mail
            } else if let meeting = chunk.meeting {
                meetings[meeting.persistentModelID] = meeting
            } else {
                orphanCount += 1
            }
        }
        if orphanCount > 0 {
            ragSweepLog.info("sweep: \(orphanCount, privacy: .public) chunk(s) orphelin(s) (aucune relation), ignorés")
        }

        for meeting in meetings.values {
            do {
                try await Self.reindexMeetingHandler(meeting, context)
            } catch is CancellationError {
                return
            } catch {
                ragSweepLog.error("sweep meeting=\(meeting.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        for attachment in attachments.values {
            do {
                try await Self.reindexAttachmentHandler(attachment, context)
            } catch is CancellationError {
                return
            } catch {
                ragSweepLog.error("sweep attachment=\(attachment.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        for mail in mails.values {
            do {
                try await Self.reindexMailHandler(mail, context)
            } catch is CancellationError {
                return
            } catch {
                ragSweepLog.error("sweep mail=\(mail.subject, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        defaults.set(currentModel, forKey: Self.lastIndexedEmbeddingModelKey)
        ragSweepLog.info("sweep: terminé (\(meetings.count, privacy: .public) réunion(s)/note(s), \(attachments.count, privacy: .public) attachment(s), \(mails.count, privacy: .public) mail(s))")
    }
}
