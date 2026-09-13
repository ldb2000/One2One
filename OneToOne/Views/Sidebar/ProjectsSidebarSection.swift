import SwiftUI

/// Les quatre destinations de la section « Projets » de la barre latérale
/// (capture `2a-sidebar-section-projets.png`).
///
/// Un `enum` et non quatre lignes écrites à la main dans la vue : l'ordre, les
/// libellés, les icônes, les routes et les badges sont ce que la capture fixe,
/// et ce sont exactement les choses qu'on réécrit sans le vouloir. Rangés ici,
/// ils tiennent dans un test au mot près (`ProjectsSidebarSectionTests`), comme
/// la table des raccourcis de réunion.
enum ProjectsSidebarEntry: String, CaseIterable, Sendable {

    /// Le portefeuille complet — la capture `1a-portfolio.png` (lot 2).
    case portfolio
    /// Les projets en alerte, groupés par motif — `1f-vue-a-risque.png` (lot 5).
    case atRisk
    /// Les réunions dont `meeting.project != nil`.
    case projectMeetings
    /// Les actions ouvertes portées par un projet.
    case projectActions

    /// Le libellé, tel que la capture l'écrit.
    var libelle: String {
        switch self {
        case .portfolio:       return "Portfolio"
        case .atRisk:          return "À risque"
        case .projectMeetings: return "Mes réunions projets"
        case .projectActions:  return "Actions projets"
        }
    }

    /// Le symbole SF que le handoff nomme (« Assets ») — les glyphes de la
    /// maquette (`▦ ◈ ◷ ≣`) sont des placeholders.
    var icone: String {
        switch self {
        case .portfolio:       return "square.grid.3x3.fill"
        case .atRisk:          return "diamond.fill"
        case .projectMeetings: return "clock"
        case .projectActions:  return "line.3.horizontal"
        }
    }

    /// La route du lot 0 que l'entrée sélectionne.
    var route: MainRoute {
        switch self {
        case .portfolio:       return .portfolio
        case .atRisk:          return .atRisk
        case .projectMeetings: return .projectMeetings
        case .projectActions:  return .projectActions
        }
    }

    /// La teinte de l'icône et du badge, ou `nil` pour l'encre courante.
    /// Seule « À risque » est teintée, en `report` — c'est le seul signal de
    /// la section, et la capture le montre sur l'icône **et** sur le compteur.
    var teinte: Color? {
        self == .atRisk ? One2OneToken.report : nil
    }

    /// Le compteur affiché à droite, ou `nil`.
    ///
    /// Zéro n'affiche rien : un « 0 » à côté de « À risque » se lit comme une
    /// alerte alors qu'il dit le contraire. « Mes réunions projets » n'en porte
    /// pas — la capture non plus, et le nombre de réunions d'un portefeuille ne
    /// veut rien dire sans période.
    func badge(_ comptes: SidebarProjectCounts) -> String? {
        let valeur: Int
        switch self {
        case .portfolio:       valeur = comptes.active
        case .atRisk:          valeur = comptes.atRisk
        case .projectActions:  valeur = comptes.openProjectActions
        case .projectMeetings: return nil
        }
        return valeur > 0 ? "\(valeur)" : nil
    }
}

/// La section « Projets » de la barre latérale — variante **2a** du handoff,
/// la structure retenue : la section est **le** point d'accès aux projets.
///
/// **Un point d'accès, pas un catalogue.** Quatre destinations, les projets
/// épinglés, les derniers ouverts. Retrouver un projet par son nom est le
/// travail du Portfolio (lot 2) et de la palette `⌘K` (lot 3) ; l'arbre par
/// entité, conservé replié pendant la variante 2b, a été retiré au lot 6.
///
/// **Rien n'est calculé ici** (décision **D11**) : les compteurs viennent de
/// `SidebarProjectCounts`, les épinglés de `PinnedProjectsList`, les récents de
/// `RecentProjectsList` — trois fonctions pures testées avant cette vue. La
/// vue ne fait qu'assembler des lignes et poser des jetons.
struct ProjectsSidebarSection: View {

    /// Le titre de la section, tel que la capture l'écrit.
    static let titre = "Projets"

    /// La clé de dépliage de la section (décision **D5**). L'arbre par entité
    /// avait la sienne ; elle est partie avec lui au lot 6, et la valeur
    /// éventuellement persistée chez un utilisateur n'a plus de lecteur.
    static let expandedKey = "sidebar.projectsSectionExpanded"

    /// Dépliée par défaut : c'est la navigation projets, elle ne se cache pas.
    static let deplieParDefaut = true

    /// Corps d'une entrée (handoff §Typographie : corps 13 pt).
    static let tailleEntree: CGFloat = 13
    /// Compteur mono à droite de l'entrée.
    static let tailleBadge: CGFloat = 11
    /// Dimensionnement des symboles SF de la section.
    static let tailleIcone: CGFloat = 12
    /// Décalage des lignes de projet sous leur sous-titre.
    static let indentation: CGFloat = 10

    /// Tous les projets — le filtrage vit dans les fonctions pures.
    let projets: [Project]

    /// Les trois compteurs, calculés par l'appelant.
    let comptes: SidebarProjectCounts

    /// Le terme de recherche debouncé de la barre latérale. Non vide, il filtre
    /// les épinglés et les récents comme il filtre déjà les collaborateurs.
    let recherche: String

    /// La route affichée, pour la surbrillance des entrées.
    let routeCourante: MainRoute?

    /// Les notes d'un projet — la barre latérale les a déjà en main, et
    /// `Meeting` ne se remonte pas depuis `Project`.
    let notesDuProjet: (Project) -> [Meeting]

    /// Ouvrir un projet (épinglé ou récent). C'est `MainRouter.openProject`,
    /// qui route **et** inscrit aux récents.
    let ouvrir: (Project) -> Void

    @AppStorage(ProjectsSidebarSection.expandedKey)
    private var deplie: Bool = ProjectsSidebarSection.deplieParDefaut

    /// Les récents sont lus **des réglages** et non du routeur : la liste du
    /// routeur n'est pas observable, et la section doit se redessiner dès qu'un
    /// projet est ouvert ailleurs (palette, recherche du menu système).
    @AppStorage(RecentProjects.key)
    private var recentsBruts: String = ""

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $deplie) {
                ForEach(ProjectsSidebarEntry.allCases, id: \.self) { entree in
                    ligne(entree)
                }
                PinnedProjectsList(projets: epingles,
                                   indentation: Self.indentation,
                                   ouvrir: ouvrir)
                RecentProjectsList(projets: recents,
                                   indentation: Self.indentation,
                                   ouvrir: ouvrir)
            } label: {
                Text(Self.titre)
                    .font(.plexSans(Self.tailleEntree, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
            }
        }
    }

    // MARK: - Les données de la section

    private var epingles: [Project] {
        PinnedProjectsList.epingles(among: projets,
                                    query: recherche,
                                    notes: notesDuProjet)
    }

    private var recents: [Project] {
        RecentProjectsList.resolve(ids: RecentProjects.ids(from: recentsBruts),
                                   among: projets,
                                   query: recherche,
                                   notes: notesDuProjet)
    }

    // MARK: - Une entrée

    @ViewBuilder
    private func ligne(_ entree: ProjectsSidebarEntry) -> some View {
        let selectionnee = (routeCourante == entree.route)
        HStack(spacing: 6) {
            Image(systemName: entree.icone)
                .font(.system(size: Self.tailleIcone))
                .foregroundStyle(teinte(entree, selectionnee: selectionnee))
                .frame(width: 18, alignment: .center)
            Text(entree.libelle)
                .font(.plexSans(Self.tailleEntree))
                .foregroundStyle(selectionnee ? One2OneToken.onFilledButton : One2OneToken.ink1)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let badge = entree.badge(comptes) {
                Text(badge)
                    .font(.plexMono(Self.tailleBadge, .medium))
                    .foregroundStyle(teinte(entree, selectionnee: selectionnee))
            }
        }
        .tag(entree.route)
        .listRowBackground(fondDeSelection(selectionnee))
    }

    /// L'encre de l'icône **et** du compteur d'une entrée — la capture les
    /// montre de la même teinte, y compris le `report` de « À risque ».
    ///
    /// Sélectionnée, la ligne est peinte en `action` : tout y passe en blanc,
    /// où `report` serait illisible. Sinon `ink4`, et non `inkMuted` : à 11 pt,
    /// `inkMuted` n'atteint pas 4,5:1 (règle §1.2 — « jamais sous 11,5 px »).
    private func teinte(_ entree: ProjectsSidebarEntry, selectionnee: Bool) -> Color {
        if selectionnee { return One2OneToken.onFilledButton }
        return entree.teinte ?? One2OneToken.ink4
    }

    /// Le fond de l'entrée sélectionnée : `action`, rayon 6, texte blanc — ce
    /// que la capture montre sur « Portfolio ». Posé en `listRowBackground`
    /// pour que ce soit **le jeton** qui peigne la ligne, et non la couleur
    /// d'accent du système.
    @ViewBuilder
    private func fondDeSelection(_ selectionnee: Bool) -> some View {
        if selectionnee {
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .fill(One2OneToken.action)
        } else {
            Color.clear
        }
    }
}
