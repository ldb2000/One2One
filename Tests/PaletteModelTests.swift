import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le modèle de la palette `⌘K` (capture `1c-palette-cmdk.png`), testé **sur
/// le semis de démonstration** avec le terme de la capture — « ged ».
///
/// Tout ce que la palette décide est ici : quels projets remontent et dans
/// quel ordre, quelles actions les suivent, où va la sélection quand on
/// presse `↑` ou `↓`, ce que `⌘↩` bascule, et à quoi ressemble la sous-ligne
/// `code · entité · phase · chef de projet`. La vue ne calcule rien
/// (décision **D11**).
@Suite("Palette de commandes")
@MainActor
struct PaletteModelTests {

    // MARK: - Outillage

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Le store de la recette `p1c` : le portefeuille de démonstration entier.
    private func semis() throws -> (contexte: ModelContext, projets: [Project]) {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        return (contexte, try contexte.fetch(FetchDescriptor<Project>()))
    }

    /// Le modèle chargé sur un terme, comme la vue le fait à chaque frappe.
    private func modele(_ projets: [Project], _ terme: String) -> PaletteModel {
        let m = PaletteModel()
        m.recharger(projects: projets, terme: terme)
        return m
    }

    // MARK: - Les résultats de la capture

    @Test("« ged » rend les deux projets de la capture, l'épinglé d'abord")
    func lesDeuxProjetsDeLaCapture() throws {
        let (_, projets) = try semis()
        let m = modele(projets, RefonteDemoSeed.portfolioPaletteQuery)
        #expect(m.projets.map(\.code) == ["P25_087", "P24_211"])
    }

    @Test("un projet archivé remonte dans la palette")
    func archiveRemonte() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        let migration = try #require(m.projets.first { $0.code == "P24_211" })
        // La capture 1c montre « RH – Migration GED documentaire », qui est
        // archivé : la palette cherche dans tout le portefeuille, à la
        // différence du Portfolio, qui ne montre que les actifs.
        #expect(migration.isArchived)
    }

    @Test("les résultats sont bornés à six projets")
    func borneASix() throws {
        let (_, projets) = try semis()
        // « ASP » désigne quinze projets actifs du semis, plus les archivés.
        let m = modele(projets, "ASP")
        #expect(m.projets.count == PaletteModel.maxProjets)
        #expect(PaletteModel.maxProjets == 6)
    }

    @Test("un terme sans correspondance ne rend aucun projet, mais les actions")
    func aucunProjet() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "zzzzz")
        #expect(m.projets.isEmpty)
        #expect(m.aucunProjet)
        #expect(m.actions == [.creer, .chercher])
        #expect(m.nombreDeLignes == 2)
    }

    @Test("un terme vide n'affiche ni projet ni action")
    func termeVide() throws {
        let (_, projets) = try semis()
        for terme in ["", "   ", "\n"] {
            let m = modele(projets, terme)
            #expect(m.projets.isEmpty, "« \(terme) » ne doit rien rendre")
            // Ni « Aucun projet » — rien n'a été cherché — ni les actions :
            // on ne crée pas un projet sans nom et on ne cherche pas le vide.
            #expect(!m.aucunProjet)
            #expect(m.actions.isEmpty)
            #expect(m.nombreDeLignes == 0)
            #expect(m.estVide)
        }
    }

    @Test("le rechargement remet la sélection sur la première ligne")
    func rechargementReinitialiseLaSelection() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        m.suivant()
        #expect(m.index == 1)
        m.recharger(projects: projets, terme: "ged")
        #expect(m.index == 0)
    }

    // MARK: - Navigation au clavier

    @Test("↓ et ↑ parcourent les lignes sans sortir de la liste")
    func navigationBornee() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        // Deux projets + deux actions = quatre lignes.
        #expect(m.nombreDeLignes == 4)
        #expect(m.index == 0)
        m.precedent()
        #expect(m.index == 0, "↑ sur la première ligne n'en sort pas")
        for attendu in [1, 2, 3] {
            m.suivant()
            #expect(m.index == attendu)
        }
        m.suivant()
        #expect(m.index == 3, "↓ sur la dernière ligne n'en sort pas")
        m.precedent()
        #expect(m.index == 2)
    }

    @Test("la navigation ne bouge pas sur une palette vide")
    func navigationSansLigne() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "")
        m.suivant()
        #expect(m.index == 0)
        m.precedent()
        #expect(m.index == 0)
        #expect(m.selection == nil)
    }

    // MARK: - La ligne sélectionnée

    @Test("la sélection désigne le projet, puis les deux actions")
    func selection() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        #expect(m.projetSelectionne?.code == "P25_087")
        #expect(m.selection == .projet(0))
        m.suivant()
        #expect(m.projetSelectionne?.code == "P24_211")
        m.suivant()
        #expect(m.selection == .action(.creer))
        #expect(m.projetSelectionne == nil)
        m.suivant()
        #expect(m.selection == .action(.chercher))
    }

    @Test("un index hérité d'un terme plus large ne déborde pas")
    func indexRecale() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        m.suivant(); m.suivant(); m.suivant()
        #expect(m.index == 3)
        // « zzzzz » ne laisse que les deux actions : l'index doit suivre.
        m.recharger(projects: projets, terme: "zzzzz")
        #expect(m.index == 0)
        #expect(m.selection == .action(.creer))
    }

    // MARK: - ⌘↩ épingle

    @Test("⌘↩ bascule l'épinglage du projet sélectionné, dans les deux sens")
    func basculerEpinglage() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        let epingle = try #require(m.projets.first)
        #expect(epingle.code == "P25_087")
        #expect(epingle.pinned)

        #expect(m.basculerEpinglage()?.code == "P25_087")
        #expect(!epingle.pinned)
        #expect(m.basculerEpinglage()?.code == "P25_087")
        #expect(epingle.pinned)
    }

    @Test("⌘↩ ne fait rien sur une ligne d'action ni sur une palette vide")
    func basculerEpinglageSansProjet() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        m.suivant(); m.suivant()
        #expect(m.selection == .action(.creer))
        #expect(m.basculerEpinglage() == nil)

        let vide = modele(projets, "")
        #expect(vide.basculerEpinglage() == nil)
    }

    @Test("l'épinglage ne referme pas la palette : la liste garde son ordre")
    func epinglerNeReordonnePas() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "ged")
        _ = m.basculerEpinglage()
        // `recharger` n'est pas appelé : la ligne reste où elle est, sinon
        // celle qu'on vient d'épingler sauterait sous le curseur.
        #expect(m.projets.map(\.code) == ["P25_087", "P24_211"])
        #expect(m.index == 0)
    }

    // MARK: - La sous-ligne mono

    @Test("la sous-ligne du projet de la capture est celle de la capture")
    func sousLigneDeLaCapture() throws {
        let (_, projets) = try semis()
        let ged = try #require(projets.first { $0.code == "P25_087" })
        #expect(PaletteModel.sousLigne(ged) == "P25_087 · ASP · Build · PENVEN Yann")
    }

    @Test("la sous-ligne omet les segments vides")
    func sousLigneOmetLeVide() throws {
        let contexte = try contexteEnMemoire()
        let nu = Project(code: "T_001", name: "Projet nu", domain: "",
                         sponsor: "", projectType: "Métier", phase: "")
        contexte.insert(nu)
        #expect(PaletteModel.sousLigne(nu) == "T_001")

        let entite = Entity(name: "SI")
        contexte.insert(entite)
        nu.entity = entite
        #expect(PaletteModel.sousLigne(nu) == "T_001 · SI")

        nu.phase = "Run"
        #expect(PaletteModel.sousLigne(nu) == "T_001 · SI · Run")
    }

    @Test("la sous-ligne lit le chef de projet par la relation seule (D3)")
    func sousLigneLitLaRelation() throws {
        let contexte = try contexteEnMemoire()
        let p = Project(code: "T_002", name: "Projet", domain: "", sponsor: "",
                        projectType: "Métier", phase: "Build")
        // Le nom du xlsx est là, la relation manque : D3 dit que la relation
        // fait foi, donc le segment est **absent**.
        p.chefDeProjet = "NOMINE Laurent"
        contexte.insert(p)
        #expect(PaletteModel.sousLigne(p) == "T_002 · Build")

        let chef = Collaborator(name: "NOMINE Laurent")
        contexte.insert(chef)
        p.projectManager = chef
        #expect(PaletteModel.sousLigne(p) == "T_002 · Build · NOMINE Laurent")
    }

    @Test("une phase hors table s'affiche telle quelle, sans planter")
    func phaseHorsTable() throws {
        let contexte = try contexteEnMemoire()
        let p = Project(code: "T_003", name: "Projet", domain: "", sponsor: "",
                        projectType: "Métier", phase: "Réalisation")
        contexte.insert(p)
        #expect(PaletteModel.sousLigne(p) == "T_003 · Réalisation")
    }

    // MARK: - Les libellés, au mot près

    @Test("les libellés des deux actions citent le terme entre guillemets français")
    func libellesDesActions() {
        #expect(PaletteModel.libelle(.creer, terme: "ged") == "Créer un projet « ged »")
        #expect(PaletteModel.libelle(.chercher, terme: "ged")
                == "Chercher « ged » dans les CR")
        // Décision **D8** : les CR seulement. La maquette écrit « dans les CR
        // et mails » ; les mails viendront dans un chantier ultérieur.
        #expect(!PaletteModel.libelle(.chercher, terme: "ged").contains("mails"))
        // Le terme est rogné : « ged » et non «  ged  ».
        #expect(PaletteModel.libelle(.creer, terme: "  ged  ") == "Créer un projet « ged »")
    }

    @Test("les icônes des deux actions sont celles du handoff")
    func iconesDesActions() {
        #expect(PaletteModel.Action.creer.icone == "plus")
        #expect(PaletteModel.Action.chercher.icone == "line.3.horizontal")
    }

    @Test("le terme rendu par le modèle est rogné")
    func termeRogne() throws {
        let (_, projets) = try semis()
        let m = modele(projets, "  ged  ")
        #expect(m.terme == "ged")
        #expect(m.projets.count == 2)
    }
}
