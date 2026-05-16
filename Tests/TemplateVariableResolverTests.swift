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
