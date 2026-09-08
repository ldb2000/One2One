import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// **La couture des lots 2 et 3** : une intention posée par une surface amont
/// (la ligne `/action` du composeur de notes, le bouton `＋ Action` d'une
/// phrase de transcription) traverse `MeetingScreenModel.pendingActionDraft` et
/// ressort en `ActionTask` sous le `⌘⏎` du composeur du rail, **sa source
/// intacte**.
///
/// Le lot 2 posait l'intention sans que personne ne la consomme, le lot 3
/// consommait une intention que personne ne posait — chacun vert de son côté.
/// Cette suite est écrite pour tomber si les deux moitiés se désalignent :
/// elle ne monte **aucune vue** et n'appelle que ce que les vues appellent —
/// `NoteCommandParser`, `ActionFromPhrase`, `MeetingScreenModel`,
/// `ActionComposerService`, `ActionsRailGrouping`.
@Suite("Couture /action → rail")
@MainActor
struct ActionSeamIntegrationTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeScreen() -> MeetingScreenModel {
        let suite = "ActionSeamIntegrationTests.\(UUID().uuidString)"
        return MeetingScreenModel(defaults: UserDefaults(suiteName: suite)!)
    }

    /// La réunion de la capture `1a-cockpit.png`, son segment `04:12` et son
    /// locuteur.
    private func fixture(in context: ModelContext)
    -> (meeting: Meeting, segment: TranscriptSegment, speaker: Collaborator) {
        let reunion = Meeting(title: "[P25_110] Partage statut final", date: Date(), notes: "")
        reunion.durationSeconds = 1_404
        context.insert(reunion)

        let locuteur = Collaborator(name: "Laurent Deberti", role: "Manager")
        context.insert(locuteur)
        reunion.participants.append(locuteur)

        let segment = TranscriptSegment(
            orderIndex: 1,
            startSeconds: 252,
            endSeconds: 275,
            text: "il faut vérifier l'état des comptes GitLab.",
            speakerID: 1
        )
        context.insert(segment)
        segment.meeting = reunion
        segment.speaker = locuteur
        return (reunion, segment, locuteur)
    }

    // MARK: - Chemin 1 — `/action` dans le composeur de notes

    @Test("`/action` pose une source `note` horodatée, le rail crée l'action avec")
    func actionDepuisUneLigneDeNote() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let screen = makeScreen()
        screen.attach(meetingID: f.meeting.ensuredStableID)
        screen.playhead.duration = Double(f.meeting.durationSeconds)
        screen.playhead.seek(to: 252)

        // 1. La frappe, telle que `NoteComposer.valider()` la traite.
        screen.pendingNoteText = "/action Vérifier les comptes GitLab"
        let parsed = NoteCommandParser.parse(screen.pendingNoteText)
        #expect(parsed.opensActionComposer)
        #expect(parsed.text == "Vérifier les comptes GitLab")

        screen.requestAction(from: ActionFromPhrase.draft(phrase: parsed.text,
                                                          kind: .note,
                                                          stableID: f.meeting.ensuredStableID,
                                                          t: screen.playhead.t))
        screen.pendingNoteText = ""

        // 2. L'intention est posée, avec sa source, et le composeur du rail est
        //    prérempli.
        let brouillon = try #require(screen.pendingActionDraft)
        #expect(brouillon.title == "Vérifier les comptes GitLab")
        #expect(brouillon.sourceRef?.kind == .note)
        #expect(brouillon.sourceRef?.stableID == f.meeting.ensuredStableID)
        #expect(brouillon.sourceRef?.t == 252)
        #expect(screen.newTaskTitle == "Vérifier les comptes GitLab")
        // `/action` n'écrit aucune note : la ligne devient une action, pas les
        // deux.
        #expect(f.meeting.timedNotes.isEmpty)
        #expect(f.meeting.tasks.isEmpty)

        // 3. `⌘⏎` dans le composeur du rail. Sans responsable suggéré (une note
        //    n'a pas de locuteur), la pilule du composeur décide — ici « à
        //    assigner », comme le fait un clic sur la pilule Destinataire.
        screen.newTaskAudience = .collaborateur
        screen.selectedCollaborator = nil
        let action = try #require(ActionComposerService.creer(from: screen,
                                                             meeting: f.meeting,
                                                             in: context))

        #expect(action.title == "Vérifier les comptes GitLab")
        #expect(action.sourceRef?.kind == .note)
        #expect(action.sourceRef?.stableID == f.meeting.ensuredStableID)
        #expect(action.sourceRef?.t == 252)
        #expect(f.meeting.tasks.count == 1, "une seule action pour un seul geste")

        // 4. Le composeur est vidé et l'intention consommée.
        #expect(screen.newTaskTitle.isEmpty)
        #expect(screen.pendingActionDraft == nil)

        // 5. Le rail la montre en tête d'À ASSIGNER.
        let groupes = ActionsRailGrouping.groupes(for: f.meeting.tasks)
        let aAssigner = try #require(groupes.first { $0.identite == .aAssigner })
        #expect(aAssigner.actions.first === action)
    }

    // MARK: - Chemin 2 — `＋ Action` sur une phrase de transcription

    @Test("`＋ Action` sur une phrase suggère le locuteur et garde la source du segment")
    func actionDepuisUnSegment() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let screen = makeScreen()
        screen.attach(meetingID: f.meeting.ensuredStableID)

        // Une action déjà là, pour vérifier que la neuve passe devant.
        let existante = ActionTask(title: "Action déjà là")
        existante.sortOrder = 0
        existante.destinataire = .collaborateur
        existante.collaborator = f.speaker
        context.insert(existante)
        existante.meeting = f.meeting

        // 1. Le clic, tel que `TranscriptColumn.creerAction` le traite : il
        //    pose l'intention et ne crée rien.
        screen.requestAction(from: ActionFromPhrase.draft(from: f.segment))
        #expect(f.meeting.tasks.count == 1, "le clic ne crée pas l'action, il la propose")

        let brouillon = try #require(screen.pendingActionDraft)
        #expect(brouillon.title == "Vérifier l'état des comptes GitLab")
        #expect(brouillon.sourceRef?.kind == .transcript)
        #expect(brouillon.sourceRef?.stableID == f.segment.ensuredStableID)
        #expect(brouillon.sourceRef?.t == 252)
        #expect(brouillon.suggestedOwner === f.speaker)

        // 2. Titre **et** responsable suggéré sont lisibles dans le composeur
        //    avant validation : une suggestion invisible ne se refuse pas.
        #expect(screen.newTaskTitle == "Vérifier l'état des comptes GitLab")
        #expect(screen.newTaskAudience == .collaborateur)
        #expect(screen.selectedCollaborator === f.speaker)

        // 3. `⌘⏎`.
        let action = try #require(ActionComposerService.creer(from: screen,
                                                             meeting: f.meeting,
                                                             in: context))
        #expect(action.title == "Vérifier l'état des comptes GitLab")
        #expect(action.collaborator === f.speaker)
        #expect(action.sourceRef?.kind == .transcript)
        #expect(action.sourceRef?.stableID == f.segment.ensuredStableID)
        #expect(action.sourceRef?.t == 252)
        #expect(f.meeting.tasks.count == 2, "une seule action de plus, pas deux")
        #expect(screen.newTaskTitle.isEmpty)
        #expect(screen.pendingActionDraft == nil)

        // 4. En tête du groupe de son responsable (`Déléguées`), devant
        //    l'action qui y était déjà.
        #expect(action.sortOrder < existante.sortOrder)
        let groupes = ActionsRailGrouping.groupes(for: f.meeting.tasks)
        let groupe = try #require(groupes.first { $0.identite == .deleguees })
        #expect(groupe.actions.first === action)
    }

    // MARK: - Le titre saisi l'emporte, la source survit

    @Test("Reformuler le titre proposé ne coupe pas le lien vers la phrase")
    func reformulerGardeLaSource() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let screen = makeScreen()
        screen.attach(meetingID: f.meeting.ensuredStableID)

        screen.requestAction(from: ActionFromPhrase.draft(from: f.segment))
        screen.newTaskTitle = "Réactiver les comptes GitLab du partenaire"

        let action = try #require(ActionComposerService.creer(from: screen,
                                                             meeting: f.meeting,
                                                             in: context))
        #expect(action.title == "Réactiver les comptes GitLab du partenaire")
        #expect(action.sourceRef?.stableID == f.segment.ensuredStableID)
        #expect(action.sourceRef?.t == 252)
    }

    // MARK: - Une seule fabrique d'action

    @Test("Aucune surface amont ne crée d'action : seul le composeur du rail le fait")
    func uneSeuleFabrique() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // La double création du geste `＋ Action` (le service *et* le composeur)
        // ne se voit dans aucun état final : elle produit deux actions
        // plausibles. Le test lit donc les sources amont.
        let amont = [
            "OneToOne/Views/Meeting/Spaces/Transcript/TranscriptColumn.swift",
            "OneToOne/Views/Meeting/Spaces/Notes/NoteComposer.swift",
            "OneToOne/Services/Meeting/ActionFromPhrase.swift"
        ]
        for chemin in amont {
            let texte = try String(contentsOf: racine.appendingPathComponent(chemin),
                                   encoding: .utf8)
            #expect(!texte.contains("ActionTask("),
                    "\(chemin) fabrique une ActionTask : la création appartient à ActionComposerService")
        }

        // `MeetingView` garde une fabrique d'action — celle du rapport IA, qui
        // n'a rien à voir avec la couture (`report.actions`). Ce qui ne doit
        // plus y être, c'est le composeur : `addTask` a déménagé dans
        // `ActionComposerService`.
        let vue = try String(
            contentsOf: racine.appendingPathComponent("OneToOne/Views/MeetingView.swift"),
            encoding: .utf8
        )
        #expect(!vue.contains("addTask"), "MeetingView garde un reliquat d'addTask")
    }
}
