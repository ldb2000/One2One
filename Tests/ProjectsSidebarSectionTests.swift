import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import OneToOne

/// La section « Projets » de la barre latérale, variante **2a** du handoff.
///
/// Ce qui se teste d'une section de navigation, ce sont ses **mots** et ses
/// **destinations** : la capture `2a-sidebar-section-projets.png` écrit
/// « Portfolio », « À risque », « Mes réunions projets », « Actions projets »,
/// « ÉPINGLÉS » et « RÉCENTS », dans cet ordre, avec ces icônes-là. Un libellé
/// réécrit ou une entrée qui mène ailleurs ne change l'état d'aucun modèle : sans
/// ce test, rien ne bronche — même mécanique que `AppShortcutsTests`.
///
/// Depuis le lot 6, la suite tient aussi **l'absence** de l'arbre « Projets par
/// Entité » : la variante 2b n'était qu'un filet de sécurité pour la première
/// livraison, et la structure retenue est 2a.
@Suite("Section Projets de la barre latérale — 2a")
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

    // MARK: - La place de la section dans la barre, et ce qui n'y est plus

    /// `Sidebar.swift`, lu comme un texte.
    private func sourceDeLaBarre() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OneToOne/Views/Sidebar.swift")
        return try String(contentsOf: source, encoding: .utf8)
    }

    @Test("La section « Projets » précède les collaborateurs")
    func ordreDeLaBarreLaterale() throws {
        // Lecture des sources : l'ordre des lignes d'une `List` ne s'observe
        // pas depuis un test, et c'est pourtant lui que la capture 2a fixe —
        // section « Projets », **puis** « Collaborateurs ». Le lot 1 tenait
        // aussi la place de l'arbre par entité entre les deux ; le lot 6 l'a
        // retiré, et c'est `arbreParEntiteRetire` qui le tient désormais.
        let texte = try sourceDeLaBarre()
        let section = try #require(texte.range(of: "ProjectsSidebarSection("))
        let collaborateurs = try #require(texte.range(of: "isExpanded: $collabsExpanded"))
        #expect(section.lowerBound < collaborateurs.lowerBound,
                "la section « Projets » doit venir avant la section « Collaborateurs »")
    }

    @Test("L'arbre « Projets par Entité » n'existe plus dans la barre latérale")
    func arbreParEntiteRetire() throws {
        // La bascule en 2a est une **suppression** : ce qui la prouve, c'est
        // l'absence. Un test de lecture des sources, comme
        // `ordreDeLaBarreLaterale`, parce qu'aucun modèle ne change d'état
        // quand l'arbre revient — il reviendrait en silence.
        let texte = try sourceDeLaBarre()
        for interdit in ["Projets par Entité",
                         "sidebar.projectsExpanded",
                         "$projectsExpanded",
                         "expandedEntityNames",
                         "filteredProjectsFor(",
                         "filteredOrphanProjects",
                         "Sans Entité",
                         "moveProjects(",
                         "moveProjectsToNone(",
                         ".draggable(",
                         ".dropDestination("] {
            #expect(!texte.contains(interdit),
                    "« \(interdit) » appartient à l'arbre par entité, retiré au lot 6")
        }
    }

    @Test("Déplacer un projet vers une entité est une action en lot, plus un glisser-déposer")
    func deplacementParLaBarreEnLot() {
        // Le glisser-déposer projet → entité vivait dans l'arbre. Le handoff
        // §2a le reporte sur la sélection multiple : `ProjectBatchBar` porte
        // « Déplacer vers une entité », et la barre latérale comme le
        // Portfolio la montent (décision **D15**).
        #expect(ProjectBatchBar.deplacerVersEntite == "Déplacer vers une entité")
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

    // MARK: - Les récents des recettes `p2b` et `p2a`

    /// Les **deux** écrans de barre latérale préremplissent les récents : la
    /// capture `2a-sidebar-section-projets.png` montre la sous-section comme
    /// `2b`, et depuis le retrait de l'arbre au lot 6 c'est le même écran.
    @Test("Les deux écrans de barre latérale préremplissent les récents, dans l'ordre de la capture")
    func recentsDeRecette() {
        let attendus = ["P25_140", "P25_099", "P25_204"]
        #expect(RecetteScreen.sectionProjets.codesDeProjetsRecents == attendus)
        #expect(RecetteScreen.sectionProjetsFinale.codesDeProjetsRecents == attendus)
        for ecran in RecetteScreen.allCases
        where ecran != .sectionProjets && ecran != .sectionProjetsFinale {
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

    // MARK: - L'identité des lignes de projet (recette p1f)

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    private static var racineDuDepot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racineDuDepot.appendingPathComponent(chemin),
                     encoding: .utf8)) ?? ""
    }

    @Test("un même projet a une identité différente dans chaque sous-section")
    func identitesDistinctesParSection() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let bloom = try #require(projets.first { $0.code == "P25_112" })

        let epingle = SidebarProjectRow.lignes([bloom], section: PinnedProjectsList.libelle)
        let recent = SidebarProjectRow.lignes([bloom], section: RecentProjectsList.libelle)
        #expect(epingle[0].id != recent[0].id,
                "un projet épinglé **et** récent apparaît deux fois dans la même List")
        // Le projet, lui, est bien le même des deux côtés.
        #expect(epingle[0].projet.persistentModelID == recent[0].projet.persistentModelID)
    }

    @Test("deux projets d'une même section ont des identités différentes")
    func identitesDistinctesParProjet() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let lignes = SidebarProjectRow.lignes(Array(projets.prefix(5)),
                                              section: PinnedProjectsList.libelle)
        #expect(Set(lignes.map(\.id)).count == 5)
    }

    @Test("l'identité d'une ligne est stable d'un rendu à l'autre")
    func identiteStable() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let a = SidebarProjectRow.lignes(projets, section: PinnedProjectsList.libelle)
        let b = SidebarProjectRow.lignes(projets, section: PinnedProjectsList.libelle)
        #expect(a.map(\.id) == b.map(\.id),
                "une identité qui change à chaque rendu casserait la réutilisation des lignes")
    }

    @Test("les trois listes de projets de la barre latérale ont migré")
    func listesMigrees() {
        // Le défaut de la recette `p1f` : `ForEach(projets, id: \.persistentModelID)`
        // dans deux sous-sections d'une **même** `List`. Le garde-fou est une
        // lecture des sources, parce qu'une collision d'identité ne change
        // l'état d'aucun modèle — elle ne se voit qu'à l'écran.
        for fichier in ["OneToOne/Views/Sidebar/PinnedProjectsList.swift",
                        "OneToOne/Views/Sidebar/RecentProjectsList.swift"] {
            let source = Self.source(fichier)
            #expect(!source.isEmpty, "\(fichier) introuvable")
            #expect(!source.contains("ForEach(projets, id: \\.persistentModelID)"),
                    "\(fichier) identifie encore ses lignes par le seul projet")
            #expect(source.contains("SidebarProjectRow.lignes(projets, section:"))
        }
        let barre = Self.source("OneToOne/Views/Sidebar.swift")
        #expect(!barre.contains("ForEach(entityProjects) {"))
        #expect(!barre.contains("ForEach(orphans) {"))
        #expect(!barre.contains("ForEach(filteredArchivedProjects) {"))
        #expect(barre.contains("SidebarProjectRow.lignes("))
    }
}
