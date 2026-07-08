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
        try context.save()
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
        context.insert(MailScanRecord(messageId: "s-orphan", verdict: .suggested))
        context.insert(MailScanRecord(messageId: "s-ok", verdict: .suggested))
        try context.save()

        let deleted = MailScanStore.deleteOrphanSuggestions(in: context)
        try context.save()
        XCTAssertEqual(deleted, 1)
        let remaining = try context.fetch(FetchDescriptor<MailIndexSuggestion>())
        XCTAssertEqual(remaining.map(\.messageId), ["s-ok"])

        // Le MailScanRecord de l'orphelin doit disparaître avec la suggestion
        // (sinon le messageId reste « connu » à jamais et n'est plus jamais
        // ré-évalué). Le record d'un messageId non-orphelin doit survivre.
        let remainingRecords = try context.fetch(FetchDescriptor<MailScanRecord>())
        XCTAssertFalse(remainingRecords.contains { $0.messageId == "s-orphan" })
        XCTAssertTrue(remainingRecords.contains { $0.messageId == "s-ok" })
    }
}
