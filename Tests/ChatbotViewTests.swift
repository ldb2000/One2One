import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ChatbotView — pre-fetch RAG (B1)")
@MainActor
struct ChatbotViewTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Un chunk indexé et proche de la requête produit un bloc citable [1] dans le prompt")
    func ragHitsAreFormattedWithCitation() throws {
        let context = try makeContext()

        let meeting = Meeting(title: "Comité de pilotage", date: Date(), notes: "")
        context.insert(meeting)

        let chunk = TranscriptChunk(text: "Le socle technique a tenu la charge en production.", orderIndex: 0)
        chunk.meeting = meeting
        chunk.setEmbedding([1, 0, 0], model: "test-embed")
        context.insert(chunk)

        // Chunk hors-sujet : embedding orthogonal, ne doit pas remonter avant le pertinent.
        let noise = TranscriptChunk(text: "Point météo sans rapport.", orderIndex: 1)
        noise.meeting = meeting
        noise.setEmbedding([0, 1, 0], model: "test-embed")
        context.insert(noise)

        let hits = RAGQuery.searchByVector([1, 0, 0], topK: 4, context: context)

        #expect(hits.first?.chunk.chunkId == chunk.chunkId)

        let view = ChatbotView()
        let block = view.formatRAGHits(hits)

        #expect(block.contains("[1]"))
        #expect(block.contains("Le socle technique a tenu la charge en production."))
        #expect(block.contains("Comité de pilotage"))
    }

    @Test("Sans chunk indexé, le bloc RAG est vide (fail-soft, prompt inchangé)")
    func noHitsProducesEmptyBlock() throws {
        let view = ChatbotView()
        #expect(view.formatRAGHits([]).isEmpty)
    }

    @Test("Mode B2 (tool calling) : le prompt omet le bloc « Extraits pertinents » mais garde base + historique")
    func toolCallingOmitsRAGBlockFromPrompt() throws {
        let view = ChatbotView()

        let withRAG = view.makePrompt(question: "Où en est le projet ?", databaseContext: "Projets:\n- X", ragBlock: "\nExtraits pertinents (RAG):\n[1] ...\n", history: "Utilisateur: bonjour")
        #expect(withRAG.contains("Extraits pertinents (RAG)"))
        #expect(withRAG.contains("Projets:\n- X"))
        #expect(withRAG.contains("Conversation antérieure"))

        let withoutRAG = view.makePrompt(question: "Où en est le projet ?", databaseContext: "Projets:\n- X", ragBlock: "", history: "Utilisateur: bonjour")
        #expect(!withoutRAG.contains("Extraits pertinents (RAG)"))
        #expect(withoutRAG.contains("Projets:\n- X"))
        #expect(withoutRAG.contains("Conversation antérieure"))
        #expect(withoutRAG.contains("Où en est le projet ?"))
    }
}
