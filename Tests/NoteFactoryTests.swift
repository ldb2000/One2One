import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NoteFactory — une note est une réunion avec soi-même")
struct NoteFactoryTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    @Test("Le kind est note et le corps va dans liveNotes")
    func kindAndBody() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Idée du jour")
        context.insert(note)
        #expect(note.kind == .note)
        #expect(note.liveNotes == "Idée du jour")
    }

    @Test("Le projet est rattaché")
    func projectIsLinked() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)
        let note = NoteFactory.make(body: "REX", title: "REX", project: project)
        context.insert(note)
        #expect(note.project?.code == "REFSI")
    }

    @Test("Le collaborateur devient participant, et le lien survit à la sauvegarde")
    func collaboratorBecomesParticipant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        let note = NoteFactory.make(body: "Point de vigilance", collaborator: collab)
        context.insert(note)
        try context.save()

        // Second contexte sur le même conteneur. C'est la seule façon de sortir
        // de la carte d'identité du premier : un `fetch` sur le contexte qui a
        // fait le `save` rend l'instance déjà en mémoire, et l'assertion serait
        // tautologique. Le dépôt ne fait nulle part cette distinction
        // (cf. `Tests/SwiftDataTests.swift`) ; ici elle compte, parce que
        // `NoteFactory` pose la relation AVANT l'insertion.
        let verifier = ModelContext(container)
        let fetchedNotes = try verifier.fetch(FetchDescriptor<Meeting>())
        #expect(fetchedNotes.count == 1)
        #expect(fetchedNotes.first?.participants.map(\.name) == ["Alice"])
        // Côté inverse, relu lui aussi depuis le second contexte.
        let fetchedCollabs = try verifier.fetch(FetchDescriptor<Collaborator>())
        #expect(fetchedCollabs.first?.meetings.count == 1)
    }

    @Test("Sans collaborateur, aucun participant")
    func noCollaboratorMeansNoParticipant() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Note libre")
        context.insert(note)
        #expect(note.participants.isEmpty)
    }

    // MARK: - isDiscardableEmptyNote

    @Test("Une note fraîchement fabriquée est jetable")
    func freshNoteIsDiscardable() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        #expect(NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Un titre ou un corps, même réduit à des espaces autour, la retient")
    func titleOrBodyKeepsIt() throws {
        let context = try makeContext()
        let titled = NoteFactory.make(title: "  Titre  ")
        let bodied = NoteFactory.make(body: "\n Contenu \n")
        context.insert(titled); context.insert(bodied)
        #expect(!NoteFactory.isDiscardableEmptyNote(titled))
        #expect(!NoteFactory.isDiscardableEmptyNote(bodied))
    }

    @Test("Des blancs seuls ne retiennent pas la note")
    func whitespaceOnlyIsStillDiscardable() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "   \n\t ", title: "  ")
        context.insert(note)
        #expect(NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Un thème retient la note, même sans titre ni corps")
    func tagKeepsIt() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        let tag = MeetingTag(name: "Recrutement")
        context.insert(tag)
        note.tags.append(tag)
        try context.save()
        // `MeetingTagEditor` est rendu hors de la garde de kind du chrome :
        // poser un thème est la seule saisie possible sur une note sans écrire
        // une ligne. La supprimer emporterait le lien vers le thème.
        #expect(!NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Un prompt spécifique retient la note")
    func customPromptKeepsIt() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        // Atteint par « ⋯ → Détails de la réunion… » : le TextEditor de
        // `MeetingDetailsBlock` n'est sous aucune garde de kind.
        note.customPrompt = "Insister sur les risques"
        #expect(!NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Un événement calendrier importé retient la note, même sans titre")
    func calendarLinkKeepsIt() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        // « ⋯ → Importer Calendrier » reste actif sur une note (cf.
        // `MeetingMenuActions`). L'import recopie le titre de l'événement,
        // mais un événement sans titre laisserait la note vide en apparence.
        note.calendarEventID = "EVT-123"
        #expect(!NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Une pièce jointe retient la note, même sans titre ni corps")
    func attachmentKeepsIt() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        let attachment = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/doc.pdf"), kind: "pdf")
        attachment.meeting = note
        context.insert(attachment)
        try context.save()
        #expect(!NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Le projet ou le participant posés par la fabrique ne retiennent pas la note")
    func targetAloneDoesNotKeepIt() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let collab = Collaborator(name: "Alice")
        context.insert(project); context.insert(collab)
        let projectNote = NoteFactory.make(project: project)
        let collabNote = NoteFactory.make(collaborator: collab)
        context.insert(projectNote); context.insert(collabNote)
        #expect(NoteFactory.isDiscardableEmptyNote(projectNote))
        #expect(NoteFactory.isDiscardableEmptyNote(collabNote))
    }

    @Test("Une réunion vide qui n'est pas une note n'est jamais jetable")
    func nonNoteIsNeverDiscardable() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "", date: Date())
        meeting.kind = .oneToOne
        context.insert(meeting)
        #expect(!NoteFactory.isDiscardableEmptyNote(meeting))
    }

    // MARK: - Une note n'est pas forcément née note

    /// **Le scénario qui compte.** Le badge de type du fil d'Ariane est un
    /// `Picker` sur `MeetingKind.allCases`, rendu sans garde sur toutes les
    /// réunions ; et les réunions naissent sans titre
    /// (`MeetingsListView.addMeeting`). Une réunion enregistrée, transcrite,
    /// rapportée et jamais renommée, dont on bascule le type sur « Note »,
    /// n'est donc **pas** jetable — sinon la fermeture de l'écran la
    /// supprimerait sans la confirmation que `deleteMeeting` exige.
    @Test("Une réunion transcrite et rapportée, sans titre, convertie en note, n'est pas jetable")
    func convertedRecordedMeetingIsNotDiscardable() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "", date: Date(), notes: "")
        context.insert(meeting)
        meeting.rawTranscript = "Bonjour à tous, on démarre le point."
        meeting.summary = "## Décisions\n- Reporter la mise en production."
        meeting.wavFilePath = "/tmp/reunion.wav"
        try context.save()

        // Le geste réel : l'utilisateur bascule le badge de type sur « Note ».
        meeting.kind = .note

        #expect(!NoteFactory.isDiscardableEmptyNote(meeting))
    }

    /// Chaque champ hérité d'une vraie réunion retient la note **à lui seul**,
    /// tous les autres restant vides. Verrouille l'absence de trou dans la
    /// liste des gardes.
    @Test("Chaque trace d'une vraie réunion retient la note à elle seule")
    func eachLeftoverFieldAloneKeepsIt() throws {
        let context = try makeContext()

        func convertedNote(_ fill: (Meeting) -> Void) -> Meeting {
            let m = Meeting(title: "", date: Date(), notes: "")
            context.insert(m)
            fill(m)
            m.kind = .note
            return m
        }

        let cases: [(String, (Meeting) -> Void)] = [
            ("notes",            { $0.notes = "Compte rendu manuscrit" }),
            ("rawTranscript",    { $0.rawTranscript = "…" }),
            ("mergedTranscript", { $0.mergedTranscript = "…" }),
            ("summary",          { $0.summary = "Rapport" }),
            ("shortSummary",     { $0.shortSummary = "Résumé court" }),
            ("prepNotes",        { $0.prepNotes = "- Préparer le budget" }),
            ("referencedAbsent", { $0.referencedAbsent = "Zied" }),
            ("nextDeadline",     { $0.nextDeadline = "Comité du 12" }),
            ("wavFilePath",      { $0.wavFilePath = "/tmp/a.wav" }),
            ("keyPoints",        { $0.keyPoints = ["Un point clé"] }),
            ("decisions",        { $0.decisions = ["Une décision"] }),
            ("openQuestions",    { $0.openQuestions = ["Une question"] })
        ]
        for (name, fill) in cases {
            #expect(!NoteFactory.isDiscardableEmptyNote(convertedNote(fill)),
                    "\(name) seul devrait retenir la note")
        }
    }

    @Test("Une action ouverte retient la note")
    func taskKeepsIt() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        let task = ActionTask(title: "Relancer le prestataire")
        task.meeting = note
        context.insert(task)
        try context.save()
        // Relation en cascade : supprimer la note emporterait l'action.
        #expect(!NoteFactory.isDiscardableEmptyNote(note))
    }

    // MARK: - Le contenu rattaché sans relation inverse sur Meeting

    /// Le 1:1 manager range son contenu dans quatre références à `Meeting` qui
    /// ne déclarent **aucun tableau inverse** : `ManagerMeetingReport.meeting`,
    /// `ManagerReportItem.sourceMeeting`, `ManagerReportItem.archivedInMeeting`
    /// et `ActionTask.managerMeeting`. Lire les collections de `Meeting` ne les
    /// voit donc pas — il faut les chercher depuis leur propre côté. Une
    /// réunion tenue via l'agenda manager n'a rien dans `summary`,
    /// `rawTranscript`, `tasks` ni `reportRevisions` : sans ces gardes, la
    /// basculer sur « Note » puis fermer l'écran la supprimerait avec son CR.
    @Test("Chaque rattachement du 1:1 manager retient la note à lui seul")
    func managerAttachmentAloneKeepsIt() throws {
        let context = try makeContext()

        func convertedNote(_ attach: (Meeting) -> Void) throws -> Meeting {
            let m = Meeting(title: "", date: Date(), notes: "")
            context.insert(m)
            attach(m)
            m.kind = .note
            try context.save()
            return m
        }

        let cases: [(String, (Meeting) -> Void)] = [
            ("ManagerMeetingReport.meeting", { m in
                let report = ManagerMeetingReport(meeting: m)
                report.generatedSummary = "## Points\n- Budget à arbitrer"
                context.insert(report)
            }),
            ("ManagerReportItem.sourceMeeting", { m in
                let item = ManagerReportItem(rawSnippet: "Le budget dérape",
                                             sourceField: "manual",
                                             sourceRangeStart: 0,
                                             sourceRangeLength: 0,
                                             sourceMeeting: m)
                context.insert(item)
            }),
            ("ManagerReportItem.archivedInMeeting", { m in
                let item = ManagerReportItem(manualSnippet: "Point clos", category: "Information")
                item.archivedInMeeting = m
                context.insert(item)
            }),
            ("ActionTask.managerMeeting", { m in
                let task = ActionTask(title: "Relancer la DSI")
                task.fromManager = true
                task.managerMeeting = m
                context.insert(task)
            })
        ]

        for (name, attach) in cases {
            let note = try convertedNote(attach)
            #expect(!NoteFactory.isDiscardableEmptyNote(note),
                    "\(name) seul devrait retenir la note")
        }
    }

    /// Sans contexte, le prédicat ne peut pas chercher les rattachements sans
    /// inverse : il ne peut donc pas conclure que la note ne porte rien.
    /// L'asymétrie du risque commande alors de la retenir.
    @Test("Une note hors de tout contexte n'est jamais jetable")
    func noteWithoutContextIsNotDiscardable() throws {
        let orphan = NoteFactory.make()
        #expect(!NoteFactory.isDiscardableEmptyNote(orphan))
    }
}
