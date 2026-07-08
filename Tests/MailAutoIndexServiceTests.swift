import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailAutoIndexServiceTests: XCTestCase {

    func test_outcome_seuils() {
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.8, autoThreshold: 0.75, suggestThreshold: 0.45), .attach)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.75, autoThreshold: 0.75, suggestThreshold: 0.45), .attach)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.6, autoThreshold: 0.75, suggestThreshold: 0.45), .suggest)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.45, autoThreshold: 0.75, suggestThreshold: 0.45), .suggest)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0.2, autoThreshold: 0.75, suggestThreshold: 0.45), .ignore)
        XCTAssertEqual(MailAutoIndexService.outcome(confidence: 0, autoThreshold: 0.75, suggestThreshold: 0.45), .ignore)
    }

    func test_appSettings_mailboxesAccesseurJSON() {
        let s = AppSettings()
        XCTAssertEqual(s.mailAutoIndexMailboxes, [])
        let refs = [MailboxRef(accountName: "Pro", mailboxName: "INBOX"),
                    MailboxRef(accountName: "Perso", mailboxName: "INBOX")]
        s.mailAutoIndexMailboxes = refs
        XCTAssertEqual(s.mailAutoIndexMailboxes, refs)
        // JSON invalide → tableau vide, pas de crash
        s.mailAutoIndexMailboxesJSON = "{pas-du-json"
        XCTAssertEqual(s.mailAutoIndexMailboxes, [])
    }

    func test_threadProjectCodes_construitDepuisProjectMail() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: cfg)
        let context = container.mainContext

        let project = Project(code: "REFSI", name: "Refonte SI", domain: "IT", phase: "Run")
        context.insert(project)
        let mail = ProjectMail(messageId: "m1", accountName: "Pro", mailbox: "INBOX",
                               subject: "Re: Point hebdo", sender: "a@ex.com",
                               threadTopic: "Point hebdo")
        mail.project = project
        context.insert(mail)
        try context.save()

        let map = MailAutoIndexService.threadProjectCodes(in: context)
        XCTAssertEqual(map["point hebdo"], "REFSI")
    }
}
