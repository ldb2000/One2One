import Foundation
import SwiftData
import Testing
@testable import OneToOne

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema(CurrentSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

private func makeChunk(_ text: String, embedding: [Float]? = nil, order: Int = 0) -> TranscriptChunk {
    let chunk = TranscriptChunk(text: text, orderIndex: order, sourceType: "meeting")
    if let embedding {
        chunk.setEmbedding(embedding, model: "test")
    }
    return chunk
}

/// Tests sur `RAGQuery.searchHybrid(queryVec:queryText:...)`, la variante
/// testable qui prend un vecteur pré-calculé (pas d'appel MLX réel — voir
/// CLAUDE.md, `swift test` n'embarque pas `default.metallib`).
@Suite("RAGQuery.searchHybrid — fusion BM25 + cosine via RRF (B3)")
@MainActor
struct RAGHybridSearchTests {

    @Test("un chunk pertinent lexicalement ET sémantiquement remonte plus haut qu'avec cosine seul")
    func lexicalAndSemanticMatchClimbsAboveCosineOnly() throws {
        let context = try makeContext()

        // Cosine parfait, aucun recouvrement lexical avec la requête.
        let cosineTop = makeChunk("Rien à voir avec la requête, discussion générale sur l'équipe.", embedding: [1, 0, 0])
        // Cosine correct (0.8) mais recouvrement lexical exact avec la requête.
        let mixed = makeChunk("Livraison critique serveur en retard, urgence sur le déploiement.", embedding: [0.8, 0.6, 0])
        context.insert(cosineTop)
        context.insert(mixed)
        try context.save()

        let queryVec: [Float] = [1, 0, 0]
        let queryText = "livraison critique serveur"

        let cosineOnly = RAGQuery.searchByVector(queryVec, topK: 1, context: context)
        #expect(cosineOnly.first?.chunk.chunkId == cosineTop.chunkId)

        let hybrid = RAGQuery.searchHybrid(queryVec: queryVec, queryText: queryText, topK: 2, context: context)
        #expect(hybrid.first?.chunk.chunkId == mixed.chunkId)
    }

    @Test("un nom propre inventé remonte via BM25 même sans embedding (jamais trouvé en cosine seul)")
    func pureLexicalMatchSurfacesWithoutEmbedding() throws {
        let context = try makeContext()

        // Aucun embedding : ne peut jamais apparaître dans une recherche cosine.
        let lexicalOnly = makeChunk("Le lancement de ProjectXylophone est prévu la semaine prochaine.")
        // Embedding parfait mais aucun mot en commun avec la requête.
        let semanticDistractor = makeChunk("Compte rendu budgétaire du comité de pilotage.", embedding: [1, 0, 0])
        context.insert(lexicalOnly)
        context.insert(semanticDistractor)
        try context.save()

        let queryVec: [Float] = [1, 0, 0]
        let queryText = "ProjectXylophone"

        let cosineOnly = RAGQuery.searchByVector(queryVec, topK: 5, context: context)
        #expect(!cosineOnly.contains { $0.chunk.chunkId == lexicalOnly.chunkId })

        let hybrid = RAGQuery.searchHybrid(queryVec: queryVec, queryText: queryText, topK: 5, context: context)
        #expect(hybrid.contains { $0.chunk.chunkId == lexicalOnly.chunkId })
    }

    @Test("une paraphrase sans recouvrement lexical retombe sur le classement cosine")
    func pureSemanticQueryFallsBackToCosineOrder() throws {
        let context = try makeContext()

        let semanticMatch = makeChunk("Réorganisation complète des équipes annoncée hier.", embedding: [1, 0, 0])
        let other = makeChunk("Compte rendu de la réunion budget.", embedding: [0, 1, 0])
        context.insert(semanticMatch)
        context.insert(other)
        try context.save()

        let queryVec: [Float] = [1, 0, 0]
        // Ni "réorganisation" ni "équipes" : aucun terme en commun avec les chunks indexés.
        let queryText = "restructuration organisationnelle"

        let cosineOnly = RAGQuery.searchByVector(queryVec, topK: 2, context: context)
        let hybrid = RAGQuery.searchHybrid(queryVec: queryVec, queryText: queryText, topK: 2, context: context)

        #expect(hybrid.map { $0.chunk.chunkId } == cosineOnly.map { $0.chunk.chunkId })
        #expect(hybrid.first?.chunk.chunkId == semanticMatch.chunkId)
    }
}

@Suite("ToolRouter — parsing use_hybrid (B3)")
struct ToolRouterHybridParsingTests {

    @Test("use_hybrid absent retombe sur false (comportement B2 inchangé)")
    func defaultsToFalse() throws {
        let request = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"budget Q3"}"#))
        #expect(request.useHybrid == false)
    }

    @Test("use_hybrid: true est retenu")
    func explicitTrueIsRetained() throws {
        let request = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"budget Q3","use_hybrid":true}"#))
        #expect(request.useHybrid == true)
    }

    @Test("use_hybrid: false est retenu explicitement")
    func explicitFalseIsRetained() throws {
        let request = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"budget Q3","use_hybrid":false}"#))
        #expect(request.useHybrid == false)
    }
}

@Suite("ToolSpec — use_hybrid exposé au LLM (B3)")
struct ToolSpecHybridEncodingTests {

    @Test("search_knowledge expose use_hybrid en booléen optionnel")
    func useHybridIsOptionalBoolean() throws {
        let data = try JSONEncoder().encode(ToolCatalog.searchKnowledge)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let function = try #require(json["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])

        let useHybrid = try #require(properties["use_hybrid"] as? [String: Any])
        #expect(useHybrid["type"] as? String == "boolean")

        let required = try #require(parameters["required"] as? [String])
        #expect(!required.contains("use_hybrid"))
    }
}
