import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les trois badges de la section « Projets » de la barre latérale — « 62 »,
/// « 7 » et « 23 » de la capture `2b-sidebar-variante-arbre-replie.png`.
///
/// Ils sont testés **sur le semis du portefeuille**, pas sur trois projets
/// fabriqués pour l'occasion : c'est ce store-là que la recette photographie,
/// et un compteur juste sur un cas d'école mais faux sur soixante-seize
/// projets ne vaudrait rien. Les motifs « à risque » sont en plus vérifiés un
/// par un, parce que le lot 5 remplacera ce stub par `AtRiskBuilder` et que la
/// bascule devra rendre exactement les mêmes chiffres.
@Suite("Compteurs de la section Projets")
@MainActor
struct SidebarProjectCountsTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func comptes(_ contexte: ModelContext,
                         today: Date = Date()) throws -> SidebarProjectCounts {
        SidebarProjectCounts.compute(
            projects: try contexte.fetch(FetchDescriptor<Project>()),
            meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
            tasks: try contexte.fetch(FetchDescriptor<ActionTask>()),
            today: today
        )
    }

    private func projet(_ contexte: ModelContext,
                        code: String = "P25_001",
                        sponsor: String = "Direction ASP",
                        statut: String = "Green",
                        chefLie: Bool = true) -> Project {
        let p = Project(code: code, name: "Projet \(code)", domain: "ASP",
                        sponsor: sponsor, projectType: "Métier", phase: "Build",
                        status: statut)
        contexte.insert(p)
        if chefLie {
            let chef = Collaborator(name: "RIGAUT Manuel", role: "Chef de projet")
            contexte.insert(chef)
            p.projectManager = chef
        }
        return p
    }

    // MARK: - Sur le semis, les trois chiffres de la capture

    @Test("Le semis du portefeuille donne 62 actifs, 7 à risque et 23 actions ouvertes")
    func chiffresDeLaCapture() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let c = try comptes(contexte)
        #expect(c.active == 62)
        #expect(c.atRisk == 7)
        #expect(c.openProjectActions == 23)
    }

    @Test("Le semis deux fois ne double aucun compteur")
    func idempotence() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let premier = try comptes(contexte)
        RefonteDemoSeed.seedPortfolio(in: contexte)
        #expect(try comptes(contexte) == premier)
    }

    @Test("Un store vide ne rend que des zéros")
    func storeVide() throws {
        let contexte = try contexteEnMemoire()
        #expect(try comptes(contexte) == SidebarProjectCounts.zero)
    }

    // MARK: - « Actifs »

    @Test("« Actifs » compte les projets non archivés, archivés exclus")
    func actifs() throws {
        let contexte = try contexteEnMemoire()
        projet(contexte, code: "P25_001")
        let archive = projet(contexte, code: "P25_002")
        archive.isArchived = true
        #expect(try comptes(contexte).active == 1)
    }

    // MARK: - « Actions projets »

    @Test("« Actions projets » ne compte que les actions ouvertes portées par un projet")
    func actionsOuvertesDeProjet() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)

        let ouverte = ActionTask(title: "Rédiger le DAT")
        contexte.insert(ouverte)
        ouverte.project = p

        let terminee = ActionTask(title: "Chiffrer la reprise")
        contexte.insert(terminee)
        terminee.project = p
        terminee.status = .done

        let abandonnee = ActionTask(title: "Planifier l’atelier")
        contexte.insert(abandonnee)
        abandonnee.project = p
        abandonnee.status = .dropped

        let sansProjet = ActionTask(title: "Appeler l’éditeur")
        contexte.insert(sansProjet)

        #expect(try comptes(contexte).openProjectActions == 1)
    }

    // MARK: - « À risque » : les trois motifs du handoff

    @Test("Motif 1 — un jalon échu et non fait met le projet à risque")
    func motifJalonDepasse() {
        let aujourdHui = Date()
        #expect(SidebarProjectCounts.jalonDepasse(
            jalons: [(dueAt: aujourdHui.addingTimeInterval(-6 * 86_400), state: .planned)],
            today: aujourdHui))
        // Fait : ce n'est plus un risque, même échu.
        #expect(!SidebarProjectCounts.jalonDepasse(
            jalons: [(dueAt: aujourdHui.addingTimeInterval(-6 * 86_400), state: .done)],
            today: aujourdHui))
        // À venir : pas un risque.
        #expect(!SidebarProjectCounts.jalonDepasse(
            jalons: [(dueAt: aujourdHui.addingTimeInterval(6 * 86_400), state: .planned)],
            today: aujourdHui))
        // Marqué « en retard » : risque, quelle que soit l'échéance.
        #expect(SidebarProjectCounts.jalonDepasse(
            jalons: [(dueAt: aujourdHui.addingTimeInterval(6 * 86_400), state: .late)],
            today: aujourdHui))
        // Sans échéance ni retard déclaré, rien à dire.
        #expect(!SidebarProjectCounts.jalonDepasse(
            jalons: [(dueAt: nil, state: .inProgress)], today: aujourdHui))
        #expect(!SidebarProjectCounts.jalonDepasse(jalons: [], today: aujourdHui))
    }

    @Test("Motif 2 — aucune réunion tenue depuis trente jours")
    func motifSansReunion() {
        let aujourdHui = Date()
        #expect(SidebarProjectCounts.sansReunionRecente(nil, today: aujourdHui))
        #expect(SidebarProjectCounts.sansReunionRecente(
            aujourdHui.addingTimeInterval(-34 * 86_400), today: aujourdHui))
        #expect(!SidebarProjectCounts.sansReunionRecente(
            aujourdHui.addingTimeInterval(-26 * 86_400), today: aujourdHui))
        #expect(SidebarProjectCounts.sansReunionDepuis == 30)
    }

    @Test("Motif 3 — fiche incomplète : sponsor vide, chef non lié, statut inconnu")
    func motifFicheIncomplete() throws {
        let contexte = try contexteEnMemoire()
        #expect(SidebarProjectCounts.ficheIncomplete(
            projet(contexte, code: "P25_001", sponsor: "")))
        // D3 : la **relation** fait foi — le nom du xlsx ne suffit pas.
        let sansRelation = projet(contexte, code: "P25_002", chefLie: false)
        sansRelation.chefDeProjet = "NOMINE Laurent"
        #expect(SidebarProjectCounts.ficheIncomplete(sansRelation))
        #expect(SidebarProjectCounts.ficheIncomplete(
            projet(contexte, code: "P25_003", statut: "Unknown")))
        #expect(SidebarProjectCounts.ficheIncomplete(
            projet(contexte, code: "P25_004", statut: "")))
        // Complète : rien ne manque.
        #expect(!SidebarProjectCounts.ficheIncomplete(projet(contexte, code: "P25_005")))
    }

    @Test("Un projet cumulant deux motifs n'est compté qu'une fois")
    func compteUneSeuleFois() throws {
        let contexte = try contexteEnMemoire()
        // Sponsor vide **et** aucune réunion : deux motifs, un projet.
        projet(contexte, code: "P25_001", sponsor: "")
        #expect(try comptes(contexte).atRisk == 1)
    }

    @Test("Un projet archivé n'est jamais à risque")
    func archiveJamaisARisque() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "P25_001", sponsor: "")
        p.isArchived = true
        #expect(try comptes(contexte).atRisk == 0)
    }

    @Test("Une note ne compte pas comme une réunion tenue")
    func laNoteNestPasUneReunion() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "P25_001")
        let note = Meeting(title: "Note du jour", date: Date(), notes: "")
        note.kind = .note
        contexte.insert(note)
        note.project = p
        // Le projet est complet et sans jalon : seul le motif « sans réunion »
        // peut le ranger à risque, et une note ne l'en sort pas.
        #expect(try comptes(contexte).atRisk == 1)
    }

    @Test("Une réunion à venir ne compte pas comme tenue")
    func reunionAVenir() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "P25_001")
        let future = Meeting(title: "COPIL de novembre",
                             date: Date().addingTimeInterval(10 * 86_400), notes: "")
        future.kind = .project
        contexte.insert(future)
        future.project = p
        #expect(try comptes(contexte).atRisk == 1)
    }
}
