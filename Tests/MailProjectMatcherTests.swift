import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MailProjectMatcherTests: XCTestCase {

    private let projects = [
        MailProjectMatcher.ProjectEntry(code: "REFSI", name: "Refonte SI Courtage",
                                        collaboratorEmails: ["alice@april.com"]),
        MailProjectMatcher.ProjectEntry(code: "DATA24", name: "Plateforme Data",
                                        collaboratorEmails: ["bob@april.com"]),
    ]

    func test_extractEmail_formatsCourants() {
        XCTAssertEqual(MailProjectMatcher.extractEmail(fromSender: "Alice Dupont <Alice@April.com>"),
                       "alice@april.com")
        XCTAssertEqual(MailProjectMatcher.extractEmail(fromSender: "bob@april.com"), "bob@april.com")
        XCTAssertNil(MailProjectMatcher.extractEmail(fromSender: "Alice Dupont"))
    }

    func test_continuiteDeFil_gagneAvecConfiance095() {
        let v = MailProjectMatcher.match(
            subject: "Re: Point hebdo courtage",
            sender: "inconnu@ext.com",
            projects: projects,
            threadProjectCodes: ["point hebdo courtage": "DATA24"]
        )
        XCTAssertEqual(v.projectCode, "DATA24")
        XCTAssertEqual(v.confidence, 0.95, accuracy: 0.001)
    }

    func test_matchSujet_nomDeProjetDansLeSujet() {
        let v = MailProjectMatcher.match(
            subject: "Avancement Refonte SI Courtage — sprint 4",
            sender: "inconnu@ext.com",
            projects: projects,
            threadProjectCodes: [:]
        )
        XCTAssertEqual(v.projectCode, "REFSI")
        XCTAssertGreaterThanOrEqual(v.confidence, 0.75)
    }

    func test_codeProjetCiteDansLeSujet_score09() {
        let v = MailProjectMatcher.match(
            subject: "[DATA24] livraison lot 2",
            sender: "inconnu@ext.com",
            projects: projects,
            threadProjectCodes: [:]
        )
        XCTAssertEqual(v.projectCode, "DATA24")
        XCTAssertGreaterThanOrEqual(v.confidence, 0.9)
    }

    func test_bonusEmailExpediteur_rehausseUnMatchSujet() {
        let sans = MailProjectMatcher.match(
            subject: "Question data", sender: "inconnu@ext.com",
            projects: projects, threadProjectCodes: [:]
        )
        let avec = MailProjectMatcher.match(
            subject: "Question data", sender: "Bob <bob@april.com>",
            projects: projects, threadProjectCodes: [:]
        )
        XCTAssertGreaterThan(avec.confidence, sans.confidence)
        XCTAssertEqual(avec.projectCode, "DATA24")
    }

    func test_emailSeul_matchFaible() {
        let v = MailProjectMatcher.match(
            subject: "Déjeuner demain ?", sender: "alice@april.com",
            projects: projects, threadProjectCodes: [:]
        )
        XCTAssertEqual(v.projectCode, "REFSI")
        XCTAssertEqual(v.confidence, 0.4, accuracy: 0.001)
    }

    func test_aucunMatch_verdictNone() {
        let v = MailProjectMatcher.match(
            subject: "Newsletter hebdomadaire", sender: "news@externe.com",
            projects: projects, threadProjectCodes: [:]
        )
        XCTAssertNil(v.projectCode)
        XCTAssertEqual(v.confidence, 0, accuracy: 0.001)
    }

    // MARK: - projectEntries(from:meetings:)

    func test_projectEntries_agregeLesEmailsDesParticipantsDesReunions() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        alice.email = "Alice@April.com"
        let manager = Collaborator(name: "Manager")
        manager.email = "manager@april.com"
        project.projectManager = manager
        context.insert(project); context.insert(alice); context.insert(manager)

        let meeting = Meeting(title: "Comité", date: Date())
        meeting.kind = .project
        meeting.project = project
        meeting.participants = [alice]
        context.insert(meeting)

        let entries = MailProjectMatcher.projectEntries(from: [project], meetings: [meeting])
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].collaboratorEmails.contains("alice@april.com"))
        XCTAssertTrue(entries[0].collaboratorEmails.contains("manager@april.com"))
    }

    func test_projectEntries_dedoublonneLesEmails() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        alice.email = "alice@april.com"
        context.insert(project); context.insert(alice)

        var meetings: [Meeting] = []
        for index in 0..<3 {
            let meeting = Meeting(title: "Comité \(index)", date: Date())
            meeting.kind = .project
            meeting.project = project
            meeting.participants = [alice]
            context.insert(meeting)
            meetings.append(meeting)
        }

        let entries = MailProjectMatcher.projectEntries(from: [project], meetings: meetings)
        XCTAssertEqual(entries[0].collaboratorEmails.filter { $0 == "alice@april.com" }.count, 1)
    }

    func test_projectEntries_ignoreLesReunionsDUnAutreProjet() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let refsi = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let data = Project(code: "DATA24", name: "Plateforme Data", domain: "Data", phase: "Run")
        let bob = Collaborator(name: "Bob")
        bob.email = "bob@april.com"
        context.insert(refsi); context.insert(data); context.insert(bob)

        let meeting = Meeting(title: "Comité Data", date: Date())
        meeting.kind = .project
        meeting.project = data
        meeting.participants = [bob]
        context.insert(meeting)

        let entries = MailProjectMatcher.projectEntries(from: [refsi], meetings: [meeting])
        XCTAssertFalse(entries[0].collaboratorEmails.contains("bob@april.com"))
    }
}
