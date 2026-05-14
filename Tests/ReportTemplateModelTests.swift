import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ReportTemplate Model Tests")
struct ReportTemplateModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [cfg])
    }

    @Test("init sets defaults")
    func initSetsDefaults() throws {
        let t = ReportTemplate(name: "Test", kind: .general)
        #expect(t.name == "Test")
        #expect(t.kindRaw == "general")
        #expect(t.historyModeRaw == "none")
        #expect(t.historyN == 0)
        #expect(t.historyK == 0)
        #expect(t.isBuiltIn == false)
        #expect(t.isArchived == false)
        #expect(t.stableID != nil)
    }

    @Test("ensuredStableID backfills nil")
    func ensuredStableIDBackfillsNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let t = ReportTemplate(name: "Test", kind: .general)
        context.insert(t)
        t.stableID = nil
        let backfilled = t.ensuredStableID
        #expect(t.stableID != nil)
        #expect(backfilled == t.stableID)
    }

    @Test("sections roundtrip")
    func sectionsRoundtrip() throws {
        let t = ReportTemplate(name: "Test", kind: .general)
        t.sections = [
            .init(title: "Résumé", hint: "Synthèse en 3 lignes"),
            .init(title: "Décisions", hint: "")
        ]
        #expect(t.sections.count == 2)
        #expect(t.sections[0].title == "Résumé")
        #expect(t.sections[1].hint == "")
    }

    @Test("kind enum accessor")
    func kindEnumAccessor() throws {
        let t = ReportTemplate(name: "Test", kind: .copil)
        #expect(t.kind == .copil)
        t.kind = .codir
        #expect(t.kindRaw == "codir")
    }
}
