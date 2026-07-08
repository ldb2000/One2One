import XCTest
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
}
