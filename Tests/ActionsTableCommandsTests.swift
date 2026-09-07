import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La navigation clavier du tableau d'actions du poste de pilotage
/// (spec §2.7 : « `↑↓` navigue, `Espace` coche, `⌥↑↓` réordonne »).
///
/// Ces règles sont extraites de la vue pour la raison qui vaut pour tout ce
/// lot : un réordonnancement qui ne survit pas au prochain rendu — parce que
/// `sortOrder` n'a pas été réécrit, ou l'a été de travers — se voit à l'œil une
/// fois sur trois, et jamais dans une suite de tests qui n'appelle que la vue.
@Suite("Commandes du tableau d'actions")
@MainActor
struct ActionsTableCommandsTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: - `↑↓`

    @Test("Sans sélection, ↓ prend la première ligne et ↑ la dernière")
    func firstSelection() {
        #expect(ActionsTableCommands.indexSuivant(courant: nil, nombre: 5, delta: 1) == 0)
        #expect(ActionsTableCommands.indexSuivant(courant: nil, nombre: 5, delta: -1) == 4)
    }

    @Test("La navigation est bornée : elle ne boucle pas et ne sort pas du tableau")
    func boundedNavigation() {
        #expect(ActionsTableCommands.indexSuivant(courant: 0, nombre: 5, delta: -1) == 0)
        #expect(ActionsTableCommands.indexSuivant(courant: 4, nombre: 5, delta: 1) == 4)
        #expect(ActionsTableCommands.indexSuivant(courant: 2, nombre: 5, delta: 1) == 3)
        #expect(ActionsTableCommands.indexSuivant(courant: 2, nombre: 5, delta: -1) == 1)
    }

    @Test("Un tableau vide n'a pas de ligne à sélectionner")
    func emptyTable() {
        #expect(ActionsTableCommands.indexSuivant(courant: nil, nombre: 0, delta: 1) == nil)
        #expect(ActionsTableCommands.indexSuivant(courant: 3, nombre: 0, delta: 1) == nil)
    }

    @Test("Une sélection hors bornes est ramenée dans le tableau")
    func staleSelection() {
        #expect(ActionsTableCommands.indexSuivant(courant: 9, nombre: 3, delta: 1) == 2)
        #expect(ActionsTableCommands.indexSuivant(courant: -4, nombre: 3, delta: -1) == 0)
    }

    // MARK: - `⌥↑↓`

    @Test("⌥↑ échange la ligne avec celle du dessus")
    func moveUp() {
        #expect(ActionsTableCommands.permutation(nombre: 4, index: 2, delta: -1) == [0, 2, 1, 3])
    }

    @Test("⌥↓ échange la ligne avec celle du dessous")
    func moveDown() {
        #expect(ActionsTableCommands.permutation(nombre: 4, index: 0, delta: 1) == [1, 0, 2, 3])
    }

    @Test("Un déplacement hors du tableau ne renvoie aucune permutation")
    func moveOutOfBounds() {
        #expect(ActionsTableCommands.permutation(nombre: 4, index: 0, delta: -1) == nil)
        #expect(ActionsTableCommands.permutation(nombre: 4, index: 3, delta: 1) == nil)
        #expect(ActionsTableCommands.permutation(nombre: 0, index: 0, delta: 1) == nil)
        #expect(ActionsTableCommands.permutation(nombre: 4, index: 7, delta: 1) == nil)
    }

    // MARK: - `sortOrder`

    @Test("L'ordre appliqué survit au tri du rail")
    func appliedOrderSurvivesGrouping() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final")
        context.insert(reunion)

        // Des `sortOrder` hérités du composeur : négatifs, non contigus. C'est
        // le cas réel — `ActionComposerService` place une action neuve à
        // `minimum − 1`.
        let titres = ["Vérifier les comptes GitLab", "Clarifier la facturation",
                      "Chiffrer la fin Marine", "Planifier la formation Admin"]
        var lignes: [ActionTask] = []
        for (index, titre) in titres.enumerated() {
            let tache = ActionTask(title: titre)
            tache.sortOrder = -3 + index * 5
            tache.destinataire = .collaborateur
            context.insert(tache)
            tache.meeting = reunion
            lignes.append(tache)
        }

        guard let permutation = ActionsTableCommands.permutation(nombre: 4, index: 3, delta: -1) else {
            Issue.record("La permutation devrait exister")
            return
        }
        let reordonnees = permutation.map { lignes[$0] }
        ActionsTableCommands.appliquerOrdre(reordonnees)

        // Les `sortOrder` sont strictement croissants dans le nouvel ordre…
        #expect(reordonnees.map(\.sortOrder) == [0, 1, 2, 3])
        // …et le tri du rail rend exactement cet ordre : c'est la seule preuve
        // qui compte, `ActionsRailGrouping.triees` étant le lecteur réel.
        #expect(ActionsRailGrouping.triees(lignes).map(\.title)
                == reordonnees.map(\.title))
        #expect(reordonnees.map(\.title) == ["Vérifier les comptes GitLab",
                                             "Clarifier la facturation",
                                             "Planifier la formation Admin",
                                             "Chiffrer la fin Marine"])
    }

    // MARK: - Première action non assignée

    @Test("Le focus va à la première action sans porteur, nom non résolu compris")
    func firstUnassigned() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final")
        context.insert(reunion)
        let porteur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(porteur)

        let assignee = ActionTask(title: "Chiffrer la fin Marine")
        assignee.collaborator = porteur
        // Un nom que l'extraction n'a pas relié à une fiche **compte** comme un
        // porteur : même règle que `ActionsRailGrouping.aUnPorteur`, sinon le
        // badge « n sans responsable » et le focus désigneraient deux lignes
        // différentes.
        let nommee = ActionTask(title: "Relancer le périmètre Digital")
        nommee.unresolvedAssigneeName = "Alexis"
        let libre = ActionTask(title: "Clarifier la facturation")
        libre.destinataire = .collaborateur
        for tache in [assignee, nommee, libre] {
            context.insert(tache)
            tache.meeting = reunion
        }

        #expect(ActionsTableCommands.premiereSansResponsable([assignee, nommee, libre]) == 2)
        #expect(ActionsTableCommands.premiereSansResponsable([assignee, nommee]) == nil)
        #expect(ActionsTableCommands.premiereSansResponsable([]) == nil)
    }

    // MARK: - Repli

    @Test("Le tableau se replie à cinq lignes et annonce le reste")
    func collapse() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final")
        context.insert(reunion)
        var lignes: [ActionTask] = []
        for index in 0..<12 {
            let tache = ActionTask(title: "Action \(index)")
            context.insert(tache)
            tache.meeting = reunion
            lignes.append(tache)
        }

        let replie = ActionsTableCommands.repli(lignes, limite: 5, tout: false)
        #expect(replie.visibles.count == 5)
        #expect(replie.restantes == 7)

        let deplie = ActionsTableCommands.repli(lignes, limite: 5, tout: true)
        #expect(deplie.visibles.count == 12)
        #expect(deplie.restantes == 0)

        // Moins de lignes que la limite : rien à annoncer, et surtout pas
        // « −7 autres ».
        let courtes = ActionsTableCommands.repli(Array(lignes.prefix(3)), limite: 5, tout: false)
        #expect(courtes.visibles.count == 3)
        #expect(courtes.restantes == 0)
    }

}
