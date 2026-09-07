import Foundation
import SwiftData
import AppKit
import os

private let attachLog = Logger(subsystem: "com.onetoone.app", category: "attach")

// MARK: - MeetingAttachmentService

/// Ingestion de documents rattachés à une réunion :
///   1. **Copie le fichier** dans `recordings/<uuid>/documents/` et crée la
///      ligne `MeetingAttachment` avec ses métadonnées (D5, ADR
///      `2026-09-07-pieces-copiees-jamais-referencees.md`)
///   2. Extrait le texte (PDF / PPTX / XLSX / TXT / MD / DOCX best-effort)
///   3. Chunking → Embeddings → `TranscriptChunk(sourceType: "attachment")`
///
/// L'étape 1 est `attachDocument`, synchrone et sans réseau ; les étapes 2 et 3
/// sont `importDocument`, qui l'appelle. La séparation n'est pas cosmétique :
/// la politique de copie se vérifie sans modèle d'embedding, et une extraction
/// qui échoue ne doit pas perdre le fichier déjà copié.
///
/// Les chunks produits sont visibles dans les recherches `RAGQuery` via leur
/// `meeting` associé, au même titre que les transcriptions audio.
@MainActor
struct MeetingAttachmentService {

    /// Erreurs d'ingestion : actuellement l'échec d'extraction de texte.
    enum AttachError: LocalizedError {
        case extractFailed(String)

        var errorDescription: String? {
            switch self {
            case .extractFailed(let d): return "Extraction texte impossible : \(d)"
            }
        }
    }

    /// **Copie** le fichier dans la réunion et crée la ligne correspondante,
    /// sans extraction ni indexation (D5).
    ///
    /// La copie précède l'insertion : une source illisible ne doit pas laisser
    /// derrière elle une ligne sans fichier, qui ne se distinguerait pas d'une
    /// pièce orpheline et pour laquelle le tiroir proposerait de « relier » un
    /// document n'ayant jamais existé.
    ///
    /// - Parameter base: racine du stockage ; paramétrée pour les tests.
    @discardableResult
    static func attachDocument(
        url: URL,
        into meeting: Meeting,
        context: ModelContext,
        base: URL = AttachmentImporter.baseDirectory()
    ) throws -> MeetingAttachment {
        let ext = url.pathExtension.lowercased()
        let copie = try AttachmentImporter.copyIntoAppSupport(
            source: url,
            bucket: .meetingDocuments(meetingStableID: meeting.ensuredStableID),
            base: base)

        let attach = MeetingAttachment(url: copie, kind: AttachmentCopyPolicy.kind(forExtension: ext))
        // Le nom **affiché** est celui du fichier d'origine, pas le nom
        // horodaté de la copie : c'est celui-là qu'on reconnaît dans le tiroir.
        attach.fileName = url.lastPathComponent
        // Un signet vers une copie interne n'a aucune valeur : son absence est
        // le signal le plus simple qu'une pièce relève de la politique D5.
        attach.bookmarkData = nil
        attach.scope = .meeting
        attach.mimeType = AttachmentCopyPolicy.mimeType(forExtension: ext)
        attach.byteCount = fileSize(at: copie)
        attach.addedByName = ownerName(in: context)
        _ = attach.ensuredStableID
        attach.meeting = meeting
        context.insert(attach)
        try context.save()
        attachLog.info("attach: \(url.lastPathComponent, privacy: .public) -> \(copie.path, privacy: .public)")
        return attach
    }

    /// Ajoute un document à la réunion + indexe son contenu pour RAG.
    /// - Returns: l'attachment créé.
    @discardableResult
    static func importDocument(
        url: URL,
        into meeting: Meeting,
        context: ModelContext,
        base: URL = AttachmentImporter.baseDirectory()
    ) async throws -> MeetingAttachment {
        let attach = try attachDocument(url: url, into: meeting, context: context, base: base)
        // L'extraction lit la **copie** : l'original peut déjà avoir disparu,
        // c'est tout l'intérêt de D5.
        let url = URL(fileURLWithPath: attach.filePath)

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

    /// Taille du fichier copié, `0` si elle n'est pas lisible (la colonne
    /// `byteCount` traite `0` comme « inconnue » et le tiroir omet alors la
    /// mention, plutôt que d'afficher « 0 o »).
    private static func fileSize(at url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }

    /// Le nom du déposant, en clair (app mono-utilisateur) : `Ajouté par
    /// Sylvain` sur la vignette de `3a-tiroir-ressources.png`. Vide si les
    /// réglages ne le donnent pas — la vignette omet alors la mention.
    private static func ownerName(in context: ModelContext) -> String {
        let tous = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        return tous.canonicalSettings?.ownerName ?? ""
    }
}

// MARK: - Array safe (duplicated for module isolation)

private extension Array {
    subscript(safe i: Int) -> Element? {
        (0..<count).contains(i) ? self[i] : nil
    }
}
