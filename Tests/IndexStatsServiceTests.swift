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
