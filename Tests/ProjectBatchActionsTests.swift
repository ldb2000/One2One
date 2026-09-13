import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les actions en lot sur une sélection de projets (décision **D15**) et la
/// création d'un projet.
///
/// Elles étaient cinq méthodes privées de `Sidebar.swift`, donc non testées :
/// c'est le premier test qu'elles reçoivent. Le Portfolio et la barre latérale
/// appellent désormais les mêmes.
@Suite("Actions en lot sur les projets (D15)")
@MainActor
struct ProjectBatchActionsTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func projet(_ contexte: ModelContext,
                        code: String,
                        phase: String = "Cadrage",
                        statut: String = "Green") -> Project {
        let p = Project(code: code, name: "Projet \(code)", domain: "ASP",
                        sponsor: "Direction", projectType: "Métier",
                        phase: phase, status: statut)
        contexte.insert(p)
        return p
    }

    // MARK: - Résolution de la sélection

    @Test("La sélection se résout par PersistentIdentifier, dans l'ordre de la liste")
    func resolution() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let b = projet(contexte, code: "T_B")
        let c = projet(contexte, code: "T_C")
        let choisis = ProjectBatchActions.resolve([c.persistentModelID, a.persistentModelID],
                                                  among: [a, b, c])
        #expect(choisis.map(\.code) == ["T_A", "T_C"])
    }

    @Test("Une sélection vide ne résout rien ; un identifiant orphelin est ignoré")
    func resolutionVide() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let disparu = projet(contexte, code: "T_X")
        let idDisparu = disparu.persistentModelID
        #expect(ProjectBatchActions.resolve([], among: [a]).isEmpty)
        #expect(ProjectBatchActions.resolve([idDisparu], among: [a]).isEmpty)
    }

    // MARK: - Les cinq opérations

    @Test("La phase s'applique à toute la sélection, et à elle seule")
    func phaseEnLot() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let b = projet(contexte, code: "T_B")
        let hors = projet(contexte, code: "T_C")
        ProjectBatchActions.setPhase("Build", on: [a, b])
        #expect(a.phase == "Build")
        #expect(b.phase == "Build")
        #expect(hors.phase == "Cadrage")
    }

    @Test("Le statut s'applique à toute la sélection")
    func statutEnLot() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        ProjectBatchActions.setStatus("Red", on: [a])
        #expect(a.status == "Red")
    }

    @Test("Une valeur hors table est acceptée telle quelle (D14)")
    func valeurHorsTable() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        ProjectBatchActions.setPhase("Réalisation", on: [a])
        #expect(a.phase == "Réalisation")
        #expect(ProjectPhase(raw: a.phase) == nil)
    }

    @Test("L'entité se pose et se retire — c'est « Déplacer vers une entité »")
    func entiteEnLot() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let cible = Entity(name: "LOG")
        contexte.insert(cible)
        ProjectBatchActions.setEntity(cible, on: [a])
        #expect(a.entity?.name == "LOG")
        ProjectBatchActions.setEntity(nil, on: [a])
        #expect(a.entity == nil)
    }

    @Test("Archiver ne supprime rien ; désarchiver revient en arrière")
    func archivage() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let b = projet(contexte, code: "T_B")
        ProjectBatchActions.archive([a, b])
        #expect(a.isArchived)
        #expect(b.isArchived)
        #expect(try contexte.fetch(FetchDescriptor<Project>()).count == 2)
        ProjectBatchActions.unarchive([a])
        #expect(!a.isArchived)
        #expect(b.isArchived)
    }

    @Test("Un projet archivé quitte le tableau du Portfolio")
    func archiveQuitteLeTableau() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        #expect(PortfolioBuilder.rows(projects: [a], meetings: [], today: Date()).count == 1)
        ProjectBatchActions.archive([a])
        #expect(PortfolioBuilder.rows(projects: [a], meetings: [], today: Date()).isEmpty)
    }

    @Test("Supprimer retire les projets du store, et rien d'autre")
    func suppression() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let b = projet(contexte, code: "T_B")
        try contexte.save()
        ProjectBatchActions.delete([a], in: contexte)
        let restants = try contexte.fetch(FetchDescriptor<Project>())
        #expect(restants.map(\.code) == ["T_B"])
        #expect(b.isArchived == false)
    }

    @Test("Supprimer emporte les jalons du projet (cascade)")
    func suppressionEnCascade() throws {
        let contexte = try contexteEnMemoire()
        let a = projet(contexte, code: "T_A")
        let jalon = ProjectMilestone(label: "Livraison", dueAt: Date(), state: .planned)
        contexte.insert(jalon)
        jalon.project = a
        try contexte.save()
        #expect(try contexte.fetch(FetchDescriptor<ProjectMilestone>()).count == 1)
        ProjectBatchActions.delete([a], in: contexte)
        #expect(try contexte.fetch(FetchDescriptor<ProjectMilestone>()).isEmpty)
    }

    @Test("Une sélection vide ne fait rien, sur aucune opération")
    func selectionVide() throws {
        let contexte = try contexteEnMemoire()
        let temoin = projet(contexte, code: "T_A")
        try contexte.save()
        ProjectBatchActions.setPhase("Build", on: [])
        ProjectBatchActions.setStatus("Red", on: [])
        ProjectBatchActions.setEntity(nil, on: [])
        ProjectBatchActions.archive([])
        ProjectBatchActions.unarchive([])
        ProjectBatchActions.delete([], in: contexte)
        #expect(temoin.phase == "Cadrage")
        #expect(try contexte.fetch(FetchDescriptor<Project>()).count == 1)
    }

    // MARK: - Création d'un projet

    @Test("Le prochain code est le premier PXX_ libre")
    func prochainCode() {
        #expect(ProjectCreation.prochainCode(parmi: []) == "PXX_001")
        #expect(ProjectCreation.prochainCode(parmi: ["PXX_001"]) == "PXX_002")
        #expect(ProjectCreation.prochainCode(parmi: ["PXX_001", "PXX_003"]) == "PXX_002")
        // Les codes du portfolio externe n'entrent pas en collision.
        #expect(ProjectCreation.prochainCode(parmi: ["P25_112"]) == "PXX_001")
    }

    @Test("« ＋ Nouveau projet » crée un projet actif, en Cadrage, dans le store")
    func creation() throws {
        let contexte = try contexteEnMemoire()
        let existant = projet(contexte, code: "PXX_001")
        let neuf = ProjectCreation.creer(among: [existant], in: contexte)
        #expect(neuf.code == "PXX_002")
        #expect(neuf.name == "Nouveau projet")
        #expect(neuf.phase == "Cadrage")
        #expect(neuf.projectType == "Métier")
        #expect(!neuf.isArchived)
        #expect(neuf.entity == nil)
        #expect(try contexte.fetch(FetchDescriptor<Project>()).count == 2)
    }

    @Test("Créer dans une entité rattache le projet et lui donne son domaine")
    func creationDansEntite() throws {
        let contexte = try contexteEnMemoire()
        let entite = Entity(name: "LOG")
        contexte.insert(entite)
        let neuf = ProjectCreation.creer(among: [], entity: entite, in: contexte)
        #expect(neuf.entity?.name == "LOG")
        #expect(neuf.domain == "LOG")
    }

    @Test("Un projet neuf apparaît dans le tableau du Portfolio")
    func creationApparaitDansLeTableau() throws {
        let contexte = try contexteEnMemoire()
        let neuf = ProjectCreation.creer(among: [], in: contexte)
        let lignes = PortfolioBuilder.rows(projects: [neuf], meetings: [], today: Date())
        #expect(lignes.count == 1)
        #expect(lignes[0].name == ProjectCreation.nomParDefaut)
        #expect(lignes[0].phase == .cadrage)
        #expect(lignes[0].manager == nil)
    }
}
