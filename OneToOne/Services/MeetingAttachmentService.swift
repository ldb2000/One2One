import Foundation
import SwiftData
import AppKit
import os

private let attachLog = Logger(subsystem: "com.onetoone.app", category: "attach")

// MARK: - MeetingAttachmentService

/// Ingestion de documents rattachés à une réunion :
///   1. Copie la référence (bookmark) dans `MeetingAttachment`
///   2. Extrait le texte (PDF / PPTX / XLSX / TXT / MD / DOCX best-effort)
///   3. Chunking → Embeddings Ollama → `TranscriptChunk(sourceType: "attachment")`
///
/// Les chunks produits sont visibles dans les recherches `RAGQuery` via leur
/// `meeting` associé, au même titre que les transcriptions audio.
@MainActor
struct MeetingAttachmentService {

    enum AttachError: LocalizedError {
        case extractFailed(String)

        var errorDescription: String? {
            switch self {
            case .extractFailed(let d): return "Extraction texte impossible : \(d)"
            }
        }
    }

    /// Ajoute un document à la réunion + indexe son contenu pour RAG.
    /// - Returns: l'attachment créé.
    @discardableResult
    static func importDocument(
        url: URL,
        into meeting: Meeting,
        context: ModelContext
    ) async throws -> MeetingAttachment {
        let ext = url.pathExtension.lowercased()
        let kind = kindForExtension(ext)

        let attach = MeetingAttachment(url: url, kind: kind)
        attach.meeting = meeting
        context.insert(attach)

        // 1. Extract text via AIIngestionService (réutilise le parseur existant).
        let ingester = AIIngestionService()
        let extracted: String
        do {
            extracted = try ingester.extractTextPublic(from: url)
        } catch {
            attachLog.error("extract failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // On garde quand même l'attachement mais sans texte indexé.
            try context.save()
            throw AttachError.extractFailed(error.localizedDescription)
        }
        attach.extractedText = extracted
        try context.save()

        guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            attachLog.info("extract empty for \(url.lastPathComponent, privacy: .public) — skip indexing")
            return attach
        }

        // 2. Chunk + embed + persist.
        let chunks = TextChunker.chunk(extracted)
        attachLog.info("indexing \(url.lastPathComponent, privacy: .public): chunks=\(chunks.count)")

        let vectors = (try? await EmbeddingService.embedBatch(chunks)) ?? []

        for (i, text) in chunks.enumerated() {
            let chunk = TranscriptChunk(
                text: text,
                orderIndex: i,
                sourceType: "attachment"
            )
            chunk.meeting = meeting
            chunk.attachment = attach
            if let vec = vectors[safe: i], !vec.isEmpty {
                chunk.setEmbedding(vec, model: EmbeddingService.model)
            }
            context.insert(chunk)
        }
        try context.save()

        return attach
    }

    /// Ré-indexation forcée d'un attachment (texte déjà extrait).
    static func reindexAttachment(_ attach: MeetingAttachment, context: ModelContext) async throws {
        for old in attach.chunks { context.delete(old) }
        try context.save()

        guard !attach.extractedText.isEmpty else { return }

        let chunks = TextChunker.chunk(attach.extractedText)
        let vectors = (try? await EmbeddingService.embedBatch(chunks)) ?? []
        for (i, text) in chunks.enumerated() {
            let c = TranscriptChunk(text: text, orderIndex: i, sourceType: "attachment")
            c.meeting = attach.meeting
            c.attachment = attach
            if let v = vectors[safe: i], !v.isEmpty {
                c.setEmbedding(v, model: EmbeddingService.model)
            }
            context.insert(c)
        }
        try context.save()
    }

    // MARK: - Helpers

    private static func kindForExtension(_ ext: String) -> String {
        switch ext {
        case "pdf":               return "pdf"
        case "pptx", "ppt":       return "pptx"
        case "docx", "doc":       return "docx"
        case "xlsx", "xls", "csv": return "xlsx"
        case "md", "markdown":    return "markdown"
        case "txt", "text":       return "text"
        case "png", "jpg", "jpeg", "heic", "gif", "tiff": return "image"
        default:                   return "document"
        }
    }
}

// MARK: - Array safe (duplicated for module isolation)

private extension Array {
    subscript(safe i: Int) -> Element? {
        (0..<count).contains(i) ? self[i] : nil
    }
}
