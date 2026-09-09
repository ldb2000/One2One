import SwiftUI
import SwiftData

/// La colonne de détail de la fenêtre principale : un `switch` sur
/// `MainRouter.route` (décision **D0**).
///
/// **C'est un routeur, comme `MeetingView`** : il monte un écran, il n'en
/// calcule aucun. Le Portfolio est livré (lot 2, `PortfolioView`), la
/// recherche dans les CR aussi (lot 3, `ReportSearchView`), l'écran projet à
/// six onglets également (lot 4, `ProjectScreen`) et la vue « À risque »
/// depuis le lot 5 (`AtRiskView`) ; les deux listes de projets restantes
/// affichent encore une invite sobre que le lot 6 remplacera. Rien d'autre ne change
/// de rendu : chaque entrée de la barre latérale retrouve ici exactement la
/// destination qu'elle avait en `NavigationLink`.
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
            MainDetailPlaceholder(titre: "Mes réunions projets",
                                  detail: "les réunions de projet, filtrées depuis la liste existante")
        case .projectActions:
            MainDetailPlaceholder(titre: "Actions projets",
                                  detail: "les actions de projet, filtrées depuis la liste existante")
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

/// L'invite d'un écran que la refonte livrera plus tard.
///
/// Sobre exprès : elle n'a pas à ressembler à un écran vide de l'application,
/// et elle disparaîtra lot par lot. Aux jetons `One2OneToken` et à la fonte
/// Plex, comme tout ce qui vit sous `Views/Navigation/` (décision **D17**).
private struct MainDetailPlaceholder: View {
    let titre: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre)
                .font(.plexSans(17, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("Bientôt : \(detail).")
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(One2OneToken.cardPaddingMax)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(One2OneToken.bgApp)
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
