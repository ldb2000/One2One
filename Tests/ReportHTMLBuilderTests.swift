import XCTest
import SwiftData
@testable import OneToOne

final class ReportHTMLBuilderTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_eyebrowContainsKindAndConfidential() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Test", date: Date())
        meeting.summary = "Contenu de test."
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("CONFIDENTIEL"))
        XCTAssertTrue(html.contains("Test"))
    }

    @MainActor
    func test_titleEscaped() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Titre <script>", date: Date())
        meeting.summary = "x"
        ctx.insert(meeting)
        try ctx.save()
        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("<h1>Titre <script>"))
        XCTAssertTrue(html.contains("Titre &lt;script&gt;"))
    }

    @MainActor
    func test_metaParticipants() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)
        let meeting = Meeting(title: "T", date: Date())
        meeting.participants = [alice, bob]
        meeting.summary = "x"
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Alice DUPONT"))
        XCTAssertTrue(html.contains("Bob MARTIN"))
    }

    @MainActor
    func test_injectsDecisionsTable() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "## Contexte\n\nLa séance vise…"
        meeting.decisions = ["Catalogue par exception", "Tri amont"]
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Relevé de décisions"))
        XCTAssertTrue(html.contains("Catalogue par exception"))
        XCTAssertTrue(html.contains("Tri amont"))
        XCTAssertTrue(html.contains("D1"))
        XCTAssertTrue(html.contains("D2"))
    }

    @MainActor
    func test_injectsActionsFromTasks() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "x"
        ctx.insert(meeting)
        let task = ActionTask(title: "Préparer slides", dueDate: nil)
        task.collaborator = alice
        task.meeting = meeting
        ctx.insert(task)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Plan d'actions"))
        XCTAssertTrue(html.contains("Préparer slides"))
        XCTAssertTrue(html.contains("Alice DUPONT"))
        XCTAssertTrue(html.contains("A1"))
    }

    @MainActor
    func test_noInjectionWhenAllEmpty() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "## Section unique\n\nContenu."
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("Relevé de décisions"))
        XCTAssertFalse(html.contains("Plan d'actions"))
    }

    @MainActor
    func test_dedupeH2_remplaceDecisionsLLM() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = """
        ## Contexte
        Texte.

        ## Décisions
        Le LLM a écrit du texte ici qui doit être remplacé.
        """
        meeting.decisions = ["Canonique 1"]
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Canonique 1"))
        XCTAssertFalse(html.contains("Le LLM a écrit du texte ici qui doit être remplacé."))
    }

    @MainActor
    func test_oneToOneActionsTable_singleProject_noProjectColumn() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        ctx.insert(proj)
        let meeting = Meeting(title: "1:1 Alice", date: Date())
        meeting.kindRaw = MeetingKind.oneToOne.rawValue
        meeting.participants = [alice]
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche 1", dueDate: nil)
        t1.meeting = meeting
        t1.project = proj
        ctx.insert(t1)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("<th>Action</th>"))
        XCTAssertFalse(html.contains("<th>Projet</th>"),
                       "Single project → colonne Projet absente")
    }

    @MainActor
    func test_oneToOneActionsTable_multipleProjects_includesProjectColumn() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let p1 = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        let p2 = Project(code: "P2", name: "Projet 2", domain: "Y", phase: "Build")
        ctx.insert(p1); ctx.insert(p2)
        let meeting = Meeting(title: "1:1 Alice", date: Date())
        meeting.kindRaw = MeetingKind.oneToOne.rawValue
        meeting.participants = [alice]
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
        t1.meeting = meeting
        t1.project = p1
        ctx.insert(t1)
        let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
        t2.meeting = meeting
        t2.project = p2
        ctx.insert(t2)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("<th>Projet</th>"),
                      "Multi projets en 1:1 → colonne Projet présente")
        XCTAssertTrue(html.contains("P1"))
        XCTAssertTrue(html.contains("P2"))
    }

    @MainActor
    func test_nonOneToOneActionsTable_noProjectColumn() throws {
        let ctx = try makeContext()
        let p1 = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        let p2 = Project(code: "P2", name: "Projet 2", domain: "Y", phase: "Build")
        ctx.insert(p1); ctx.insert(p2)
        let meeting = Meeting(title: "COPIL", date: Date())
        meeting.kindRaw = MeetingKind.project.rawValue
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
        t1.meeting = meeting; t1.project = p1
        ctx.insert(t1)
        let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
        t2.meeting = meeting; t2.project = p2
        ctx.insert(t2)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("<th>Projet</th>"),
                       "Non-1:1 → pas de colonne Projet même si multi projets")
    }

    @MainActor
    func test_workMeetingMultipleProjects_includesProjectColumn() throws {
        let ctx = try makeContext()
        let p1 = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        let p2 = Project(code: "P2", name: "Projet 2", domain: "Y", phase: "Build")
        ctx.insert(p1); ctx.insert(p2)
        let meeting = Meeting(title: "Archi équipe", date: Date())
        meeting.kindRaw = MeetingKind.work.rawValue
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
        t1.meeting = meeting
        t1.project = p1
        ctx.insert(t1)
        let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
        t2.meeting = meeting
        t2.project = p2
        ctx.insert(t2)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("<th>Projet</th>"),
                      ".work + multi-projets → colonne Projet présente")
    }

    // MARK: - Lot 15 — annexes et chaîne de citation

    /// Critère d'acceptation n° 3 du chantier 3, moitié rapport : la pièce
    /// épinglée est citée avec son timecode, **sans aucune intervention du
    /// modèle** — ici, `summary` ne la mentionne pas.
    @MainActor
    func test_lot15_pieceEpingleeCiteeAvecSonTimecode() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue Marine", date: Date())
        meeting.summary = "## Contexte\n\nLa séance a passé le chiffrage en revue."
        ctx.insert(meeting)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage_Marine_v3.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = meeting
        ctx.insert(piece)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        XCTAssertTrue(html.contains(ReportOptionalBlocks.pinnedTitle))
        XCTAssertTrue(html.contains("Chiffrage_Marine_v3.xlsx"))
        XCTAssertTrue(html.contains("04:12"))
        XCTAssertTrue(html.contains(
            "onetoone://meeting/\(meeting.ensuredStableID.uuidString)?t=252"))
    }

    @MainActor
    func test_lot15_caseDecochee_pasDeBlocDePieces() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.summary = "Contenu."
        var options = meeting.reportAttachmentOptions
        options.attachPinned = false
        meeting.reportAttachmentOptions = options
        ctx.insert(meeting)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = meeting
        ctx.insert(piece)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        XCTAssertFalse(html.contains(ReportOptionalBlocks.pinnedTitle))
        XCTAssertFalse(html.contains("Chiffrage.xlsx"))
    }

    @MainActor
    func test_lot15_exportOutlookGardeLeTimecodeEnTexte() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.summary = "Contenu."
        ctx.insert(meeting)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Annexe.pdf"))
        piece.pinnedAtT = 252
        piece.meeting = meeting
        ctx.insert(piece)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false, mode: .outlook)
        XCTAssertFalse(html.contains("onetoone://"))
        XCTAssertTrue(html.contains("04:12"))
    }

    /// Faux positif : un horaire écrit par le modèle dans le corps du rapport
    /// n'est pas une position sur l'axe temps.
    @MainActor
    func test_lot15_horaireDansLeCorpsResteDuTexte() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.summary = "Le point est reporté à 14:30, après la démo."
        ctx.insert(meeting)
        try ctx.save()
        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        XCTAssertTrue(html.contains("14:30"))
        XCTAssertFalse(html.contains("onetoone://"))
    }

    /// Critère d'acceptation n° 5 du chantier 6, côté rapport.
    @MainActor
    func test_lot15_planchesDansLOrdreDuTemps() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Atelier", date: Date())
        meeting.summary = "Contenu."
        ctx.insert(meeting)
        for (index, couple) in [("Première", 120.0), ("Deuxième", 450.0),
                                ("Troisième", 900.0)].enumerated().reversed() {
            let planche = Board(index: index, title: couple.0, mode: .sketch, t: couple.1)
            planche.meeting = meeting
            ctx.insert(planche)
        }
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        let positions = ["Première", "Deuxième", "Troisième"]
            .compactMap { html.range(of: $0)?.lowerBound }
        XCTAssertEqual(positions.count, 3)
        XCTAssertEqual(positions, positions.sorted())
    }

    @MainActor
    func test_lot15_noteHorodateeEstUnLienVersElleMeme() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.summary = "Contenu."
        ctx.insert(meeting)
        let note = MeetingNote(t: 120, text: "Le chiffrage dérape", visibility: .shared)
        note.meeting = meeting
        ctx.insert(note)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        XCTAssertTrue(html.contains("?t=120&note=\(note.ensuredStableID.uuidString)"))
    }
}
