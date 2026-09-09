import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import OneToOne

/// La section « Projets » de la barre latérale, variante **2b** du handoff.
///
/// Ce qui se teste d'une section de navigation, ce sont ses **mots** et ses
/// **destinations** : la capture `2b-sidebar-variante-arbre-replie.png` écrit
/// « Portfolio », « À risque », « Mes réunions projets », « Actions projets »,
/// « ÉPINGLÉS » et « RÉCENTS », dans cet ordre, avec ces icônes-là. Un libellé
/// réécrit ou une entrée qui mène ailleurs ne change l'état d'aucun modèle : sans
/// ce test, rien ne bronche — même mécanique que `MeetingShortcutsTests`.
@Suite("Section Projets de la barre latérale — 2b")
@MainActor
struct ProjectsSidebarSectionTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: - Les quatre entrées

    @Test("Les quatre entrées sont dans l'ordre de la capture")
    func ordreDesEntrees() {
        #expect(ProjectsSidebarEntry.allCases.map(\.libelle)
                == ["Portfolio", "À risque", "Mes réunions projets", "Actions projets"])
    }

    @Test("Les icônes sont celles que le handoff nomme, pas les glyphes de la maquette")
    func icones() {
        #expect(ProjectsSidebarEntry.allCases.map(\.icone)
                == ["square.grid.3x3.fill", "diamond.fill", "clock", "line.3.horizontal"])
    }

    @Test("Chaque entrée mène à la route du lot 0")
    func routes() {
        #expect(ProjectsSidebarEntry.portfolio.route == .portfolio)
        #expect(ProjectsSidebarEntry.atRisk.route == .atRisk)
        #expect(ProjectsSidebarEntry.projectMeetings.route == .projectMeetings)
        #expect(ProjectsSidebarEntry.projectActions.route == .projectActions)
        // Quatre entrées, quatre routes distinctes.
        #expect(Set(ProjectsSidebarEntry.allCases.map(\.route)).count == 4)
    }

    @Test("Seule « À risque » est teintée, en `report`")
    func teintes() {
        #expect(ProjectsSidebarEntry.atRisk.teinte == One2OneToken.report)
        #expect(ProjectsSidebarEntry.portfolio.teinte == nil)
        #expect(ProjectsSidebarEntry.projectMeetings.teinte == nil)
        #expect(ProjectsSidebarEntry.projectActions.teinte == nil)
    }

    // MARK: - Les badges

    @Test("Les badges de la capture : 62 sur Portfolio, 7 sur À risque, 23 sur Actions")
    func badges() {
        let comptes = SidebarProjectCounts(active: 62, atRisk: 7, openProjectActions: 23)
        #expect(ProjectsSidebarEntry.portfolio.badge(comptes) == "62")
        #expect(ProjectsSidebarEntry.atRisk.badge(comptes) == "7")
        #expect(ProjectsSidebarEntry.projectActions.badge(comptes) == "23")
        // « Mes réunions projets » n'en porte pas — la capture non plus.
        #expect(ProjectsSidebarEntry.projectMeetings.badge(comptes) == nil)
    }

    @Test("Un compteur à zéro n'affiche pas de badge")
    func badgeZero() {
        let comptes = SidebarProjectCounts.zero
        #expect(ProjectsSidebarEntry.allCases.allSatisfy { $0.badge(comptes) == nil })
    }

    // MARK: - Les deux sous-sections

    @Test("Les sous-titres sont écrits en majuscules, au mot près")
    func sousTitres() {
        #expect(ProjectsSidebarSection.titre == "Projets")
        #expect(PinnedProjectsList.libelle == "ÉPINGLÉS")
        #expect(RecentProjectsList.libelle == "RÉCENTS")
    }

    @Test("La clé de dépliage est celle de D5, dépliée par défaut")
    func clefDeDepliage() {
        #expect(ProjectsSidebarSection.expandedKey == "sidebar.projectsSectionExpanded")
        #expect(ProjectsSidebarSection.deplieParDefaut)
    }

    @Test("La sous-ligne de l'arbre par entité est celle de la capture")
    func sousLigneDeLArbre() {
        #expect(ProjectsSidebarSection.sousLigneArbre(entites: 8) == "8 entités · replié par défaut")
        #expect(ProjectsSidebarSection.sousLigneArbre(entites: 1) == "1 entité · replié par défaut")
        #expect(ProjectsSidebarSection.sousLigneArbre(entites: 0) == "0 entité · replié par défaut")
    }

    // MARK: - Épinglés

    @Test("Les épinglés du semis sont les trois projets de la capture")
    func epinglesDuSemis() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let tous = try contexte.fetch(FetchDescriptor<Project>())
        let epingles = PinnedProjectsList.epingles(among: tous)
        #expect(epingles.count == 3)
        #expect(Set(epingles.map(\.code)) == ["P25_112", "P25_193", "P25_087"])
    }

    @Test("Un projet archivé n'apparaît pas dans les épinglés")
    func epinglesSansArchive() throws {
        let contexte = try contexteEnMemoire()
        let actif = Project(code: "P25_001", name: "ASP – BLOOM", domain: "ASP", phase: "Build")
        actif.pinned = true
        let archive = Project(code: "P25_002", name: "ASP – Ancien", domain: "ASP", phase: "Run")
        archive.pinned = true
        archive.isArchived = true
        contexte.insert(actif)
        contexte.insert(archive)
        #expect(PinnedProjectsList.epingles(among: [actif, archive]).map(\.code) == ["P25_001"])
    }

    @Test("Les épinglés sont classés par nom — ordre stable d'un lancement à l'autre")
    func epinglesTriesParNom() {
        let b = Project(code: "P25_002", name: "BLOOM", domain: "ASP", phase: "Build")
        let a = Project(code: "P25_001", name: "ANNUAIRE", domain: "ASP", phase: "Build")
        b.pinned = true
        a.pinned = true
        #expect(PinnedProjectsList.epingles(among: [b, a]).map(\.code) == ["P25_001", "P25_002"])
    }

    @Test("Une recherche en cours filtre aussi les épinglés")
    func epinglesFiltresParLaRecherche() {
        let bloom = Project(code: "P25_001", name: "ASP – BLOOM", domain: "ASP", phase: "Build")
        let ged = Project(code: "P25_002", name: "ASP – Installation nouvelle GED",
                          domain: "ASP", phase: "Build")
        bloom.pinned = true
        ged.pinned = true
        #expect(PinnedProjectsList.epingles(among: [bloom, ged], query: "ged").map(\.code)
                == ["P25_002"])
    }

    // MARK: - Récents

    @Test("Les récents sont résolus par `stableID`, dans l'ordre de la liste")
    func recentsResolus() {
        let a = Project(code: "P25_140", name: "ASP – Sécurisation des flux inter-sites",
                        domain: "ASP", phase: "Cadrage")
        let b = Project(code: "P25_099", name: "ASP – Obsolescence de la VM applicative",
                        domain: "ASP", phase: "Build")
        let c = Project(code: "P25_204", name: "RH – TIME & APPLI", domain: "RH", phase: "Build")
        let ids = [a, b, c].map { $0.stableID! }
        #expect(RecentProjectsList.resolve(ids: ids, among: [c, b, a]).map(\.code)
                == ["P25_140", "P25_099", "P25_204"])
    }

    @Test("Un identifiant récent qui ne désigne plus rien est ignoré, sans trouer la liste")
    func recentsIntrouvables() {
        let a = Project(code: "P25_140", name: "ASP – Sécurisation", domain: "ASP", phase: "Cadrage")
        let b = Project(code: "P25_099", name: "ASP – Obsolescence", domain: "ASP", phase: "Build")
        let ids = [a.stableID!, UUID(), b.stableID!]
        #expect(RecentProjectsList.resolve(ids: ids, among: [a, b]).map(\.code)
                == ["P25_140", "P25_099"])
    }

    @Test("Une recherche en cours filtre aussi les récents")
    func recentsFiltresParLaRecherche() {
        let a = Project(code: "P25_140", name: "ASP – Sécurisation des flux", domain: "ASP",
                        phase: "Cadrage")
        let b = Project(code: "P25_204", name: "RH – TIME & APPLI", domain: "RH", phase: "Build")
        let ids = [a.stableID!, b.stableID!]
        #expect(RecentProjectsList.resolve(ids: ids, among: [a, b], query: "time").map(\.code)
                == ["P25_204"])
    }

    @Test("La barre latérale n'affiche que trois récents, même si la file en retient cinq")
    func recentsBornesATrois() {
        let projets = (1...5).map {
            Project(code: "P25_00\($0)", name: "Projet \($0)", domain: "ASP", phase: "Build")
        }
        let ids = projets.map { $0.stableID! }
        #expect(RecentProjects.max == 5)
        #expect(RecentProjectsList.maxAffiches == 3)
        #expect(RecentProjectsList.resolve(ids: ids, among: projets).map(\.code)
                == ["P25_001", "P25_002", "P25_003"])
    }

    // MARK: - Les récents de la recette `p2b`

    @Test("L'écran `p2b` est le seul à préremplir les récents, dans l'ordre de la capture")
    func recentsDeRecette() {
        #expect(RecetteScreen.sectionProjets.codesDeProjetsRecents
                == ["P25_140", "P25_099", "P25_204"])
        for ecran in RecetteScreen.allCases where ecran != .sectionProjets {
            #expect(ecran.codesDeProjetsRecents.isEmpty,
                    "\(ecran.rawValue) prérempli des récents")
        }
    }

    @Test("Les trois codes récents désignent les projets que la capture nomme")
    func recentsDeRecetteExistent() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let tous = try contexte.fetch(FetchDescriptor<Project>())
        let noms = RefonteDemoSeed.portfolioRecentProjectCodes.map { code in
            tous.first { $0.code == code }?.name
        }
        #expect(noms == ["ASP – Sécurisation des flux inter-sites",
                         "ASP – Obsolescence de la VM applicative",
                         "RH – TIME & APPLI"])
    }
}
