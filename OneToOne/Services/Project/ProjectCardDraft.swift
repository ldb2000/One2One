import Foundation
import SwiftData

/// Le brouillon d'édition de la fiche projet : une `struct` détachée du modèle
/// SwiftData jusqu'à `Enregistrer`.
///
/// C'est la pièce qui tient le **critère d'acceptation n° 4 du chantier 3** —
/// « aucune modification de la fiche projet n'est écrite sans validation
/// humaine explicite ». Lier les champs du panneau directement à
/// `@Bindable project` écrirait dans le store à chaque frappe, et un
/// `Annuler` n'aurait plus rien à restaurer. Ici, tant que personne n'appelle
/// `apply(to:in:)`, `Project` ne bouge pas : c'est structurel, pas une
/// discipline.
///
/// L'instantané sert aussi à `UndoBanner` : la bannière garde le brouillon
/// d'avant enregistrement et le réapplique si l'utilisateur annule dans les
/// cinq secondes.
struct ProjectCardDraft: Equatable, Sendable {

    struct MilestoneDraft: Equatable, Sendable, Identifiable {
        /// `stableID` du jalon existant, ou un UUID neuf pour une ligne
        /// ajoutée dans le brouillon. Sert aussi d'identité SwiftUI.
        var id: UUID
        var label: String
        var dueAt: Date?
        var state: MilestoneState
        var order: Int
    }

    struct ContactDraft: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var role: String
        var order: Int
    }

    struct RiskDraft: Equatable, Sendable, Identifiable {
        /// Identité SwiftUI seulement : `ProjectAlert` n'a pas de `stableID`
        /// (c'est un modèle antérieur au programme de refonte), donc la
        /// réconciliation passe par `existing`.
        var id: UUID
        var title: String
        var severity: String
        /// Identité SwiftData de l'alerte d'origine ; `nil` pour un risque
        /// saisi dans le brouillon.
        var existing: PersistentIdentifier?

        /// `id` est **exclu** de l'égalité : il est retiré à chaque instantané,
        /// faute de `stableID` sur `ProjectAlert`. L'inclure ferait paraître
        /// modifié un brouillon que personne n'a touché — et le pied du
        /// panneau proposerait d'enregistrer le néant.
        static func == (gauche: RiskDraft, droite: RiskDraft) -> Bool {
            gauche.title == droite.title
                && gauche.severity == droite.severity
                && gauche.existing == droite.existing
        }
    }

    var status: ProjectCardStatus = .watch
    var budgetSpent: Double?
    /// Le budget total tel que l'utilisateur le voit : `budgetRev` s'il existe,
    /// `budgetInit` sinon.
    var budgetTotal: Double?
    var scopeText: String = ""
    var tags: [String] = []
    var milestones: [MilestoneDraft] = []
    var contacts: [ContactDraft] = []
    var risks: [RiskDraft] = []

    // MARK: - Lecture

    @MainActor
    static func snapshot(of project: Project) -> ProjectCardDraft {
        ProjectCardDraft(
            status: ProjectCardStatus(projectStatus: project.status),
            budgetSpent: project.budgetCons,
            budgetTotal: project.budgetRev ?? project.budgetInit,
            scopeText: project.scopeText,
            tags: project.tags,
            milestones: ProjectCardBuilder.sortedMilestones(project.milestones).map { jalon in
                MilestoneDraft(id: jalon.ensuredStableID,
                               label: jalon.label,
                               dueAt: jalon.dueAt,
                               state: jalon.state,
                               order: jalon.order)
            },
            contacts: ProjectCardBuilder.sortedContacts(project.contacts).map { contact in
                ContactDraft(id: contact.ensuredStableID,
                             name: contact.name,
                             role: contact.role,
                             order: contact.order)
            },
            // Les alertes **ouvertes** seulement, dans l'ordre du panneau. Une
            // alerte résolue reste en base et hors du brouillon : elle
            // appartient à l'historique du projet, pas à sa fiche courante.
            risks: project.alerts
                .filter { !$0.isResolved }
                .sorted { gauche, droite in
                    let ng = MeetingKPIBuilder.level(fromSeverity: gauche.severity)
                    let nd = MeetingKPIBuilder.level(fromSeverity: droite.severity)
                    if ng != nd { return ng < nd }
                    return gauche.date > droite.date
                }
                .map { alerte in
                    RiskDraft(id: UUID(),
                              title: alerte.title,
                              severity: alerte.severityRaw,
                              existing: alerte.persistentModelID)
                }
        )
    }

    // MARK: - Écriture

    /// Applique le brouillon au modèle. **Seul point d'écriture de la fiche** :
    /// appelé par `Enregistrer` et par l'annulation de `UndoBanner`, jamais
    /// par une frappe.
    ///
    /// Réconcilie par identité : met à jour les lignes existantes, insère les
    /// nouvelles, **supprime** celles que le brouillon ne porte plus. Les
    /// `order` sont renumérotés d'après le rang dans le tableau, sinon un jalon
    /// déplacé retrouverait sa place d'origine à la relecture.
    @MainActor
    func apply(to project: Project, in context: ModelContext) {
        project.status = status.projectStatusRaw
        project.budgetCons = budgetSpent
        project.scopeText = scopeText
        project.tags = tags

        // Le total saisi est le budget **révisé**. Égal à l'initial, il n'y a
        // pas de révision : `budgetRev` repasse à `nil` plutôt que de recopier
        // une donnée du portfolio externe, que le prochain import écraserait.
        if let total = budgetTotal, total != project.budgetInit {
            project.budgetRev = total
        } else {
            project.budgetRev = nil
        }

        applyMilestones(to: project, in: context)
        applyContacts(to: project, in: context)
        applyRisks(to: project, in: context)

        try? context.save()
    }

    @MainActor
    private func applyMilestones(to project: Project, in context: ModelContext) {
        let retenus = milestones.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let parID = Dictionary(project.milestones.map { ($0.ensuredStableID, $0) },
                               uniquingKeysWith: { premier, _ in premier })

        for (rang, ligne) in retenus.enumerated() {
            if let existant = parID[ligne.id] {
                existant.label = ligne.label
                existant.dueAt = ligne.dueAt
                existant.state = ligne.state
                existant.order = rang
            } else {
                let jalon = ProjectMilestone(label: ligne.label,
                                             dueAt: ligne.dueAt,
                                             state: ligne.state,
                                             order: rang)
                jalon.stableID = ligne.id
                context.insert(jalon)
                jalon.project = project
            }
        }

        let gardes = Set(retenus.map(\.id))
        for jalon in project.milestones where !gardes.contains(jalon.ensuredStableID) {
            context.delete(jalon)
        }
    }

    @MainActor
    private func applyContacts(to project: Project, in context: ModelContext) {
        let retenus = contacts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let parID = Dictionary(project.contacts.map { ($0.ensuredStableID, $0) },
                               uniquingKeysWith: { premier, _ in premier })

        for (rang, ligne) in retenus.enumerated() {
            if let existant = parID[ligne.id] {
                existant.name = ligne.name
                existant.role = ligne.role
                existant.order = rang
            } else {
                let contact = ProjectContact(name: ligne.name, role: ligne.role, order: rang)
                contact.stableID = ligne.id
                context.insert(contact)
                contact.project = project
            }
        }

        let gardes = Set(retenus.map(\.id))
        for contact in project.contacts where !gardes.contains(contact.ensuredStableID) {
            context.delete(contact)
        }
    }

    /// Les risques sont des `ProjectAlert`. Deux prudences par rapport aux
    /// jalons : une alerte **résolue** n'apparaît pas dans le brouillon et ne
    /// doit donc jamais être supprimée par son absence, et une alerte porte un
    /// lien vers la réunion qui l'a soulevée — on ne la recrée pas, on la
    /// modifie.
    @MainActor
    private func applyRisks(to project: Project, in context: ModelContext) {
        let retenus = risks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let parID = Dictionary(project.alerts.map { ($0.persistentModelID, $0) },
                               uniquingKeysWith: { premier, _ in premier })

        // Les alertes créées à l'instant rejoignent `project.alerts` : sans les
        // inscrire dans la liste des conservées, la passe de suppression
        // ci-dessous les effacerait aussitôt.
        var conservees = Set<PersistentIdentifier>()
        for ligne in retenus {
            if let identite = ligne.existing, let existant = parID[identite] {
                existant.title = ligne.title
                existant.severityRaw = ligne.severity
                conservees.insert(identite)
            } else {
                let alerte = ProjectAlert(title: ligne.title, severity: ligne.severity)
                context.insert(alerte)
                alerte.project = project
                conservees.insert(alerte.persistentModelID)
            }
        }

        for alerte in project.alerts
        where !alerte.isResolved && !conservees.contains(alerte.persistentModelID) {
            context.delete(alerte)
        }
    }
}
