import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le routeur de navigation de la fenêtre principale (décision **D0**).
///
/// Avant ce lot, la barre latérale était une liste de `NavigationLink` à
/// destination inline (`Views/Sidebar.swift`) : rien ne savait sélectionner un
/// écran par programme, or la palette, les Récents, le fil d'Ariane et
/// `SearchPopover` en ont tous besoin. Le routeur est un état, pas une vue —
/// donc il se teste sans en monter aucune, et il se teste **avant** elles.
@Suite("Routeur de navigation — D0")
@MainActor
struct MainRouterTests {

    /// Un `UserDefaults` jetable : les récents s'y écrivent, et deux exécutions
    /// de la suite ne doivent pas se marcher dessus.
    private func reglagesJetables() -> UserDefaults {
        let nom = "onetoone.tests.router.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: nom)!
        defaults.removePersistentDomain(forName: nom)
        return defaults
    }

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: - État initial

    @Test("Le routeur s'ouvre sur le tableau de bord, sans histoire")
    func etatInitial() {
        let routeur = MainRouter(defaults: reglagesJetables())
        #expect(routeur.route == .dashboard)
        #expect(routeur.history.isEmpty)
        #expect(routeur.pendingPaletteQuery == nil)
    }

    // MARK: - open / back

    @Test("Ouvrir un écran pousse le précédent dans l'histoire")
    func openPousseLePrecedent() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.open(.portfolio)
        #expect(routeur.route == .portfolio)
        #expect(routeur.history == [.dashboard])

        routeur.open(.atRisk)
        #expect(routeur.route == .atRisk)
        #expect(routeur.history == [.dashboard, .portfolio])
    }

    @Test("Revenir dépile l'histoire et n'y remet pas la route quittée")
    func backDepile() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.open(.portfolio)
        routeur.open(.atRisk)

        routeur.back()
        #expect(routeur.route == .portfolio)
        #expect(routeur.history == [.dashboard])

        routeur.back()
        #expect(routeur.route == .dashboard)
        #expect(routeur.history.isEmpty)
    }

    @Test("Revenir sans histoire ne change rien")
    func backSansHistoire() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.back()
        #expect(routeur.route == .dashboard)
        #expect(routeur.history.isEmpty)
    }

    /// Cliquer deux fois la même entrée de la barre latérale ne doit pas
    /// empiler deux fois le même écran : sinon « revenir » ne bougerait pas.
    @Test("Réouvrir l'écran courant n'empile rien")
    func memeRouteNEmpilePas() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.open(.portfolio)
        routeur.open(.portfolio)
        #expect(routeur.history == [.dashboard])
    }

    @Test("L'histoire est bornée à vingt écrans : le plus ancien tombe")
    func histoireBornee() {
        let routeur = MainRouter(defaults: reglagesJetables())
        #expect(MainRouter.historyLimit == 20)
        // 25 ouvertures distinctes : `searchReports` en donne autant qu'on veut.
        for index in 0..<25 { routeur.open(.searchReports("t\(index)")) }
        #expect(routeur.history.count == MainRouter.historyLimit)
        // Les vingt derniers écrans quittés, le plus ancien en tête.
        #expect(routeur.history.first == .searchReports("t4"))
        #expect(routeur.history.last == .searchReports("t23"))
        #expect(routeur.route == .searchReports("t24"))
    }

    // MARK: - Ouvrir un projet

    @Test("Ouvrir un projet route sur l'onglet Pilotage et l'inscrit aux récents")
    func openProject() throws {
        let contexte = try contexteEnMemoire()
        let reglages = reglagesJetables()
        let routeur = MainRouter(defaults: reglages)

        let projet = Project(code: "P25_193", name: "AE — Services IO / ALP",
                             domain: "ASP", phase: "Design")
        contexte.insert(projet)
        try contexte.save()

        routeur.openProject(projet)
        let id = try #require(projet.stableID)
        #expect(routeur.route == .project(id, .pilotage))
        #expect(routeur.recentProjectIDs == [id])
    }

    @Test("Ouvrir un projet sur un onglet donné respecte l'onglet")
    func openProjectOnglet() throws {
        let contexte = try contexteEnMemoire()
        let routeur = MainRouter(defaults: reglagesJetables())
        let projet = Project(code: "P25_112", name: "ASP — BLOOM", domain: "ASP", phase: "Build")
        contexte.insert(projet)
        try contexte.save()

        routeur.openProject(projet, tab: .actions)
        #expect(routeur.route == .project(try #require(projet.stableID), .actions))
    }

    /// Les projets créés avant l'ajout de `stableID` en portent `nil` :
    /// `ensuredStableID` doit le combler, sinon le routeur ne saurait pas
    /// désigner le projet et l'écran resterait vide.
    @Test("Un projet sans identifiant stable en reçoit un à l'ouverture")
    func openProjectBackfill() throws {
        let contexte = try contexteEnMemoire()
        let routeur = MainRouter(defaults: reglagesJetables())
        let projet = Project(code: "P24_211", name: "RH — Migration GED documentaire",
                             domain: "RH", phase: "Run")
        projet.stableID = nil
        contexte.insert(projet)
        try contexte.save()

        routeur.openProject(projet)
        let id = try #require(projet.stableID)
        #expect(routeur.route == .project(id, .pilotage))
    }

    @Test("Les récents gardent cinq projets, le dernier ouvert en tête")
    func recentsBornes() throws {
        let contexte = try contexteEnMemoire()
        let routeur = MainRouter(defaults: reglagesJetables())
        var projets: [Project] = []
        for index in 0..<7 {
            let projet = Project(code: "P25_0\(index)", name: "Projet \(index)",
                                 domain: "ASP", phase: "Build")
            contexte.insert(projet)
            projets.append(projet)
        }
        try contexte.save()

        for projet in projets { routeur.openProject(projet) }
        let attendus = try projets.suffix(5).reversed().map { try #require($0.stableID) }
        #expect(routeur.recentProjectIDs == attendus)
    }

    // MARK: - Terme en attente pour la palette (lot 3)

    /// `p1c` doit pouvoir ouvrir la palette sur le terme « ged » sans clic. Le
    /// routeur ne connaît pas la palette : il porte le terme, et le lot 3 le
    /// consommera.
    @Test("Le terme en attente de la palette se pose et se consomme une fois")
    func termeEnAttente() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.pendingPaletteQuery = "ged"
        #expect(routeur.consumePendingPaletteQuery() == "ged")
        #expect(routeur.pendingPaletteQuery == nil)
        #expect(routeur.consumePendingPaletteQuery() == nil)
    }

    // MARK: - Les routes elles-mêmes

    @Test("Deux routes de projet ne se confondent pas par leur seul onglet")
    func routesDistinctes() {
        let id = UUID()
        #expect(MainRoute.project(id, .pilotage) != MainRoute.project(id, .actions))
        #expect(MainRoute.project(id, .pilotage) == MainRoute.project(id, .pilotage))
        #expect(MainRoute.searchReports("ged") != MainRoute.searchReports("GED"))
    }

    @Test("Les six onglets de l'écran projet sont ceux de la capture 1d")
    func ongletsDeLaCapture() {
        #expect(ProjectTab.allCases.map(\.rawValue)
            == ["pilotage", "meetings", "actions", "mails", "documents", "fiche"])
        #expect(ProjectTab.allCases.map(\.label)
            == ["Pilotage", "Réunions & CR", "Actions", "Mails", "Documents", "Fiche complète"])
    }
}
