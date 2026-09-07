import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le jeu de démonstration doit reproduire **exactement** les chiffres de
/// `1a-cockpit.png`, sinon la recette visuelle compare deux écrans différents
/// et ne prouve rien.
@Suite("Jeu de démonstration de la refonte")
@MainActor
struct RefonteDemoSeedTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("Reproduit les chiffres de la capture 1a")
    func matchesCapture() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)

        #expect(reunion.title == "[P25_110] Partage statut final et chiffrage reste à faire")
        #expect(reunion.project?.name == "S/D — Modernisation CI/CD")
        #expect(reunion.kind == .project)
        #expect(reunion.durationSeconds == 1_404)          // 23:24
        #expect(reunion.participants.count == 6)
        #expect(reunion.tasks.count == 12)
        #expect(reunion.decisions.count == 3)
        #expect(reunion.meetingAlerts.count == 5)
        #expect(!reunion.liveNotes.isEmpty)
        #expect(reunion.transcriptSegments.count == 4)

        let kpi = MeetingKPIBuilder.build(meeting: reunion)
        #expect(kpi.presence.percent == 100)
        // Les six pastilles de la capture, triées par nom (cf.
        // MeetingKPIBuilder : SwiftData ne garantit pas l'ordre d'une relation).
        #expect(kpi.presence.initials == ["CA", "CP", "LD", "LS", "NL", "PY"])
        #expect(kpi.actions.total == 12)
        #expect(kpi.actions.unassigned == 9)
        #expect(kpi.decisions.count == 3)
        #expect(kpi.decisions.budgetCount == 1)
        #expect(kpi.decisions.first?.contains("partenaire") == true)
        #expect(kpi.risks.count == 5)
        #expect(kpi.risks.criticalCount == 2)
    }

    @Test("Rejouer le semis ne duplique ni la réunion, ni le projet, ni les collaborateurs")
    func idempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = RefonteDemoSeed.seed(in: context)
        _ = RefonteDemoSeed.seed(in: context)

        #expect(try context.fetch(FetchDescriptor<Meeting>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Collaborator>()).count == 6)
        #expect(try context.fetch(FetchDescriptor<ActionTask>()).count == 12)
        #expect(try context.fetch(FetchDescriptor<ProjectAlert>()).count == 5)
    }

    @Test("Le semis réutilise un collaborateur qui existe déjà, sans le dupliquer")
    func reusesExistingCollaborators() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Le poste réel contient déjà « Laurent Deberti » : le semis ne doit
        // pas en créer un second.
        let deja = Collaborator(name: "laurent deberti", role: "Manager")
        context.insert(deja)
        try context.save()

        let reunion = RefonteDemoSeed.seed(in: context)
        #expect(try context.fetch(FetchDescriptor<Collaborator>()).count == 6)
        #expect(reunion.participants.contains { $0.persistentModelID == deja.persistentModelID })
    }

    @Test("Le mode Relire et le mode Préparer trouvent de quoi s'afficher")
    func spacesHaveContent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)

        // Relire : résumé et décisions présents, donc aucune invite d'état vide.
        #expect(!reunion.shortSummary.isEmpty)
        #expect(!reunion.decisions.isEmpty)

        // Préparer : les alertes du projet remontent (les cinq risques y sont
        // aussi rattachés).
        let contexte = MeetingPrepareBuilder.build(meeting: reunion, allMeetings: [reunion])
        #expect(contexte.alertTitles.count == 5)
        #expect(contexte.lastPoints.isEmpty)   // une seule réunion dans le jeu
    }
}
