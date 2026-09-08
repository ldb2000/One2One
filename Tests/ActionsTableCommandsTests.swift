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

    private var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func date(_ jour: Int, _ mois: Int, _ annee: Int) -> Date {
        calendrier.date(from: DateComponents(year: annee, month: mois, day: jour, hour: 9)) ?? .now
    }

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

    // MARK: - Largeurs de colonnes (spec §2.7)

    @Test("Les sept colonnes du tableau ont les largeurs de la spec")
    func columnWidths() {
        // `20px | 1fr | 108 | 92 | 62 | 76 | 30` : une colonne rognée de 20 px
        // ne se voit dans aucun test de rendu.
        #expect(ActionsTable.colonnes.etat == 20)
        #expect(ActionsTable.colonnes.responsable == 108)
        #expect(ActionsTable.colonnes.echeance == 92)
        #expect(ActionsTable.colonnes.charge == 62)
        #expect(ActionsTable.colonnes.source == 76)
        #expect(ActionsTable.colonnes.menu == 30)
        #expect(ActionsTable.lignesRepliees == 5)
    }

    @Test("Le sélecteur de vue est celui de la capture : Tableau · Eisenhower · Calendrier")
    func viewSelector() {
        #expect(ActionsTable.vues == [.liste, .eisenhower, .calendar])
        #expect(ActionsTable.libelleVue(.liste) == "Tableau")
        #expect(ActionsTable.libelleVue(.eisenhower) == "Eisenhower")
        #expect(ActionsTable.libelleVue(.calendar) == "Calendrier")
    }

    // MARK: - Colonnes ÉCHÉANCE et SOURCE

    @Test("La colonne ÉCHÉANCE montre les quatre états de la capture")
    func dueDateColumn() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion", date: date(4, 9, 2026))
        let origine = Meeting(title: "COSUI hebdo", date: date(1, 9, 2026))
        context.insert(reunion); context.insert(origine)

        let sansRien = ActionTask(title: "Vérifier l'état des comptes GitLab")
        let urgente = ActionTask(title: "Clarifier la situation de facturation")
        urgente.priority = .urgent
        let datee = ActionTask(title: "Chiffrer la fin de migration Marine")
        datee.dueDate = date(11, 9, 2026)
        let reportee = ActionTask(title: "Relancer le périmètre Digital")
        reportee.carriedFromMeeting = origine
        reportee.deferralCount = 2
        for tache in [sansRien, urgente, datee, reportee] {
            context.insert(tache)
            tache.meeting = reunion
        }

        #expect(ActionsTable.libelleEcheance(sansRien).texte == "＋ date")
        #expect(ActionsTable.libelleEcheance(sansRien).etat == .invite)
        #expect(ActionsTable.libelleEcheance(urgente).texte == "Urgent")
        #expect(ActionsTable.libelleEcheance(reportee).texte == "Reporté ×2")
        // Une date réelle l'emporte sur tout le reste.
        #expect(ActionsTable.libelleEcheance(datee, reference: date(4, 9, 2026),
                                             calendar: calendrier) == ("11 sept.", .neutre))
    }

    @Test("La colonne SOURCE mène au timecode, ou à défaut à la réunion d'origine")
    func sourceColumn() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion", date: date(4, 9, 2026))
        let origine = Meeting(title: "COSUI hebdo", date: date(1, 9, 2026))
        context.insert(reunion); context.insert(origine)

        let citee = ActionTask(title: "Vérifier l'état des comptes GitLab")
        citee.sourceRef = SourceRef(kind: .transcript, stableID: UUID(), t: 252)
        let reportee = ActionTask(title: "Relancer le périmètre Digital")
        reportee.carriedFromMeeting = origine
        reportee.deferralCount = 2
        let orpheline = ActionTask(title: "Isoler la partie data")
        for tache in [citee, reportee, orpheline] {
            context.insert(tache)
            tache.meeting = reunion
        }

        #expect(ActionsTable.libelleSource(citee) == "04:12 ↗")
        #expect(ActionsTable.libelleSource(reportee, calendar: calendrier) == "1er sept.")
        #expect(ActionsTable.libelleSource(orpheline) == nil)
    }
}
