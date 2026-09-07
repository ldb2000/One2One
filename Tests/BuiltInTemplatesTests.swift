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
            "Architecture technique d'équipe",
            "Escalade"
        ])
        XCTAssertEqual(names.count, BuiltInTemplates.all.count)
    }

    // MARK: - Lot 15 — Escalade et révisions versionnées

    func test_lot15_escaladeEstSemee() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let all = try context.fetch(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }))
        let escalade = all.first { $0.name == BuiltInTemplates.d11_escalade.name }
        XCTAssertNotNil(escalade)
        XCTAssertEqual(escalade?.kind, .escalade)
        XCTAssertEqual(escalade?.kind.audience, .hr)
    }

    func test_lot15_revisionsCouvrentLesSeedsRevises() {
        for nom in [BuiltInTemplates.d1_global.name,
                    BuiltInTemplates.d2_oneToOne.name,
                    BuiltInTemplates.d3_manager.name,
                    BuiltInTemplates.d4_copil.name,
                    BuiltInTemplates.d5_cosui.name,
                    BuiltInTemplates.d9_workshop.name] {
            XCTAssertNotNil(BuiltInTemplates.revisions[nom], nom)
        }
        // Toute clé de révision doit désigner un seed livré : une clé
        // orpheline ne serait jamais appliquée et personne ne le verrait.
        for nom in BuiltInTemplates.revisions.keys {
            XCTAssertNotNil(BuiltInTemplates.dict[nom], nom)
        }
    }

    func test_lot15_revisionAppliqueeUneSeuleFois_etPreserveLEdition() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()

        let nom = BuiltInTemplates.d9_workshop.name
        let clef = BuiltInTemplates.revisionKey(for: nom)
        // Rejouer la révision : on remet le marqueur à zéro.
        UserDefaults.standard.removeObject(forKey: clef)

        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true })
        let ligne = try context.fetch(descriptor).first { $0.name == nom }
        XCTAssertNotNil(ligne)
        ligne?.promptBody = "AVANT RÉVISION"
        try context.save()

        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        XCTAssertTrue(ligne?.promptBody.contains("{{planches}}") == true)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: clef),
                       BuiltInTemplates.revisions[nom])

        // L'utilisateur édite après la révision : une seconde passe n'écrase pas.
        ligne?.promptBody = "MON PROMPT À MOI"
        try context.save()
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        XCTAssertEqual(ligne?.promptBody, "MON PROMPT À MOI")
    }

    func test_lot15_gabaritsRevisesPortentLeursBlocs() {
        XCTAssertTrue(BuiltInTemplates.d2_oneToOne.promptBody.contains("{{engagements}}"))
        XCTAssertTrue(BuiltInTemplates.d2_oneToOne.preamble
            .contains(ReportOptionalBlocks.commitmentsPrivacyNotice))
        XCTAssertTrue(BuiltInTemplates.d3_manager.promptBody.contains("{{engagements}}"))
        XCTAssertTrue(BuiltInTemplates.d9_workshop.promptBody.contains("{{planches}}"))
        XCTAssertTrue(BuiltInTemplates.d9_workshop.promptBody.contains("{{captures_jointes}}"))
        for seed in [BuiltInTemplates.d1_global,
                     BuiltInTemplates.d4_copil,
                     BuiltInTemplates.d5_cosui] {
            XCTAssertTrue(seed.promptBody.contains("{{pieces_epinglees}}"), seed.name)
            XCTAssertTrue(seed.promptBody.contains("{{captures_jointes}}"), seed.name)
            XCTAssertTrue(seed.promptBody.contains("{{fiche_projet.maj}}"), seed.name)
        }
        XCTAssertTrue(BuiltInTemplates.d11_escalade.promptBody.contains("{{engagements}}"))
    }
}
