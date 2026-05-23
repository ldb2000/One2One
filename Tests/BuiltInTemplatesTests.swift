import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class BuiltInTemplatesTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_seedIfNeeded_insertsAllSeeds_onFirstCall() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        ))
        XCTAssertEqual(count, BuiltInTemplates.all.count)
    }

    func test_seedIfNeeded_isIdempotent() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        ))
        XCTAssertEqual(count, BuiltInTemplates.all.count)
    }

    func test_seedIfNeeded_doesNotOverwriteEditedBuiltIn() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true && $0.name == "Global" }
        )
        let global = try context.fetch(descriptor).first
        XCTAssertNotNil(global)
        global?.promptBody = "EDITED"
        try context.save()

        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let again = try context.fetch(descriptor).first
        XCTAssertEqual(again?.promptBody, "EDITED")
    }

    func test_dict_contains_all_seed_names() {
        let names = Set(BuiltInTemplates.dict.keys)
        XCTAssertEqual(names, [
            "Global", "1:1 Collaborateur", "1:1 Manager",
            "COPIL", "COSUI", "CODIR",
            "Préparation", "Restitution / Démo",
            "Séance de travail / Workshop",
            "Architecture technique d'équipe"
        ])
        XCTAssertEqual(names.count, BuiltInTemplates.all.count)
    }
}
