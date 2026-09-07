import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le composeur du pied de rail (spec §2.5) : « champ + pilules par défaut
/// (`Moi`, `Demain`, `!`, durée). `⌘⏎` crée et vide le champ sans perdre le
/// focus. »
///
/// La création est un service pur de la vue : c'est ce qui rend vérifiable le
/// « sans perdre le focus » — un service qui ne connaît pas le focus ne peut
/// pas le prendre, et la vue n'a plus qu'à ne jamais remettre son
/// `@FocusState` à `false` (garde dans `ActionsRailNoModalTests`).
@Suite("Composeur d'action du rail")
@MainActor
struct ActionComposerServiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeScreen() -> MeetingScreenModel {
        let suite = "ActionComposerServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = MeetingScreenModel(defaults: defaults)
        model.attach(meetingID: UUID())
        return model
    }

    @Test("Un titre vide ne crée rien")
    func blankTitleCreatesNothing() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let screen = makeScreen()
        screen.newTaskTitle = "   "

        #expect(ActionComposerService.creer(from: screen, meeting: reunion, in: context) == nil)
        #expect(reunion.tasks.isEmpty)
    }

    @Test("La création vide le titre mais garde le destinataire et le collaborateur")
    func creationKeepsAudience() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let porteur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(porteur)

        let screen = makeScreen()
        screen.newTaskTitle = "Chiffrer la fin de migration Marine"
        screen.newTaskAudience = .collaborateur
        screen.selectedCollaborator = porteur
        screen.newTaskUrgent = true

        let creee = ActionComposerService.creer(from: screen, meeting: reunion, in: context)
        #expect(creee?.title == "Chiffrer la fin de migration Marine")
        #expect(creee?.collaborator === porteur)
        #expect(creee?.destinataire == .collaborateur)
        #expect(creee?.isUrgent == true)
        #expect(creee?.priority == .urgent)
        #expect(creee?.meeting?.persistentModelID == reunion.persistentModelID)

        // Le champ est vide, prêt pour la ligne suivante — et les réglages
        // restent : on saisit rarement une action isolée.
        #expect(screen.newTaskTitle.isEmpty)
        #expect(screen.newTaskAudience == .collaborateur)
        #expect(screen.selectedCollaborator === porteur)
        #expect(screen.newTaskUrgent == false)
    }

    @Test("Le titre est nettoyé de ses blancs de bord")
    func titleIsTrimmed() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let screen = makeScreen()
        screen.newTaskTitle = "  Relancer Alexis  "
        #expect(ActionComposerService.creer(from: screen, meeting: reunion,
                                            in: context)?.title == "Relancer Alexis")
    }

    @Test("L'action neuve passe en tête de son groupe")
    func newActionSortsFirst() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        for (index, titre) in ["Première", "Deuxième"].enumerated() {
            let t = ActionTask(title: titre)
            t.sortOrder = index
            t.destinataire = .moi
            context.insert(t)
            t.meeting = reunion
        }

        let screen = makeScreen()
        screen.newTaskTitle = "Neuve"
        screen.newTaskAudience = .moi
        let creee = ActionComposerService.creer(from: screen, meeting: reunion, in: context)

        #expect(creee?.sortOrder == -1)
        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks)
        #expect(groupes[0].actions.first?.title == "Neuve")
    }

    @Test("Le plancher de sortOrder descend sous le minimum, 0 sur une liste vide")
    func sortOrderFloor() throws {
        let context = try makeContext()
        let a = ActionTask(title: "A"); a.sortOrder = 4
        let b = ActionTask(title: "B"); b.sortOrder = -3
        context.insert(a); context.insert(b)
        #expect(ActionComposerService.plancherSortOrder([]) == 0)
        #expect(ActionComposerService.plancherSortOrder([a, b]) == -4)
    }

    @Test("L'échéance et la charge du brouillon sont appliquées")
    func dueDateAndEffortApplied() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let demain = Date().addingTimeInterval(86_400)

        let screen = makeScreen()
        screen.newTaskTitle = "Vérifier l'état des comptes GitLab"
        screen.showNewTaskDueDate = true
        screen.newTaskDueDate = demain
        screen.newTaskEffortMinutes = 120

        let creee = ActionComposerService.creer(from: screen, meeting: reunion, in: context)
        #expect(creee?.dueDate == demain)
        #expect(creee?.effortMinutes == 120)
        // Les pilules restent armées : ce sont les défauts du composeur
        // (« Moi · Demain · 30min » de la capture), pas des propriétés d'une
        // action donnée. Seule l'urgence retombe, parce qu'un `!` oublié
        // rendrait urgente toute la série suivante.
        #expect(screen.newTaskEffortMinutes == 120)
        #expect(screen.showNewTaskDueDate)
        #expect(screen.newTaskDueDate == demain)
    }

    @Test("Le brouillon posé par la transcription est consommé puis effacé")
    func pendingDraftIsConsumed() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let yann = Collaborator(name: "Yann Ferré", role: "")
        context.insert(yann)
        let ref = SourceRef(kind: .transcript, stableID: UUID(), t: 252)

        let screen = makeScreen()
        // Le champ est vide : c'est le brouillon qui fournit le titre.
        screen.pendingActionDraft = ActionDraft(title: "Vérifier l'état des comptes GitLab",
                                                sourceRef: ref,
                                                suggestedOwner: yann)

        let creee = ActionComposerService.creer(from: screen, meeting: reunion, in: context)
        #expect(creee?.title == "Vérifier l'état des comptes GitLab")
        #expect(creee?.sourceRef == ref)
        #expect(creee?.collaborator === yann)
        #expect(creee?.destinataire == .collaborateur)
        // Consommé : un second `⌘⏎` ne recrée pas la même action.
        #expect(screen.pendingActionDraft == nil)
        #expect(ActionComposerService.creer(from: screen, meeting: reunion, in: context) == nil)
        #expect(reunion.tasks.count == 1)
    }

    @Test("Le titre saisi l'emporte sur celui du brouillon en attente")
    func typedTitleWinsOverDraft() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let screen = makeScreen()
        screen.pendingActionDraft = ActionDraft(title: "Titre proposé",
                                                sourceRef: SourceRef(kind: .transcript,
                                                                     stableID: UUID(), t: 10))
        screen.newTaskTitle = "Titre récrit à la main"

        let creee = ActionComposerService.creer(from: screen, meeting: reunion, in: context)
        #expect(creee?.title == "Titre récrit à la main")
        // La chaîne de citation survit à la réécriture du titre : c'est elle
        // qui ramène à la phrase, et l'utilisateur n'a fait que reformuler.
        #expect(creee?.sourceRef?.t == 10)
    }

    @Test("L'action neuve hérite du projet de la réunion")
    func projectIsInherited() throws {
        let context = try makeContext()
        let projet = Project(code: "P25_110", name: "S/D — Modernisation CI/CD",
                             domain: "S/D", sponsor: "", phase: "", status: "Yellow")
        context.insert(projet)
        let reunion = Meeting(title: "COPIL", date: .now)
        reunion.project = projet
        context.insert(reunion)

        let screen = makeScreen()
        screen.newTaskTitle = "Action de projet"
        let creee = ActionComposerService.creer(from: screen, meeting: reunion, in: context)
        #expect(creee?.project?.persistentModelID == projet.persistentModelID)
    }
}
