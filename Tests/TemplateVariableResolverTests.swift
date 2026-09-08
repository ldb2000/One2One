import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class TemplateVariableResolverTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_substitutes_simpleMeetingFields() {
        let m = Meeting(title: "Sync", date: Date(timeIntervalSince1970: 1_700_000_000))
        m.kind = .oneToOne
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "T:{{title}} K:{{kind}}",
            for: m, in: context
        )
        XCTAssertTrue(resolved.contains("T:Sync"))
        XCTAssertTrue(resolved.contains("K:One-to-One") || resolved.contains("K:1:1 Collaborateur"))
    }

    // MARK: - Lot 15 — blocs optionnels

    func test_lot15_variablesResolvent_lesBlocsOptionnels() throws {
        let m = Meeting(title: "Revue", date: Date())
        context.insert(m)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = m
        context.insert(piece)
        let planche = Board(index: 0, title: "Zones", mode: .diagram, t: 120)
        planche.meeting = m
        context.insert(planche)
        try context.save()

        let resolved = TemplateVariableResolver.resolve(
            prompt: "P:{{pieces_epinglees}} C:{{captures_jointes}} B:{{planches}} "
                  + "E:{{engagements}} F:{{fiche_projet.maj}}",
            for: m, in: context
        )
        XCTAssertTrue(resolved.contains("04:12"))
        XCTAssertTrue(resolved.contains("Chiffrage.xlsx"))
        XCTAssertTrue(resolved.contains("02:00"))
        XCTAssertTrue(resolved.contains("Zones"))
        // Une variable inconnue reste littérale ; celles du lot 15 ne doivent
        // plus l'être, même quand elles rendent vide.
        XCTAssertFalse(resolved.contains("{{captures_jointes}}"))
        XCTAssertFalse(resolved.contains("{{engagements}}"))
        XCTAssertFalse(resolved.contains("{{fiche_projet.maj}}"))
    }

    func test_lot15_piecesEpinglees_respecteLaCaseDuTiroir() throws {
        let m = Meeting(title: "Revue", date: Date())
        var options = m.reportAttachmentOptions
        options.attachPinned = false
        m.reportAttachmentOptions = options
        context.insert(m)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = m
        context.insert(piece)
        try context.save()

        let resolved = TemplateVariableResolver.resolve(
            prompt: "P:{{pieces_epinglees}}", for: m, in: context
        )
        XCTAssertEqual(resolved, "P:")
    }

    func test_lot15_paletteExposeLesCinqVariables() {
        for nom in ["pieces_epinglees", "captures_jointes", "planches",
                    "engagements", "fiche_projet.maj"] {
            XCTAssertTrue(RefonteReportVariables.names.contains(nom), nom)
        }
    }

    func test_unknownVariable_isLeftLiteral() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "Hello {{not_a_var}}",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "Hello {{not_a_var}}")
    }

    func test_projectVar_emptyWhenNoProject() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "Projet:{{project.name}}",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "Projet:")
    }

    func test_projectVar_filledWhenProject() throws {
        let proj = Project(code: "PX", name: "MyProj", domain: "D", phase: "Build")
        context.insert(proj)
        let m = Meeting(title: "X", date: Date())
        m.project = proj
        context.insert(m)
        try context.save()
        let resolved = TemplateVariableResolver.resolve(
            prompt: "Projet:{{project.name}} ({{project.code}})",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "Projet:MyProj (PX)")
    }

    func test_collabVar_emptyWhenNoCollab() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "C:{{collab.name}}",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "C:")
    }
}
