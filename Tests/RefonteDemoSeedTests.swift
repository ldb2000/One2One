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
        // « 4 sept. 2026 · 9:15 » dans la barre d'espaces de la capture. Le
        // premier semis tombait un an trop tôt, ce qui décalait le jour de la
        // semaine et tous les raccourcis d'échéance avec lui.
        var composantes = Calendar(identifier: .gregorian)
        composantes.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        #expect(composantes.component(.year, from: reunion.date) == 2026)
        #expect(composantes.component(.month, from: reunion.date) == 9)
        #expect(composantes.component(.day, from: reunion.date) == 4)
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

    @Test("Reproduit les groupes du rail : À ASSIGNER — 9, REPORTÉES DU 1ER SEPT. — 3")
    func matchesRailGroups() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)

        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks)
        #expect(groupes.count == 2)
        #expect(groupes[0].identite == .aAssigner)
        #expect(groupes[0].actions.count == 9)
        #expect(groupes[1].actions.count == 3)
        // Les trois libellés de la capture, dans leur ordre.
        #expect(groupes[0].actions.prefix(3).map(\.title) == [
            "Vérifier l'état des comptes GitLab",
            "Clarifier la situation de facturation (40k)",
            "Chiffrer la fin de migration Marine"
        ])
        #expect(groupes[1].libelle == "Reportées du 1er sept. — 3")
        #expect(groupes[1].rendu == .lignes)
        #expect(groupes[1].actions.map(\.title).sorted() == [
            "Planification de la formation Admin",
            "Préparer gitlab.rb et valider les flux",
            "Relancer Alexis/Jeff pour l'estimation"
        ])
    }

    @Test("Les pilules des trois premières cartes sont celles de la capture")
    func matchesCardPills() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)
        let cartes = ActionsRailGrouping.groupes(for: reunion.tasks)[0].actions

        // « ＋ ... · <jour> · 2h » — une échéance dans la semaine, donc nommée
        // par son jour, et une charge de deux heures. Le mot exact dépend
        // d'aujourd'hui : mesuré depuis la date de la réunion, c'est « Lundi ».
        #expect(cartes[0].effortMinutes == 120)
        #expect(ActionCardEditing.chargeLabel(cartes[0].effortMinutes ?? 0) == "2h")
        #expect(ActionCardEditing.libelleEcheance(cartes[0], reference: reunion.date) == "Lundi")
        // « ＋ Patrice · ＋ échéance » : rien de renseigné, deux invites.
        #expect(cartes[1].dueDate == nil)
        #expect(cartes[1].effortMinutes == nil)
        #expect(ActionCardEditing.libelleEcheance(cartes[1]) == "＋ échéance")
        // « ... · 11 sept. · 1j »
        #expect(ActionCardEditing.chargeLabel(cartes[2].effortMinutes ?? 0) == "1j")
    }

    @Test("La première action porte sa chaîne de citation et suggère un responsable")
    func firstActionCarriesItsSource() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)
        let carte = ActionsRailGrouping.groupes(for: reunion.tasks)[0].actions[0]

        // Le segment de 04:12 : « Tous les comptes ont été désactivés… »
        #expect(carte.sourceRef?.kind == .transcript)
        #expect(carte.sourceRef?.t == 252)
        #expect(ActionCardEditing.libelleSource(carte) == "04:12 ↗")
        // Règle 1 de `OwnerSuggestion` : le locuteur de ce segment.
        let suggestion = OwnerSuggestion.suggestion(for: carte, in: reunion,
                                                    projectTasks: reunion.tasks)
        #expect(suggestion?.name == "Laurent Deberti")
    }

    @Test("Rejouer le semis ne duplique ni la réunion, ni le projet, ni les collaborateurs")
    func idempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = RefonteDemoSeed.seed(in: context)
        _ = RefonteDemoSeed.seed(in: context)

        // Deux réunions : celle de la capture et le COSUI du 1er septembre
        // d'où trois actions sont reportées.
        #expect(try context.fetch(FetchDescriptor<Meeting>()).count == 2)
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
        // aussi rattachés), et le COSUI du 1er septembre alimente « DERNIERS
        // POINTS » avec son résumé.
        let toutes = try context.fetch(FetchDescriptor<Meeting>())
        let contexte = MeetingPrepareBuilder.build(meeting: reunion, allMeetings: toutes)
        #expect(contexte.alertTitles.count == 5)
        #expect(contexte.lastPoints.count == 1)
        #expect(contexte.lastPoints.first?.title == RefonteDemoSeed.carriedMeetingTitle)
        #expect(contexte.lastPoints.first?.shortSummary.isEmpty == false)
    }

    // MARK: - Lot 2 : les quatre notes horodatées de la capture

    @Test("Les quatre notes horodatées de la capture sont semées, dont une décision")
    func notesHorodatees() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)

        let notes = MeetingNoteStore.sorted(reunion.timedNotes)
        #expect(notes.count == 4)
        #expect(notes.map(\.t) == [252, 468, 663, 920])   // 04:12, 07:48, 11:03, 15:20
        #expect(notes.map(\.kind) == [.note, .note, .decision, .note])
        #expect(notes[0].text.contains("Gros morceau"))
        #expect(notes[2].text.contains("partenaire finalise"))
    }

    @Test("La reprise de liveNotes n'ajoute pas une cinquième ligne à t = 0")
    func pasDeReprise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)

        // `liveNotes` reste rempli — l'éditeur markdown et les gabarits de
        // rapport le lisent —, mais le drapeau de migration est posé : sinon la
        // recette montrerait cinq lignes là où la capture en montre quatre.
        #expect(!reunion.liveNotes.isEmpty)
        #expect(reunion.notesMigrated)
        #expect(MeetingNoteStore.importLiveNotesIfNeeded(reunion, in: context) == nil)
        #expect(reunion.timedNotes.count == 4)
    }

    @Test("Rejouer le semis ne duplique pas les notes horodatées")
    func notesIdempotentes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = RefonteDemoSeed.seed(in: context)
        _ = RefonteDemoSeed.seed(in: context)
        #expect(try context.fetch(FetchDescriptor<MeetingNote>()).count == 4)
    }

    @Test("La frise porte quatre repères, dont un losange de décision")
    func reperesDeLaFrise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)

        let repères = MeetingTimelineMarkers.markers(for: reunion)
        #expect(repères.count == 4)
        #expect(repères.filter { $0.kind == .decision }.map(\.t) == [663])
        #expect(repères.filter { $0.kind == .note }.count == 3)
    }

    // MARK: - Fiche projet (lot 9, capture 3b)

    @Test("Le projet de démonstration porte la fiche de la capture 3b")
    func projectCardMatchesCapture() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)
        let projet = try #require(reunion.project)

        #expect(projet.budgetCons == 40_000)
        #expect(projet.budgetInit == 61_000)
        #expect(projet.tags == ["GitLab", "Nexus", "PostgreSQL", "Cléva"])
        #expect(projet.scopeText.contains("GitLab auto-hébergé"))

        let jalons = ProjectCardBuilder.sortedMilestones(projet.milestones)
        #expect(jalons.map(\.label) == ["Migration AP finalisée",
                                        "Migration Marine — chiffrage à valider",
                                        "Bascule Jenkins → GitLab CI"])
        #expect(jalons.map(\.state) == [.done, .late, .planned])

        let contacts = ProjectCardBuilder.sortedContacts(projet.contacts)
        #expect(contacts.map(\.name) == ["Olivier Freund",
                                         "Claire-Amélie F.-D.",
                                         "Alexis / Jeff"])
        #expect(contacts.first?.role == "partenaire, décideur")
    }

    @Test("L'état d'affichage de la fiche reprend les valeurs de la capture")
    func cardStateMatchesCapture() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = RefonteDemoSeed.seed(in: context)
        let projet = try #require(reunion.project)

        let carte = ProjectCardBuilder.build(project: projet, meetings: [reunion])
        #expect(carte.name == "S/D — Modernisation CI/CD")
        #expect(carte.reference == "P25_110")
        #expect(carte.statusLabel == "À surveiller")
        #expect(carte.budget?.text == "40\u{202F}000\u{00A0}€ / 61\u{202F}000\u{00A0}€")
        #expect(carte.milestones.count == 3)
        // Le jalon Marine est bloqué : c'est le « bloqué » rouge de la capture.
        #expect(carte.milestones[1].trailingText == "bloqué")
        #expect(carte.milestones[0].trailingText == "30 sept.")
        #expect(carte.milestones[2].trailingText == "15 nov.")
        #expect(carte.risks.count == 5)
        #expect(carte.contacts.count == 3)
        #expect(carte.tags.count == 4)
    }

    @Test("Rejouer le semis ne duplique ni les jalons ni les interlocuteurs")
    func projectCardSeedIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = RefonteDemoSeed.seed(in: context)
        _ = RefonteDemoSeed.seed(in: context)

        #expect(try context.fetch(FetchDescriptor<ProjectMilestone>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<ProjectContact>()).count == 3)
    }
}
