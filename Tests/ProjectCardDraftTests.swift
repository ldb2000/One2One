import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le brouillon de la fiche projet.
///
/// C'est lui qui porte le **critère d'acceptation n° 4 du chantier 3** :
/// « aucune modification de la fiche projet n'est écrite sans validation
/// humaine explicite ». Un brouillon `struct`, détaché du modèle SwiftData
/// jusqu'à `Enregistrer`, est la seule façon de le garantir structurellement
/// plutôt que par discipline : une vue liée directement à `@Bindable project`
/// écrirait dans le store à chaque frappe.
@Suite("Fiche projet — brouillon")
@MainActor
struct ProjectCardDraftTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    /// Le projet de la capture 3b, avec ses trois jalons, ses interlocuteurs et
    /// ses tags.
    private func makeProject(_ context: ModelContext) -> Project {
        let projet = Project(code: "P25_110",
                             name: "S/D — Modernisation CI/CD",
                             domain: "S/D",
                             phase: "Réalisation",
                             status: "Yellow")
        projet.budgetCons = 40_000
        projet.budgetInit = 61_000
        projet.scopeText = "Refonte de la chaîne CI/CD."
        projet.tags = ["GitLab", "Nexus"]
        context.insert(projet)

        for (index, gabarit) in [("Migration AP finalisée", MilestoneState.done),
                                 ("Migration Marine", MilestoneState.late),
                                 ("Bascule Jenkins", MilestoneState.planned)].enumerated() {
            let jalon = ProjectMilestone(label: gabarit.0, state: gabarit.1, order: index)
            context.insert(jalon)
            jalon.project = projet
        }
        let contact = ProjectContact(name: "Olivier Freund", role: "partenaire", order: 0)
        context.insert(contact)
        contact.project = projet

        let alerte = ProjectAlert(title: "Corruption base de données", severity: "Critique")
        context.insert(alerte)
        alerte.project = projet

        try? context.save()
        return projet
    }

    // MARK: - Instantané

    @Test("L'instantané reprend statut, budgets, périmètre, tags, jalons, interlocuteurs et risques")
    func snapshotReadsEverything() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let brouillon = ProjectCardDraft.snapshot(of: projet)

        #expect(brouillon.status == .watch)
        #expect(brouillon.budgetSpent == 40_000)
        #expect(brouillon.budgetTotal == 61_000)
        #expect(brouillon.scopeText == "Refonte de la chaîne CI/CD.")
        #expect(brouillon.tags == ["GitLab", "Nexus"])
        #expect(brouillon.milestones.map(\.label) == ["Migration AP finalisée", "Migration Marine", "Bascule Jenkins"])
        #expect(brouillon.milestones.map(\.state) == [.done, .late, .planned])
        #expect(brouillon.contacts.map(\.name) == ["Olivier Freund"])
        #expect(brouillon.risks.map(\.title) == ["Corruption base de données"])
    }

    // MARK: - Critère chantier 3 n° 4, versant brouillon

    /// **Le test du critère.** Modifier le brouillon de bout en bout — statut,
    /// budget, périmètre, tags, jalon existant, jalon neuf, suppression,
    /// interlocuteur, risque — puis vérifier que `Project` n'a pas bougé d'un
    /// octet. Rien n'est écrit avant `apply`.
    @Test("Modifier le brouillon ne touche pas au modèle SwiftData")
    func draftEditsNeverReachTheModel() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)

        brouillon.status = .risk
        brouillon.budgetSpent = 55_000
        brouillon.budgetTotal = 70_000
        brouillon.scopeText = "Tout autre chose."
        brouillon.tags = ["Autre"]
        brouillon.milestones[0].label = "Renommé"
        brouillon.milestones[0].state = .inProgress
        brouillon.milestones.removeLast()
        brouillon.milestones.append(.init(id: UUID(), label: "Jalon neuf", dueAt: nil,
                                          state: .planned, order: 9))
        brouillon.contacts = []
        brouillon.risks[0].title = "Autre risque"

        // Le modèle, lui, n'a rien vu.
        #expect(projet.status == "Yellow")
        #expect(projet.budgetCons == 40_000)
        #expect(projet.budgetInit == 61_000)
        #expect(projet.scopeText == "Refonte de la chaîne CI/CD.")
        #expect(projet.tags == ["GitLab", "Nexus"])
        #expect(projet.milestones.count == 3)
        #expect(ProjectCardBuilder.sortedMilestones(projet.milestones).map(\.label)
                == ["Migration AP finalisée", "Migration Marine", "Bascule Jenkins"])
        #expect(projet.contacts.count == 1)
        #expect(projet.alerts.first?.title == "Corruption base de données")
        #expect(try context.fetch(FetchDescriptor<ProjectMilestone>()).count == 3)
    }

    @Test("Un brouillon intact ne signale aucun changement")
    func untouchedDraftHasNoChanges() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let brouillon = ProjectCardDraft.snapshot(of: projet)
        #expect(brouillon == ProjectCardDraft.snapshot(of: projet))
    }

    // MARK: - Enregistrement

    @Test("Enregistrer écrit statut, budget, périmètre et tags")
    func applyWritesScalarFields() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        brouillon.status = .risk
        brouillon.budgetSpent = 55_000
        brouillon.budgetTotal = 70_000
        brouillon.scopeText = "Périmètre révisé."
        brouillon.tags = ["GitLab", "PostgreSQL", "Cléva"]
        brouillon.apply(to: projet, in: context)

        #expect(projet.status == "Red")
        #expect(projet.budgetCons == 55_000)
        // Le total révisé s'écrit dans `budgetRev`, jamais sur `budgetInit` :
        // l'initial est une donnée du portfolio externe, pas une saisie.
        #expect(projet.budgetRev == 70_000)
        #expect(projet.budgetInit == 61_000)
        #expect(projet.scopeText == "Périmètre révisé.")
        #expect(projet.tags == ["GitLab", "PostgreSQL", "Cléva"])
    }

    @Test("Enregistrer met à jour un jalon existant sans le dupliquer")
    func applyUpdatesMilestoneInPlace() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let echeance = Date(timeIntervalSince1970: 1_759_190_400)
        brouillon.milestones[1].label = "Migration Marine — chiffrage à valider"
        brouillon.milestones[1].state = .inProgress
        brouillon.milestones[1].dueAt = echeance
        brouillon.apply(to: projet, in: context)

        #expect(projet.milestones.count == 3)
        let tries = ProjectCardBuilder.sortedMilestones(projet.milestones)
        #expect(tries[1].label == "Migration Marine — chiffrage à valider")
        #expect(tries[1].state == .inProgress)
        #expect(tries[1].dueAt == echeance)
        #expect(try context.fetch(FetchDescriptor<ProjectMilestone>()).count == 3)
    }

    @Test("Enregistrer insère les jalons neufs et supprime ceux retirés")
    func applyInsertsAndDeletesMilestones() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        brouillon.milestones.removeFirst()
        brouillon.milestones.append(.init(id: UUID(), label: "Recette de bout en bout",
                                          dueAt: nil, state: .planned, order: 42))
        brouillon.apply(to: projet, in: context)

        let labels = ProjectCardBuilder.sortedMilestones(projet.milestones).map(\.label)
        #expect(labels == ["Migration Marine", "Bascule Jenkins", "Recette de bout en bout"])
        // Le jalon retiré est bien supprimé du store, pas seulement détaché.
        #expect(try context.fetch(FetchDescriptor<ProjectMilestone>()).count == 3)
        // Les `order` sont renumérotés d'après le rang, sinon un jalon ajouté
        // avec `order: 42` resterait au fond même après un glisser-déposer.
        #expect(ProjectCardBuilder.sortedMilestones(projet.milestones).map(\.order) == [0, 1, 2])
    }

    /// Un libellé vide, c'est la ligne d'ajout qu'on a survolée sans rien
    /// taper. L'enregistrer créerait une ligne fantôme impossible à distinguer
    /// d'un bogue.
    @Test("Un jalon, un interlocuteur ou un risque au libellé vide n'est pas écrit")
    func applyIgnoresBlankRows() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        brouillon.milestones.append(.init(id: UUID(), label: "   ", dueAt: nil,
                                          state: .planned, order: 3))
        brouillon.contacts.append(.init(id: UUID(), name: "", role: "sponsor", order: 1))
        brouillon.risks.append(.init(id: UUID(), title: "", severity: "Élevé"))
        brouillon.apply(to: projet, in: context)

        #expect(projet.milestones.count == 3)
        #expect(projet.contacts.count == 1)
        #expect(projet.alerts.count == 1)
    }

    @Test("Enregistrer écrit les interlocuteurs et les risques")
    func applyWritesContactsAndRisks() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        brouillon.contacts.append(.init(id: UUID(), name: "Claire-Amélie F.-D.",
                                        role: "architecte", order: 1))
        brouillon.risks.append(.init(id: UUID(), title: "Confusion source de code",
                                     severity: "Critique"))
        brouillon.apply(to: projet, in: context)

        #expect(ProjectCardBuilder.sortedContacts(projet.contacts).map(\.name)
                == ["Olivier Freund", "Claire-Amélie F.-D."])
        #expect(projet.alerts.count == 2)
        #expect(projet.alerts.contains { $0.title == "Confusion source de code" })
    }

    /// L'aller-retour est ce qui rend `Annuler` fiable : la bannière restaure
    /// un instantané, donc l'instantané doit être une description complète.
    @Test("Enregistrer puis reprendre un instantané redonne le même brouillon")
    func roundTripIsStable() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        brouillon.status = .ok
        brouillon.scopeText = "Autre périmètre."
        brouillon.milestones[0].label = "Renommé"
        brouillon.apply(to: projet, in: context)

        let relu = ProjectCardDraft.snapshot(of: projet)
        #expect(relu.status == .ok)
        #expect(relu.scopeText == "Autre périmètre.")
        #expect(relu.milestones.map(\.label) == ["Renommé", "Migration Marine", "Bascule Jenkins"])
        #expect(relu.tags == brouillon.tags)
        #expect(relu.contacts.map(\.name) == brouillon.contacts.map(\.name))
    }

    /// C'est le geste `Annuler` de `UndoBanner` : réappliquer l'instantané
    /// d'avant enregistrement remet exactement l'état d'avant.
    @Test("Réappliquer l'instantané précédent restaure l'état d'avant")
    func reapplyingSnapshotRestoresPreviousState() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let avant = ProjectCardDraft.snapshot(of: projet)

        var modifie = avant
        modifie.status = .risk
        modifie.scopeText = "Écrasé."
        modifie.milestones.removeLast()
        modifie.apply(to: projet, in: context)
        #expect(projet.status == "Red")
        #expect(projet.milestones.count == 2)

        avant.apply(to: projet, in: context)
        #expect(projet.status == "Yellow")
        #expect(projet.scopeText == "Refonte de la chaîne CI/CD.")
        #expect(ProjectCardBuilder.sortedMilestones(projet.milestones).map(\.label)
                == ["Migration AP finalisée", "Migration Marine", "Bascule Jenkins"])
    }
}
