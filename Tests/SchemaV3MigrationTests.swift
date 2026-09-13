import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Migration V2 → V3 : le lot 0B n'ajoute que des **tables** et des colonnes à
/// valeur par défaut, donc SwiftData applique une migration légère et
/// `OneToOneMigrationPlan.stages` reste vide. Ce test le prouve sur un store
/// SQLite réel (pas en mémoire : c'est le passage sur disque qui migre).
///
/// ⚠️ **Limite connue, déjà documentée dans `SchemaVersions.swift`** : les
/// types Swift sont partagés entre `SchemaV1/V2/V3` (aucun snapshot *nested*
/// n'a jamais été écrit dans ce dépôt), donc ouvrir le store avec `SchemaV2`
/// crée un fichier qui porte **déjà** les colonnes de V3. Ce test vérifie donc
/// ce qui reste vérifiable sans réécrire les cinq modèles en snapshots : qu'un
/// store écrit puis rouvert avec `CurrentSchema` + le plan de migration
/// conserve ses lignes et que les nouveaux champs portent bien leur défaut sur
/// des lignes créées avant eux. La migration d'un store de production
/// antérieur se vérifie hors test, sur une copie (cf. `STATUS.md`).
@Suite("Schéma V3 — migration légère sans perte")
@MainActor
struct SchemaV3MigrationTests {

    private func makeTemporaryStoreURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-schemav3-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.sqlite")
    }

    @Test("Le schéma courant est V3 et déclare les neuf nouvelles tables")
    func schemaCourantEstV3() {
        #expect(CurrentSchema.versionIdentifier == Schema.Version(3, 0, 0))
        let noms = Set(Schema(CurrentSchema.models).entities.map(\.name))
        for attendu in ["MeetingNote", "Board", "ProjectMilestone", "ProjectContact",
                        "OneOnOneThread", "Commitment", "OneOnOneAgendaItem",
                        "MoodEntry", "OneOnOneObjective"] {
            #expect(noms.contains(attendu), "table absente du schéma : \(attendu)")
        }
        // Les tables de V2 restent là : une migration légère n'en retire aucune.
        #expect(Set(SchemaV2.models.map { "\($0)" })
            .isSubset(of: Set(CurrentSchema.models.map { "\($0)" })))
        #expect(OneToOneMigrationPlan.schemas.count == 3)
        #expect(OneToOneMigrationPlan.stages.isEmpty)
        // La refonte des projets n'ajoute aucun modèle : `PortfolioSavedView`
        // est une structure `Codable` rangée dans une colonne JSON
        // d'`AppSettings` (D4), pas un `@Model`.
        #expect(!Set(Schema(CurrentSchema.models).entities.map(\.name))
            .contains("PortfolioSavedView"))
    }

    @Test("Une réunion, une action et une pièce jointe traversent la réouverture en V3")
    func donneesConserveesEtDefautsPoses() throws {
        let url = makeTemporaryStoreURL()
        let titre = "COPIL P25_110"
        let meetingID = UUID()

        // 1. Store écrit avec la version antérieure, sans plan de migration.
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV2.self),
                configurations: [ModelConfiguration(url: url)]
            )
            let context = ModelContext(container)
            let meeting = Meeting(title: titre, date: Date(timeIntervalSince1970: 1_700_000_000))
            meeting.stableID = meetingID
            meeting.liveNotes = "Point budget à revoir"
            context.insert(meeting)

            let task = ActionTask(title: "Relancer l'éditeur")
            task.meeting = meeting
            context.insert(task)

            let attachment = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/plaquette.pdf"))
            attachment.meeting = meeting
            context.insert(attachment)

            try context.save()
        }

        // 2. Réouverture avec le schéma courant et le plan de migration.
        let container = try ModelContainer(
            for: Schema(versionedSchema: CurrentSchema.self),
            migrationPlan: OneToOneMigrationPlan.self,
            configurations: [ModelConfiguration(url: url)]
        )
        let context = ModelContext(container)

        let reunions = try context.fetch(FetchDescriptor<Meeting>())
        #expect(reunions.count == 1)
        let reunion = try #require(reunions.first)
        #expect(reunion.title == titre)
        #expect(reunion.stableID == meetingID)
        #expect(reunion.liveNotes == "Point budget à revoir")
        #expect(reunion.tasks.count == 1)
        #expect(reunion.attachments.count == 1)

        // Nouveaux champs de `Meeting` : défauts sur une ligne créée avant eux.
        #expect(reunion.recordingStartedAt == nil)
        #expect(reunion.notesMigrated == false)
        #expect(reunion.timedNotes.isEmpty)
        #expect(reunion.boards.isEmpty)

        // Nouveaux champs de `ActionTask`.
        let action = try #require(reunion.tasks.first)
        #expect(action.title == "Relancer l'éditeur")
        #expect(action.priority == .normal)
        #expect(action.status == .open)
        #expect(action.effortMinutes == nil)
        #expect(action.deferralCount == 0)
        #expect(action.carriedFromMeeting == nil)
        #expect(action.sourceRef == nil)

        // Nouveaux champs de `MeetingAttachment`.
        let piece = try #require(reunion.attachments.first)
        #expect(piece.scope == .meeting)
        #expect(piece.mimeType.isEmpty)
        #expect(piece.byteCount == 0)
        #expect(piece.addedByName.isEmpty)
        #expect(piece.pinnedAtT == nil)
        #expect(piece.citationCount == 0)

        // 3. Les nouvelles tables sont écrivables dans le store migré.
        let note = MeetingNote(t: 252, text: "Décision : on garde le périmètre", kind: .decision)
        note.meeting = reunion
        context.insert(note)
        try context.save()
        #expect(reunion.timedNotes.count == 1)

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Les nouveaux champs de SlideCapture et Project portent leur défaut")
    func defautsSlideEtProjet() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let capture = SlideCapture(index: 0, capturedAt: Date(), imagePath: "/tmp/a.png")
        context.insert(capture)
        let projet = Project(code: "P25_110", name: "Refonte", domain: "SI", phase: "Design")
        context.insert(projet)
        try context.save()

        #expect(capture.t == nil)
        #expect(capture.source == .screen)
        #expect(capture.trigger == .manual)
        #expect(projet.scopeText.isEmpty)
        #expect(projet.tags.isEmpty)
        // Lot 0 de la refonte des projets (D4) : `pinned` est une colonne à
        // valeur par défaut, donc **pas** de `SchemaV4`. Le défaut est ici pour
        // qu'un futur `SchemaV4` ne passe pas inaperçu.
        #expect(projet.pinned == false)
        // Lot 4 (D9) : même motif — `scopeUpdatedAt` est un champ optionnel,
        // donc toujours pas de `SchemaV4`.
        #expect(projet.scopeUpdatedAt == nil)

        projet.tags = ["migration", "budget"]
        #expect(projet.tags == ["migration", "budget"])
    }

    /// Le fil 1:1 possède ses quatre collections : la suppression du fil doit
    /// emporter engagements, sujets, humeurs et objectifs, sinon lot 10
    /// laisserait des orphelins que rien ne ramasse.
    @Test("Supprimer un fil 1:1 emporte ses engagements, sujets, humeurs et objectifs")
    func cascadeDuFil() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let collab = Collaborator(name: "Awa Diallo", role: "Architecte")
        context.insert(collab)
        let fil = OneOnOneThread(collaborator: collab, myRole: .manager, cadenceDays: 14)
        context.insert(fil)

        let engagement = Commitment(text: "Ouvrir le poste CI/CD", ownerSide: .manager)
        engagement.thread = fil
        context.insert(engagement)
        let sujet = OneOnOneAgendaItem(text: "Charge de travail", addedBySide: .collaborator, order: 0)
        sujet.thread = fil
        context.insert(sujet)
        let humeur = MoodEntry(value: 4)
        humeur.thread = fil
        context.insert(humeur)
        let objectif = OneOnOneObjective(label: "Certification", progress: 40, order: 0)
        objectif.thread = fil
        context.insert(objectif)
        try context.save()

        #expect(fil.commitments.count == 1)
        #expect(fil.agendaItems.count == 1)
        #expect(fil.moodEntries.count == 1)
        #expect(fil.objectives.count == 1)

        context.delete(fil)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Commitment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<OneOnOneAgendaItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MoodEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<OneOnOneObjective>()).isEmpty)
    }

    /// `priorityRaw` et `statusRaw` sont des **miroirs requêtables** :
    /// `isUrgent`/`isCompleted` restent la source de vérité, sinon deux
    /// compteurs d'actions urgentes finiraient par ne plus dire la même chose.
    @Test("Priorité et statut d'action restent cohérents avec isUrgent / isCompleted")
    func coherenceDesMiroirsAction() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let action = ActionTask(title: "Cadrer le lot 1")
        context.insert(action)

        action.priority = .urgent
        #expect(action.isUrgent)
        #expect(action.priorityRaw == "urgent")
        action.isUrgent = false
        #expect(action.priority == .normal)

        action.status = .done
        #expect(action.isCompleted)
        action.isCompleted = false
        #expect(action.status == .open)
        action.status = .dropped
        #expect(!action.isCompleted)
        #expect(action.status == .dropped)
        action.isCompleted = true
        #expect(action.status == .done, "une action cochée est terminée, pas abandonnée")
    }

    @Test("Une planche et un jalon se rattachent à leur parent en cascade")
    func cascadePlanchesEtJalons() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let meeting = Meeting(title: "Atelier flux")
        meeting.kind = .workshop
        context.insert(meeting)
        let planche = Board(index: 0, title: "Flux de commande", mode: .diagram, t: 12)
        planche.meeting = meeting
        context.insert(planche)

        let projet = Project(code: "P25_111", name: "Socle", domain: "SI", phase: "Build")
        context.insert(projet)
        let jalon = ProjectMilestone(label: "Recette", dueAt: nil, order: 0)
        jalon.project = projet
        context.insert(jalon)
        let contact = ProjectContact(name: "Nicolas H.", role: "Sponsor", order: 0)
        contact.project = projet
        context.insert(contact)
        try context.save()

        #expect(meeting.boards.count == 1)
        #expect(projet.milestones.count == 1)
        #expect(projet.contacts.count == 1)
        #expect(jalon.state == .planned)

        context.delete(meeting)
        context.delete(projet)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Board>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProjectMilestone>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProjectContact>()).isEmpty)
    }
}
