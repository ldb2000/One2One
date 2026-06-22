import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class AgendaProjectResolverTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    @discardableResult
    private func makeProject(name: String) throws -> Project {
        let proj = Project(code: String(name.prefix(4)).uppercased(), name: name,
                           domain: "Test", phase: "Build")
        context.insert(proj)
        try context.save()
        return proj
    }

    // MARK: - Normalisation

    func test_normalizedKey_stripsAccentsPunctuationAndCase() {
        XCTAssertEqual(AgendaProjectResolver.normalizedKey("[Téléphonie iPMI] - Cadrage !"),
                       "telephonie ipmi cadrage")
        // Deux variantes du même titre récurrent → même clé.
        XCTAssertEqual(AgendaProjectResolver.normalizedKey("Comité Urbanisation - Juin"),
                       AgendaProjectResolver.normalizedKey("comite urbanisation – juin"))
    }

    // MARK: - Précédence règle > suggestion fuzzy

    func test_resolve_ruleWinsOverFuzzySuggestion() throws {
        let nevidis = try makeProject(name: "NEVIDIS")
        let diapason = try makeProject(name: "Diapason")
        // Le titre matche fortement "NEVIDIS" en fuzzy, mais une règle manuelle
        // pointe vers Diapason : la règle gagne.
        AgendaProjectResolver.setRule(title: "NEVIDIS point hebdo",
                                      project: diapason, ignored: false, context: context)
        try context.save()

        let index = AgendaProjectResolver.makeIndex(context: context)
        guard case .rule(let rule) = index.resolve(title: "NEVIDIS point hebdo") else {
            return XCTFail("Expected .rule")
        }
        XCTAssertEqual(rule.project?.name, "Diapason")
        XCTAssertNotEqual(rule.project?.name, nevidis.name)
    }

    func test_resolve_fuzzySuggestionWhenNoRule() throws {
        try makeProject(name: "Diapason")
        let index = AgendaProjectResolver.makeIndex(context: context)
        guard case .suggested(let project, let score) = index.resolve(title: "Diapason : solution préconisée") else {
            return XCTFail("Expected .suggested")
        }
        XCTAssertEqual(project.name, "Diapason")
        XCTAssertGreaterThanOrEqual(score, AgendaProjectResolver.suggestionThreshold)
    }

    func test_resolve_noneWhenNothingMatches() throws {
        try makeProject(name: "Diapason")
        let index = AgendaProjectResolver.makeIndex(context: context)
        guard case .none = index.resolve(title: "Ordonnance prise de sang") else {
            return XCTFail("Expected .none")
        }
    }

    // MARK: - Règle « Ignoré »

    func test_resolve_ignoredRule() throws {
        AgendaProjectResolver.setRule(title: "Psy", project: nil, ignored: true, context: context)
        try context.save()

        let index = AgendaProjectResolver.makeIndex(context: context)
        let assignment = index.resolve(title: "Psy")
        XCTAssertTrue(assignment.isIgnored)
        XCTAssertNil(assignment.project)
    }

    // MARK: - CRUD

    func test_setRule_overwritesExistingRuleForSameTitle() throws {
        let nevidis = try makeProject(name: "NEVIDIS")
        let diapason = try makeProject(name: "Diapason")

        AgendaProjectResolver.setRule(title: "Point hebdo", project: nevidis, ignored: false, context: context)
        AgendaProjectResolver.setRule(title: "Point hebdo", project: diapason, ignored: false, context: context)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<AgendaProjectRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.project?.name, "Diapason")
    }

    func test_setRule_nilProjectNotIgnored_removesRule() throws {
        let nevidis = try makeProject(name: "NEVIDIS")
        AgendaProjectResolver.setRule(title: "Point hebdo", project: nevidis, ignored: false, context: context)
        AgendaProjectResolver.setRule(title: "Point hebdo", project: nil, ignored: false, context: context)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<AgendaProjectRule>())
        XCTAssertTrue(rules.isEmpty)
    }

    func test_removeRule_deletesRule() throws {
        AgendaProjectResolver.setRule(title: "Psy", project: nil, ignored: true, context: context)
        AgendaProjectResolver.removeRule(for: "Psy", context: context)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<AgendaProjectRule>())
        XCTAssertTrue(rules.isEmpty)
    }

    // MARK: - Propagation aux réunions importées

    func test_setRule_appliesProjectToMatchingProjectMeetings() throws {
        let diapason = try makeProject(name: "Diapason")
        let meeting = Meeting(title: "Point hebdo", date: Date())
        meeting.kind = .global
        context.insert(meeting)
        let oneToOne = Meeting(title: "Point hebdo", date: Date())
        oneToOne.kind = .oneToOne
        let someone = Collaborator(name: "Quelqu'un")
        context.insert(someone)
        oneToOne.participants.append(someone)
        context.insert(oneToOne)
        try context.save()

        AgendaProjectResolver.setRule(title: "Point hebdo", project: diapason, ignored: false, context: context)
        try context.save()

        // Réunion globale sans projet → reclassée projet ; le 1:1 n'est pas touché.
        XCTAssertEqual(meeting.kind, .project)
        XCTAssertEqual(meeting.project?.name, "Diapason")
        XCTAssertEqual(oneToOne.kind, .oneToOne)
        XCTAssertNil(oneToOne.project)
    }

    // MARK: - Règle orpheline

    func test_resolve_orphanRuleFallsBackToNone() throws {
        let proj = try makeProject(name: "Éphémère")
        AgendaProjectResolver.setRule(title: "Réunion X", project: proj, ignored: false, context: context)
        try context.save()
        context.delete(proj)
        try context.save()

        let index = AgendaProjectResolver.makeIndex(context: context)
        let assignment = index.resolve(title: "Réunion X")
        if case .rule = assignment {
            XCTFail("Orphan rule should resolve to .none or .suggested, not .rule")
        }
    }
}
