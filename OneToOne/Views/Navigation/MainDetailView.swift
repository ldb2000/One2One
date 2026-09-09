import SwiftUI
import SwiftData

/// La colonne de détail de la fenêtre principale : un `switch` sur
/// `MainRouter.route` (décision **D0**).
///
/// **C'est un routeur, comme `MeetingView`** : il monte un écran, il n'en
/// calcule aucun. Le Portfolio est livré (lot 2, `PortfolioView`), la
/// recherche dans les CR aussi (lot 3, `ReportSearchView`), l'écran projet à
/// six onglets également (lot 4, `ProjectScreen`), la vue « À risque » depuis
/// le lot 5 (`AtRiskView`) et, depuis le lot 6, les deux listes de projets —
/// `MeetingsListView` et `ActionsListView` montées avec `projetsSeulement`,
/// c'est-à-dire les listes **existantes filtrées** (§4 de la spec), et non
/// deux écrans de plus. Rien d'autre ne change de rendu : chaque entrée de la
/// barre latérale retrouve ici exactement la destination qu'elle avait en
/// `NavigationLink`.
struct MainDetailView: View {

    @Environment(MainRouter.self) private var router
    @Query private var projects: [Project]
    @Query private var collaborators: [Collaborator]
    @Query private var entities: [Entity]

    var body: some View {
        switch router.route ?? .dashboard {
        case .dashboard:
            DashboardView()
        case .assistant:
            ChatbotView()
        case .actions:
            ActionsListView()
        case .meetings:
            MeetingsListView()
        case .notes:
            AllNotesView()
        case .manager:
            ManagerTrackingView()
        case .collaborators:
            AllCollaboratorsView()
        case .settings:
            SettingsView()

        case .portfolio:
            PortfolioView()
        case .atRisk:
            // Lot 5 : les projets groupés par motif (capture 1f).
            AtRiskView()
        case .projectMeetings:
            // Lot 6 : la liste des réunions, restreinte à celles qui portent un
            // projet (§4 de la spec — « listes existantes filtrées »). Pas un
            // second écran : les filtres, la recherche et les gestes de
            // `MeetingsListView` restent tous disponibles.
            MeetingsListView(projetsSeulement: true)
        case .projectActions:
            // Idem pour les actions portées par un projet.
            ActionsListView(projetsSeulement: true)
        case .searchReports(let terme):
            // Lot 3 : l'écran de résultats de « Chercher « x » dans les CR »
            // (décision **D8**). Le terme est dans la route, donc l'écran se
            // reconstruit quand la palette en propose un autre.
            ReportSearchView(terme: terme)

        case .project(let id, let onglet):
            // Lot 4 : l'écran projet à six onglets (capture 1d).
            // `ProjectDetailView` n'a pas disparu — elle est son onglet
            // « Fiche complète ».
            if let projet = projects.first(where: { $0.stableID == id }) {
                ProjectScreen(project: projet, tab: onglet)
            } else {
                MainDetailIntrouvable(quoi: "Ce projet")
            }

        case .collaborator(let id):
            if let collaborateur = collaborators.first(where: { $0.stableID == id }) {
                CollaboratorFicheView(collaborator: collaborateur)
            } else {
                MainDetailIntrouvable(quoi: "Ce collaborateur")
            }

        case .entity(let id):
            if let entite = entities.first(where: { $0.persistentModelID == id }) {
                EntityDetailView(entity: entite)
            } else {
                MainDetailIntrouvable(quoi: "Cette entité")
            }
        }
    }
}

/// Une route qui désigne un objet disparu du store (projet supprimé, récent
/// périmé). Le routeur ne plante pas et ne redirige pas en silence : il le dit.
private struct MainDetailIntrouvable: View {
    let quoi: String

    var body: some View {
        Text("\(quoi) n'existe plus.")
            .font(.plexSans(12.5))
            .foregroundStyle(One2OneToken.ink4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(One2OneToken.bgApp)
    }
}
