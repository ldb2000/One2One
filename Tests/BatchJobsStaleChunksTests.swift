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
