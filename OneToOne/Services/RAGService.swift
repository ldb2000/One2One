import Foundation
import SwiftData
import os

private let ragLog = Logger(subsystem: "com.onetoone.app", category: "rag")

// MARK: - Chunker

/// Découpe un texte en chunks ~targetChars avec overlap.
/// Privilégie les frontières de paragraphe puis de phrase.
enum TextChunker {

    /// Découpe `text` en blocs d'environ `targetChars` caractères. Privilégie
    /// les frontières de paragraphe ; un paragraphe trop long est resegmenté
    /// par phrases. Chaque bloc reprend les `overlapChars` derniers caractères
    /// du précédent (continuité de contexte pour l'embedding). Retourne `[]`
    /// si vide, ou `[texte]` si le texte tient sous `targetChars`.
    static func chunk(_ text: String, targetChars: Int = 2000, overlapChars: Int = 200) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > targetChars else { return [trimmed] }

        // Split sur les paragraphes (double newline) puis reconstitue en blocs ≤ target.
        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        func flush() {
            let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !c.isEmpty { chunks.append(c) }
            // overlap : réinjecte les derniers `overlapChars` au début du suivant.
            if overlapChars > 0, c.count > overlapChars {
                let tail = String(c.suffix(overlapChars))
                current = tail + "\n\n"
            } else {
                current = ""
            }
        }

        for p in paragraphs {
            if current.count + p.count + 2 <= targetChars {
                current += (current.isEmpty ? "" : "\n\n") + p
            } else if p.count > targetChars {
                // Paragraphe trop long → split par phrases.
                flush()
                for sub in splitSentences(p, maxLen: targetChars) {
                    if current.count + sub.count + 1 <= targetChars {
                        current += (current.isEmpty ? "" : " ") + sub
                    } else {
                        flush()
                        current += sub
                    }
                }
            } else {
                flush()
                current += p
            }
        }
        flush()
        return chunks
    }

    private static func splitSentences(_ text: String, maxLen: Int) -> [String] {
        var out: [String] = []
        var buf = ""
        let terminators: Set<Character> = [".", "!", "?", "…"]
        for ch in text {
            buf.append(ch)
            if terminators.contains(ch), buf.count >= maxLen / 2 {
                out.append(buf.trimmingCharacters(in: .whitespaces))
                buf = ""
            }
            if buf.count >= maxLen {
                out.append(buf)
                buf = ""
            }
        }
        if !buf.isEmpty { out.append(buf.trimmingCharacters(in: .whitespaces)) }
        return out.filter { !$0.isEmpty }
    }
}

// MARK: - RAGIndexer

/// Indexe les transcriptions d'une réunion : chunking + embedding + persistance
/// dans `TranscriptChunk` avec relation `meeting`.
@MainActor
struct RAGIndexer {

    /// Ré-indexe intégralement une réunion : supprime d'abord tous les
    /// `TranscriptChunk` existants, puis re-chunke / re-embedde la
    /// transcription (préfère `mergedTranscript`, sinon `rawTranscript`) et
    /// persiste. No-op si la transcription est vide. Opération idempotente.
    static func reindex(meeting: Meeting, context: ModelContext) async throws {
        let transcript = meeting.mergedTranscript.isEmpty
            ? meeting.rawTranscript
            : meeting.mergedTranscript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ragLog.info("reindex: transcript vide, skip")
            return
        }

        // Clear old chunks.
        for old in meeting.transcriptChunks {
            context.delete(old)
        }

        let pieces = TextChunker.chunk(transcript)
        ragLog.info("reindex: meeting=\(meeting.title, privacy: .public) chunks=\(pieces.count)")
        let vectors = try await EmbeddingService.embedBatch(pieces)

        for (i, text) in pieces.enumerated() {
            let chunk = TranscriptChunk(text: text, orderIndex: i, sourceType: "meeting")
            chunk.meeting = meeting
            let vec = vectors[safe: i] ?? []
            if !vec.isEmpty {
                chunk.setEmbedding(vec, model: EmbeddingService.model)
            }
            context.insert(chunk)
        }

        try context.save()
        ragLog.info("reindex: done, saved \(pieces.count) chunks")
    }
}

// MARK: - RAGQuery

/// Recherche sémantique (cosine) sur les chunks indexés.
/// `search(query:)` embedde la requête texte puis classe ; `searchByVector(_:)`
/// part d'un vecteur déjà calculé. Les deux partagent le filtrage par `Scope`.
struct RAGQuery {

    struct Result {
        let chunk: TranscriptChunk
        let similarity: Float
    }

    /// Restreint la recherche. Les critères non-nil sont combinés en ET
    /// logique ; tous nil (défaut) = aucune restriction.
    struct Scope {
        /// Ne garder que les chunks du projet donné.
        var projectPID: PersistentIdentifier? = nil
        /// Ne garder que les chunks dont la réunion compte ce collaborateur.
        var collaboratorPID: PersistentIdentifier? = nil
        /// Ne garder que les chunks d'un certain type de réunion.
        var meetingKind: MeetingKind? = nil
        /// Exclure cette réunion des résultats (utile pour la génération du rapport
        /// : on ne veut pas que la réunion en cours se nourrisse d'elle-même).
        var excludeMeetingPID: PersistentIdentifier? = nil

        /// Filtre par origine du chunk : "meeting" | "attachment" | "mail" | nil (tous).
        var sourceType: String? = nil
        /// Restreint à une réunion précise (chunk lié directement ou via attachment).
        var meetingPID: PersistentIdentifier? = nil
    }

    /// Retourne les `topK` chunks les plus similaires à la requête.
    @MainActor
    static func search(
        query: String,
        topK: Int = 6,
        scope: Scope = Scope(),
        context: ModelContext
    ) async throws -> [Result] {
        let queryVec = try await EmbeddingService.embed(query)
        guard !queryVec.isEmpty else { return [] }

        let chunks = filtered(context: context, scope: scope)
        let scored: [Result] = chunks.compactMap { c in
            let v = c.embeddingVector
            guard !v.isEmpty else { return nil }
            let sim = EmbeddingService.cosineSimilarity(queryVec, v)
            return Result(chunk: c, similarity: sim)
        }
        return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(topK))
    }

    /// Variante : recherche par vecteur pré-calculé (utile pour le context enrichment
    /// où on embed la synthèse de la réunion courante).
    @MainActor
    static func searchByVector(
        _ queryVec: [Float],
        topK: Int = 6,
        scope: Scope = Scope(),
        context: ModelContext
    ) -> [Result] {
        guard !queryVec.isEmpty else { return [] }
        let chunks = filtered(context: context, scope: scope)
        let scored: [Result] = chunks.compactMap { c in
            let v = c.embeddingVector
            guard !v.isEmpty else { return nil }
            return Result(chunk: c, similarity: EmbeddingService.cosineSimilarity(queryVec, v))
        }
        return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(topK))
    }

    /// Charge tous les `TranscriptChunk` puis applique le `scope` en mémoire.
    /// Choix volontaire (les prédicats SwiftData ne franchissent pas bien les
    /// relations) acceptable tant que le volume reste modéré — voir note coût.
    @MainActor
    private static func filtered(context: ModelContext, scope: Scope) -> [TranscriptChunk] {
        // On lit tout puis on filtre en Swift — OK tant que < ~50k chunks.
        // Au-delà, découper par meeting via prédicats.
        let all = (try? context.fetch(FetchDescriptor<TranscriptChunk>())) ?? []
        return all.filter { c in
            // Soit il y a une réunion, soit il y a un attachment.
            let m = c.meeting
            let att = c.attachment
            let mail = c.mail

            // Si on demande un meeting précis, il faut que le chunk appartienne à ce meeting
            // (soit directement via meeting, soit via l'attachment qui lui-même est lié au meeting).
            if let targetPID = scope.meetingPID {
                let chunkMeetingPID = m?.persistentModelID ?? att?.meeting?.persistentModelID
                guard chunkMeetingPID == targetPID else { return false }
            }

            // Exclude meeting
            if let excludePID = scope.excludeMeetingPID {
                let chunkMeetingPID = m?.persistentModelID ?? att?.meeting?.persistentModelID
                if chunkMeetingPID == excludePID { return false }
            }

            // Source type filter
            if let st = scope.sourceType {
                guard c.sourceType == st else { return false }
            }

            // Project filter
            if let pid = scope.projectPID {
                let chunkProjectPID = m?.project?.persistentModelID
                    ?? att?.meeting?.project?.persistentModelID
                    ?? mail?.project?.persistentModelID
                guard chunkProjectPID == pid else { return false }
            }

            // Collaborator filter
            if let pid = scope.collaboratorPID {
                let participants = m?.participants ?? att?.meeting?.participants ?? []
                guard participants.contains(where: { $0.persistentModelID == pid }) else { return false }
            }

            // Meeting kind filter
            if let kind = scope.meetingKind {
                let chunkKind = m?.kind ?? att?.meeting?.kind
                guard chunkKind == kind else { return false }
            }

            return true
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? {
        (0..<count).contains(i) ? self[i] : nil
    }
}
