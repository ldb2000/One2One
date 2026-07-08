import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailSuggestionServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func makeFixture() throws -> (MailIndexSuggestion, Project) {
        let project = Project(code: "P1", name: "Alpha", domain: "IT", phase: "Run")
        context.insert(project)
        let suggestion = MailIndexSuggestion(
            messageId: "msg-1", accountName: "Pro", mailbox: "INBOX",
            subject: "Sujet", sender: "a@ex.com", dateReceived: Date())
        suggestion.suggestedProject = project
        context.insert(suggestion)
        context.insert(MailScanRecord(messageId: "msg-1", verdict: .suggested))
        try context.save()
        return (suggestion, project)
    }

    /// Fetchers stubs : pas d'AppleScript, matérialisation minimale (le
    /// pipeline chunk+embedding réel de ProjectMailStore est hors de portée
    /// des tests — MLX indisponible sous swift test).
    private func stubFetchers() -> MailSuggestionService.Fetchers {
        MailSuggestionService.Fetchers(
            fetchBody: { _ in "corps du mail" },
            fetchAttachments: { _ in [] },
            materialize: { snippet, body, _, project, context in
                let mail = ProjectMail(messageId: snippet.messageId,
                                       accountName: snippet.accountName,
                                       mailbox: snippet.mailbox,
                                       subject: snippet.subject,
                                       sender: snippet.sender,
                                       dateReceived: snippet.dateReceived,
                                       body: body)
                mail.project = project
                context.insert(mail)
                try context.save()
            }
        )
    }

    func test_validate_materialiseEtSupprimeLaSuggestion() async throws {
        let (suggestion, project) = try makeFixture()
        try await MailSuggestionService.validate(suggestion, in: context, fetchers: stubFetchers())

        let mails = try context.fetch(FetchDescriptor<ProjectMail>())
        XCTAssertEqual(mails.count, 1)
        XCTAssertEqual(mails.first?.messageId, "msg-1")
        XCTAssertEqual(mails.first?.project?.code, project.code)
        XCTAssertEqual(mails.first?.body, "corps du mail")

        XCTAssertTrue(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).isEmpty)
        let record = try context.fetch(FetchDescriptor<MailScanRecord>()).first
        XCTAssertEqual(record?.verdict, .attached)
    }

    func test_validate_sansProjet_leveEtConserveLaSuggestion() async throws {
        let (suggestion, _) = try makeFixture()
        suggestion.suggestedProject = nil

        do {
            try await MailSuggestionService.validate(suggestion, in: context, fetchers: stubFetchers())
            XCTFail("validate aurait dû lever")
        } catch { /* attendu */ }
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).count, 1)
    }

    func test_validate_echecFetch_conserveLaSuggestionEtLeRecord() async throws {
        let (suggestion, _) = try makeFixture()
        var fetchers = stubFetchers()
        fetchers.fetchBody = { _ in throw NSError(domain: "stub", code: -1) }

        do {
            try await MailSuggestionService.validate(suggestion, in: context, fetchers: fetchers)
            XCTFail("validate aurait dû lever")
        } catch { /* attendu */ }
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailScanRecord>()).first?.verdict, .suggested)
    }

    func test_ignore_supprimeEtTraceLeVerdict() throws {
        let (suggestion, _) = try makeFixture()
        MailSuggestionService.ignore(suggestion, in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<MailIndexSuggestion>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailScanRecord>()).first?.verdict, .ignored)
    }
}
