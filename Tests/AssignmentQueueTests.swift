import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La file d'assignation du bandeau `EN ATTENTE` (spec §2.6 : « ouvre une file
/// d'assignation en 3 clics (responsable → échéance → suivante) »).
///
/// « En 3 clics » est une affirmation sur un nombre de gestes : comptée dans
/// une vue, elle n'est vérifiable qu'à la main, une fois, par la personne qui
/// vient de l'écrire.
@Suite("File d'assignation")
struct AssignmentQueueTests {

    @Test("L'ordre des étapes est responsable → échéance → suivante")
    func stepOrder() {
        var file = AssignmentQueue([1, 2])
        #expect(file.etape == .responsable)
        file = file.apres(.tab)
        #expect(file.etape == .echeance)
        file = file.apres(.tab)
        #expect(file.etape == .suivante)
    }

    @Test("Trois gestes par action, et on passe à la suivante")
    func threeGesturesPerAction() {
        #expect(AssignmentQueue<Int>.gestesParAction == 3)
        var file = AssignmentQueue([10, 20, 30])
        #expect(file.courant == 10)
        for _ in 0..<AssignmentQueue<Int>.gestesParAction { file = file.apres(.tab) }
        #expect(file.courant == 20)
        #expect(file.etape == .responsable)
        for _ in 0..<AssignmentQueue<Int>.gestesParAction { file = file.apres(.tab) }
        #expect(file.courant == 30)
    }

    @Test("`⌘⏎` avance comme `Tab` : valider, c'est passer à la suite")
    func commandReturnAdvances() {
        var parTab = AssignmentQueue([1, 2])
        var parEntree = AssignmentQueue([1, 2])
        for _ in 0..<4 {
            parTab = parTab.apres(.tab)
            parEntree = parEntree.apres(.commandReturn)
        }
        #expect(parTab == parEntree)
    }

    @Test("Neuf gestes soldent trois actions et terminent la file")
    func completesAfterAllActions() {
        var file = AssignmentQueue([1, 2, 3])
        for _ in 0..<9 { file = file.apres(.tab) }
        #expect(file.estTerminee)
        #expect(file.estClose)
        #expect(file.courant == nil)
        #expect(file.estSortie == false)
    }

    @Test("Avancer sur une file terminée ne fait plus rien")
    func advancingPastTheEndIsInert() {
        var file = AssignmentQueue([1])
        for _ in 0..<3 { file = file.apres(.tab) }
        let terminee = file
        #expect(terminee.apres(.tab) == terminee)
        #expect(terminee.apres(.passer) == terminee)
    }

    @Test("« Passer » saute l'action sans rien poser")
    func skip() {
        var file = AssignmentQueue([1, 2])
        file = file.apres(.tab)          // sur l'échéance de la première
        file = file.apres(.passer)
        #expect(file.courant == 2)
        #expect(file.etape == .responsable)
    }

    @Test("`Esc` sort à n'importe quelle étape")
    func escapeFromAnyStep() {
        for gestes in 0...5 {
            var file = AssignmentQueue([1, 2])
            for _ in 0..<gestes { file = file.apres(.tab) }
            let sortie = file.apres(.escape)
            #expect(sortie.estSortie)
            #expect(sortie.estClose)
            #expect(sortie.courant == nil)
        }
    }

    @Test("`Esc` sur une file terminée ne la ressuscite pas")
    func escapeAfterCompletion() {
        var file = AssignmentQueue([1])
        for _ in 0..<3 { file = file.apres(.tab) }
        let sortie = file.apres(.escape)
        #expect(sortie.estClose)
        #expect(sortie.courant == nil)
    }

    @Test("Une file vide est close d'emblée : rien à présenter")
    func emptyQueue() {
        let file = AssignmentQueue<Int>([])
        #expect(file.estTerminee)
        #expect(file.estClose)
        #expect(file.courant == nil)
        #expect(file.progression == (0, 0))
    }

    @Test("La progression est bornée au total")
    func progression() {
        var file = AssignmentQueue([1, 2, 3])
        #expect(file.progression == (1, 3))
        for _ in 0..<3 { file = file.apres(.tab) }
        #expect(file.progression == (2, 3))
        for _ in 0..<6 { file = file.apres(.tab) }
        #expect(file.progression == (3, 3))
    }

    @Test("Chaque étape porte le libellé de la spec")
    func labels() {
        #expect(AssignmentQueue<Int>.libelle(.responsable) == "Responsable")
        #expect(AssignmentQueue<Int>.libelle(.echeance) == "Échéance")
        #expect(AssignmentQueue<Int>.libelle(.suivante) == "Suivante")
    }
}

/// Le bandeau lui-même : « `EN ATTENTE — n actions sans responsable` ».
@Suite("Bandeau EN ATTENTE")
@MainActor
struct PendingAssignmentTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Le libellé s'accorde, et zéro n'a pas de bandeau")
    func label() {
        #expect(PendingAssignment.libelle(0) == nil)
        #expect(PendingAssignment.libelle(-1) == nil)
        #expect(PendingAssignment.libelle(1) == "1 action sans responsable")
        #expect(PendingAssignment.libelle(3) == "3 actions sans responsable")
    }

    @Test("Seules les actions ouvertes et sans porteur sont en attente")
    func pendingActions() throws {
        let context = try makeContext()
        let porteur = Collaborator(name: "Cédric Payet", role: "")
        context.insert(porteur)

        let sansPorteur = ActionTask(title: "Clarifier la facturation")
        sansPorteur.destinataire = .collaborateur
        let avecPorteur = ActionTask(title: "Préparer gitlab.rb")
        avecPorteur.destinataire = .collaborateur
        avecPorteur.collaborator = porteur
        let mienne = ActionTask(title: "Chiffrer la fin de migration")
        mienne.destinataire = .moi
        let close = ActionTask(title: "Obtenir la photo globale")
        close.destinataire = .collaborateur
        close.isCompleted = true
        for tache in [sansPorteur, avecPorteur, mienne, close] { context.insert(tache) }

        let attente = PendingAssignment.sansResponsable([sansPorteur, avecPorteur, mienne, close])
        #expect(attente.map(\.title) == ["Clarifier la facturation"])
    }

    @Test("La règle est celle du groupe À ASSIGNER du rail, pas une seconde")
    func sameRuleAsRail() throws {
        let context = try makeContext()
        let taches = (0..<3).map { index -> ActionTask in
            let tache = ActionTask(title: "Action \(index)")
            tache.destinataire = .collaborateur
            tache.sortOrder = index
            context.insert(tache)
            return tache
        }
        let groupe = ActionsRailGrouping.groupes(for: taches)
            .first { $0.identite == .aAssigner }
        #expect(PendingAssignment.sansResponsable(taches).map(\.title)
                == (groupe?.actions ?? []).map(\.title))
    }
}
