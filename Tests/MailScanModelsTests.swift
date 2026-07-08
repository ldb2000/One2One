import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailScanModelsTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_mailScanRecord_wrapperVerdict_etPersistance() throws {
        let r = MailScanRecord(messageId: "msg-1", verdict: .suggested)
        context.insert(r)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MailScanRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.verdict, .suggested)

        // Raw inconnu → fallback .ignored
        fetched.first?.verdictRaw = "n-importe-quoi"
        XCTAssertEqual(fetched.first?.verdict, .ignored)
    }

    func test_mailIndexSuggestion_persistanceAvecProjet() throws {
        let project = Project(code: "PRJ1", name: "Refonte SI", domain: "IT", phase: "Cadrage")
        context.insert(project)
        let s = MailIndexSuggestion(
            messageId: "msg-2", accountName: "Pro", mailbox: "INBOX",
            subject: "Re: Refonte SI — planning", sender: "Alice <alice@ex.com>",
            dateReceived: Date(), preview: "aperçu", confidence: 0.6
        )
        s.suggestedProject = project
        context.insert(s)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MailIndexSuggestion>())
        XCTAssertEqual(fetched.first?.suggestedProject?.code, "PRJ1")
        XCTAssertEqual(fetched.first?.confidence ?? 0, 0.6, accuracy: 0.001)
    }

    func test_appSettings_defautsMailAutoIndex() {
        let s = AppSettings()
        XCTAssertFalse(s.mailAutoIndexEnabled)
        XCTAssertEqual(s.mailAutoIndexMailboxesJSON, "[]")
        XCTAssertEqual(s.mailAutoIndexLookbackDays, 90)
        XCTAssertEqual(s.mailAutoIndexIntervalMinutes, 60)
        XCTAssertEqual(s.mailAutoIndexAutoThreshold, 0.75, accuracy: 0.001)
        XCTAssertEqual(s.mailAutoIndexSuggestThreshold, 0.45, accuracy: 0.001)
        XCTAssertNil(s.mailAutoIndexLastScanAt)
    }

    func test_mailboxRef_codableRoundTrip() throws {
        let refs = [MailboxRef(accountName: "Pro", mailboxName: "INBOX")]
        let data = try JSONEncoder().encode(refs)
        let decoded = try JSONDecoder().decode([MailboxRef].self, from: data)
        XCTAssertEqual(decoded, refs)
    }
}
