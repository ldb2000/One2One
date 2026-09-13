import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La lecture des rôles d'un projet — décision **D3**, « la relation fait
/// foi ».
///
/// Le cas qui compte est `P25_099` du semis : le xlsx y écrit « NOMINE
/// Laurent » dans `chefDeProjet`, mais aucun `Collaborator` n'est lié. La
/// colonne du Portfolio doit afficher « Non affecté » — et le sélecteur de
/// l'action « Compléter » doit malgré tout proposer NOMINE Laurent.
@Suite("Rôles d'un projet (D3)")
@MainActor
struct ProjectPeopleTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func projet(_ contexte: ModelContext, code: String = "P25_001") -> Project {
        let p = Project(code: code, name: "Projet \(code)", domain: "ASP",
                        sponsor: "Direction ASP", projectType: "Métier", phase: "Build")
        contexte.insert(p)
        return p
    }

    private func collaborateur(_ contexte: ModelContext, _ nom: String) -> Collaborator {
        let c = Collaborator(name: nom, role: "Chef de projet")
        contexte.insert(c)
        return c
    }

    // MARK: - Ce qui s'affiche

    @Test("La relation posée rend le nom du collaborateur")
    func relationPosee() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.projectManager = collaborateur(contexte, "RIGAUT Manuel")
        #expect(ProjectPeople.manager(of: p) == "RIGAUT Manuel")
    }

    @Test("La chaîne du xlsx seule ne suffit pas : le chef de projet est nil")
    func chaineSansRelation() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.chefDeProjet = "NOMINE Laurent"
        #expect(p.projectManager == nil)
        #expect(ProjectPeople.manager(of: p) == nil)
    }

    @Test("Un nom réduit à des espaces compte pour vide")
    func nomBlanc() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.projectManager = collaborateur(contexte, "   ")
        #expect(ProjectPeople.manager(of: p) == nil)
    }

    @Test("Le nom est débarrassé de ses espaces de bord")
    func nomRogne() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.projectManager = collaborateur(contexte, "  PENVEN Yann ")
        #expect(ProjectPeople.manager(of: p) == "PENVEN Yann")
    }

    @Test("L'architecte suit la même règle que le chef de projet")
    func architecte() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.architecte = "THEDREZ Wilfried"
        #expect(ProjectPeople.architect(of: p) == nil)
        p.technicalArchitect = collaborateur(contexte, "THEDREZ Wilfried")
        #expect(ProjectPeople.architect(of: p) == "THEDREZ Wilfried")
    }

    @Test("« Non affecté » est le libellé du vide")
    func libelleDuVide() {
        #expect(ProjectPeople.nonAffecte == "Non affecté")
    }

    // MARK: - Ce que « Compléter » propose

    @Test("La suggestion résout la chaîne du xlsx en collaborateur")
    func suggestion() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.chefDeProjet = "NOMINE Laurent"
        let nomine = collaborateur(contexte, "NOMINE Laurent")
        let autre = collaborateur(contexte, "PENVEN Yann")
        let suggere = ProjectPeople.suggestedManager(for: p, among: [autre, nomine])
        #expect(suggere?.persistentModelID == nomine.persistentModelID)
    }

    @Test("La suggestion plie la casse et les accents")
    func suggestionInsensible() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.chefDeProjet = "zannettini francois-louis"
        let cible = collaborateur(contexte, "ZANNETTINI François-Louis")
        #expect(ProjectPeople.suggestedManager(for: p, among: [cible])?.name
                    == "ZANNETTINI François-Louis")
    }

    @Test("La correspondance porte sur le nom entier, pas sur un préfixe")
    func suggestionNomEntier() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.chefDeProjet = "RIGAUT Manuel"
        let presque = collaborateur(contexte, "RIGAUT Manuela")
        #expect(ProjectPeople.suggestedManager(for: p, among: [presque]) == nil)
    }

    @Test("Une chaîne vide ou blanche ne suggère rien")
    func suggestionSansChaine() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        let quelquun = collaborateur(contexte, "RIGAUT Manuel")
        #expect(ProjectPeople.suggestedManager(for: p, among: [quelquun]) == nil)
        p.chefDeProjet = "   "
        #expect(ProjectPeople.suggestedManager(for: p, among: [quelquun]) == nil)
    }

    @Test("Un nom que personne ne porte ne suggère rien")
    func suggestionIntrouvable() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.chefDeProjet = "QUELQU'UN Inconnu"
        #expect(ProjectPeople.suggestedManager(for: p,
                                               among: [collaborateur(contexte, "RIGAUT Manuel")]) == nil)
    }

    @Test("La suggestion d'architecte lit `architecte`, pas `chefDeProjet`")
    func suggestionArchitecte() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        p.chefDeProjet = "RIGAUT Manuel"
        p.architecte = "PAOLI Nicolas"
        let gens = [collaborateur(contexte, "RIGAUT Manuel"),
                    collaborateur(contexte, "PAOLI Nicolas")]
        #expect(ProjectPeople.suggestedArchitect(for: p, among: gens)?.name == "PAOLI Nicolas")
    }

    // MARK: - Sur le semis

    @Test("Sur le semis, P25_099 affiche « Non affecté » et suggère NOMINE Laurent")
    func surLeSemis() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let gens = try contexte.fetch(FetchDescriptor<Collaborator>())
        let p099 = try #require(projets.first { $0.code == "P25_099" })
        #expect(p099.chefDeProjet == "NOMINE Laurent")
        #expect(ProjectPeople.manager(of: p099) == nil)
        #expect(ProjectPeople.suggestedManager(for: p099, among: gens)?.name == "NOMINE Laurent")
        // P25_112, lui, est lié : la colonne affiche son chef de projet.
        let p112 = try #require(projets.first { $0.code == "P25_112" })
        #expect(ProjectPeople.manager(of: p112) == "RIGAUT Manuel")
    }
}
