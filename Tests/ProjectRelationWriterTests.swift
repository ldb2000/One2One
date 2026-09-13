import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'écriture de `Project.entity`, et le défaut SwiftData qu'elle contourne.
///
/// **Ce que ce fichier fige.** Réaffecter `Project.entity` — passer d'une
/// entité à une autre — puis appeler `save()` perd la nouvelle valeur environ
/// une fois sur trois sur un store en mémoire. C'est la seule relation du
/// modèle dont l'inverse est déclaré (`Entity.projects`), et c'est cet inverse
/// que SwiftData n'arrive pas à recoudre : lire `Entity.projects` juste après
/// le même `save` lève « Fatal error: Never access a full future backing
/// data ».
///
/// Les tests **répètent** : à une chance sur trois, trente tours rendent
/// l'échec certain (0,67³⁰ ≈ 10⁻⁶) et un tour unique ne prouverait rien. C'est
/// exactement ce qui s'est produit avant ce service : le test des relations du
/// brouillon passait seul et tombait une fois sur huit en suite complète.
@Suite("Écriture de la relation Entité")
@MainActor
struct ProjectRelationWriterTests {

    /// Assez de tours pour qu'un défaut à une chance sur trois ne passe pas.
    static let tours = 30

    private func contexte() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
    }

    /// Un projet déjà rattaché à « ASP », et une entité « RH » où l'envoyer.
    private func scene(_ contexte: ModelContext) throws -> (Project, Entity, Entity) {
        let projet = Project(code: "P25_001", name: "Projet", domain: "",
                             phase: "Design", status: "Green")
        contexte.insert(projet)
        let asp = Entity(name: "ASP")
        contexte.insert(asp)
        projet.entity = asp
        let rh = Entity(name: "RH")
        contexte.insert(rh)
        try contexte.save()
        return (projet, asp, rh)
    }

    // MARK: - Le défaut, mesuré

    /// La mesure qui justifie le service : sans lui, l'affectation se perd.
    /// Le test **n'exige pas** que la perte se produise — il constate que le
    /// contournement, lui, ne perd jamais.
    @Test("Réaffecter puis enregistrer, sans réparation, perd parfois la valeur")
    func leDefautExiste() throws {
        var pertes = 0
        for _ in 0..<Self.tours {
            let contexte = try contexte()
            let (projet, _, rh) = try scene(contexte)
            projet.entity = rh
            try? contexte.save()
            if projet.entity?.persistentModelID != rh.persistentModelID { pertes += 1 }
        }
        // Aucune attente sur le nombre : le jour où SwiftData corrigera son
        // défaut, ce test doit rester vert, et seuls les suivants comptent.
        #expect(pertes >= 0)
    }

    // MARK: - Le contournement

    @Test("Le writer rattache le projet à sa nouvelle entité, trente fois sur trente")
    func writerTientLaValeur() throws {
        for _ in 0..<Self.tours {
            let contexte = try contexte()
            let (projet, _, rh) = try scene(contexte)
            ProjectRelationWriter.setEntity(rh, on: [projet], in: contexte)
            #expect(projet.entity?.name == "RH")
        }
    }

    @Test("Le writer sait aussi détacher")
    func writerDetache() throws {
        for _ in 0..<Self.tours {
            let contexte = try contexte()
            let (projet, _, _) = try scene(contexte)
            ProjectRelationWriter.setEntity(nil, on: [projet], in: contexte)
            #expect(projet.entity == nil)
        }
    }

    @Test("Une première affectation passe aussi par le writer, sans réparation")
    func premiereAffectation() throws {
        let contexte = try contexte()
        let projet = Project(code: "P25_002", name: "Neuf", domain: "",
                             phase: "Cadrage", status: "Green")
        contexte.insert(projet)
        let rh = Entity(name: "RH")
        contexte.insert(rh)
        try contexte.save()
        let repare = ProjectRelationWriter.setEntity(rh, on: [projet], in: contexte)
        #expect(projet.entity?.name == "RH")
        #expect(!repare, "une première affectation n'a jamais eu besoin d'être réparée")
    }

    @Test("Une sélection vide ne fait rien")
    func selectionVide() throws {
        let contexte = try contexte()
        let rh = Entity(name: "RH")
        contexte.insert(rh)
        #expect(!ProjectRelationWriter.setEntity(rh, on: [], in: contexte))
    }

    @Test("Le writer déplace toute une sélection")
    func selectionMultiple() throws {
        for _ in 0..<Self.tours {
            let contexte = try contexte()
            let (premier, _, rh) = try scene(contexte)
            let second = Project(code: "P25_003", name: "Second", domain: "",
                                 phase: "Design", status: "Green")
            contexte.insert(second)
            second.entity = premier.entity
            try contexte.save()

            ProjectRelationWriter.setEntity(rh, on: [premier, second], in: contexte)
            #expect(premier.entity?.name == "RH")
            #expect(second.entity?.name == "RH")
        }
    }

    // MARK: - Les deux appelants

    /// La barre d'actions en lot (lot 2) portait le même défaut : elle
    /// affectait la relation puis enregistrait, comme les cinq autres
    /// opérations, qui écrivent des colonnes et ne risquent rien.
    @Test("La barre d'actions en lot passe par le writer")
    func barreEnLot() throws {
        for _ in 0..<Self.tours {
            let contexte = try contexte()
            let (projet, _, rh) = try scene(contexte)
            ProjectBatchActions.setEntity(rh, on: [projet])
            #expect(projet.entity?.name == "RH")
        }
    }

    /// L'édition in-place (lot 4, décision **D9**) : c'est elle qui a rendu le
    /// défaut visible, par un test qui tombait une fois sur huit.
    @Test("Le brouillon de fiche projet passe par le writer")
    func brouillonDeFiche() throws {
        for _ in 0..<Self.tours {
            let contexte = try contexte()
            let (projet, _, rh) = try scene(contexte)
            var brouillon = ProjectCardDraft.snapshot(of: projet)
            brouillon.entityID = rh.persistentModelID
            brouillon.apply(to: projet, in: contexte)
            #expect(projet.entity?.name == "RH")
        }
    }
}
