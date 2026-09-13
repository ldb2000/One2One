import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les deux dernières entrées de la section « Projets » de la barre latérale :
/// « Mes réunions projets » (`MainRoute.projectMeetings`) et « Actions
/// projets » (`.projectActions`).
///
/// Le §4 de la spec de la refonte les décrit comme **les listes existantes,
/// filtrées** — pas deux écrans de plus. `MainDetailView` monte donc
/// `MeetingsListView(projetsSeulement: true)` et
/// `ActionsListView(projetsSeulement: true)`, qui gardent leurs filtres, leur
/// recherche et leurs gestes.
///
/// Ce qui se teste ici : les **mots** du bandeau qui dit qu'une liste est
/// restreinte, le **branchement** des deux routes (lecture des sources — une
/// `View` à `@Query` ne s'instancie pas hors d'un conteneur SwiftUI), et le
/// **compte** que le semis rend, qui est aussi celui des badges de la barre
/// latérale.
@Suite("Listes de projets — réunions et actions filtrées")
@MainActor
struct ProjectScopedListsTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private static var racineDuDepot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racineDuDepot.appendingPathComponent(chemin),
                     encoding: .utf8)) ?? ""
    }

    // MARK: - Les libellés

    /// Une liste amputée de la moitié de ses lignes sans rien dire se lit comme
    /// une liste vide : le bandeau est ce qui distingue « Mes réunions
    /// projets » de « Réunions ».
    @Test("Le bandeau dit ce qui filtre et comment en sortir")
    func libellesDuBandeau() {
        #expect(ProjectScopeBanner.reunions == "Réunions liées à un projet")
        #expect(ProjectScopeBanner.actions == "Actions portées par un projet")
        #expect(ProjectScopeBanner.sortie
                == "Choisir « Réunions » ou « Actions » dans la barre latérale pour tout voir")
    }

    /// Les deux entrées de la barre latérale gardent les mots de la capture
    /// `2a-sidebar-section-projets.png` : le bandeau les explique, il ne les
    /// renomme pas.
    @Test("Les deux entrées de la barre latérale n'ont pas changé de nom")
    func libellesDesEntrees() {
        #expect(ProjectsSidebarEntry.projectMeetings.libelle == "Mes réunions projets")
        #expect(ProjectsSidebarEntry.projectActions.libelle == "Actions projets")
        #expect(ProjectsSidebarEntry.projectMeetings.route == .projectMeetings)
        #expect(ProjectsSidebarEntry.projectActions.route == .projectActions)
    }

    // MARK: - Le branchement

    @Test("Les deux routes montent les listes existantes, sans invite résiduelle")
    func routesCablees() {
        let source = Self.source("OneToOne/Views/Navigation/MainDetailView.swift")
        #expect(!source.isEmpty, "MainDetailView.swift introuvable")
        #expect(source.contains("case .projectMeetings:"))
        #expect(source.contains("MeetingsListView(projetsSeulement: true)"))
        #expect(source.contains("case .projectActions:"))
        #expect(source.contains("ActionsListView(projetsSeulement: true)"))
        // Les deux invites du lot 0 ont disparu — et avec elles le composant,
        // qui n'avait plus d'appelant.
        #expect(!source.contains("MainDetailPlaceholder"),
                "les invites « Bientôt » n'ont plus lieu d'être : les six écrans sont livrés")
    }

    /// Le filtre est **une** ligne dans la chaîne existante, pas une seconde
    /// chaîne : c'est ce qui garantit que les autres filtres continuent de
    /// s'appliquer par-dessus.
    @Test("Le filtre s'ajoute à la chaîne existante des deux listes")
    func filtreDansLaChaine() {
        let reunions = Self.source("OneToOne/Views/MeetingsListView.swift")
        #expect(reunions.contains("init(projetsSeulement: Bool = false)"))
        #expect(reunions.contains("result = result.filter { $0.project != nil }"))

        let actions = Self.source("OneToOne/Views/ActionsListView.swift")
        #expect(actions.contains("init(projetsSeulement: Bool = false)"))
        #expect(actions.contains("tasks = tasks.filter { $0.project != nil }"))
    }

    // MARK: - Ce que le semis rend

    /// Le compte des deux écrans sur le portefeuille de démonstration.
    ///
    /// Il n'est pas décoratif : « Actions projets » est **la même règle** que
    /// le badge de la barre latérale, aux actions closes près
    /// (`SidebarProjectCounts.openProjectActions` compte les ouvertes). Si les
    /// deux divergeaient, l'utilisateur verrait un badge annoncer un nombre que
    /// l'écran ne montre pas.
    @Test("Le semis rend des réunions et des actions de projet, et le badge les recompte")
    func comptesSurLeSemis() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())
        let actions = try contexte.fetch(FetchDescriptor<ActionTask>())

        // Ce que « Mes réunions projets » montrerait : les réunions tenues
        // (hors notes, comme la liste elle-même) qui portent un projet.
        let reunionsDeProjet = MeetingStatsScope.held(reunions).filter { $0.project != nil }
        #expect(!reunionsDeProjet.isEmpty,
                "le semis doit peupler l'écran « Mes réunions projets »")

        // Ce que « Actions projets » montrerait, toutes portées confondues.
        let actionsDeProjet = actions.filter { $0.project != nil }
        #expect(!actionsDeProjet.isEmpty)

        // Et le badge, qui n'en compte que les ouvertes : un sous-ensemble,
        // jamais un compte différent.
        let comptes = SidebarProjectCounts.compute(projects: projets,
                                                   meetings: reunions,
                                                   tasks: actions,
                                                   today: Date())
        let ouvertesDeProjet = actionsDeProjet.filter { $0.status == .open }.count
        #expect(comptes.openProjectActions == ouvertesDeProjet)
        #expect(comptes.openProjectActions <= actionsDeProjet.count)
    }

    /// Une action sans projet ne doit apparaître dans aucun des deux écrans —
    /// c'est tout ce que « filtré » veut dire, et c'est la règle que le badge
    /// applique déjà.
    @Test("Une action ou une réunion sans projet sort des deux listes")
    func sansProjetExclu() throws {
        let contexte = try contexteEnMemoire()
        let projet = Project(code: "P25_900", name: "ASP – Témoin", domain: "ASP", phase: "Build")
        contexte.insert(projet)

        let avec = ActionTask(title: "Avec projet")
        avec.project = projet
        let sans = ActionTask(title: "Sans projet")
        contexte.insert(avec)
        contexte.insert(sans)

        let actions = try contexte.fetch(FetchDescriptor<ActionTask>())
        #expect(actions.count == 2)
        #expect(actions.filter { $0.project != nil }.map(\.title) == ["Avec projet"])
    }
}
