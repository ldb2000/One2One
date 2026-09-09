import SwiftUI

/// La sous-section « RÉCENTS » de la section « Projets » : les derniers projets
/// ouverts, **nom seul**, sans pastille (capture
/// `2b-sidebar-variante-arbre-replie.png`).
///
/// La file est tenue par `RecentProjects` (décision **D4**, cinq entrées au
/// plus, persistée en `@AppStorage`) et alimentée par
/// `MainRouter.openProject` : ouvrir un projet — d'ici, du Portfolio, de la
/// palette ou de la recherche du menu système — l'y inscrit.
///
/// **C'est un état de session, pas une donnée du store** : le semis de
/// démonstration ne pose aucun récent, et l'écran de recette `p2b` les
/// préremplit lui-même (`RecetteScreen.codesDeProjetsRecents`).
struct RecentProjectsList: View {

    /// Le sous-titre, tel que la capture l'écrit.
    static let libelle = "RÉCENTS"

    /// Nombre de récents **affichés**. Le handoff en montre trois (« puis les
    /// 3 derniers projets ouverts ») alors que la file en retient cinq : les
    /// deux plus anciens restent disponibles pour la palette du lot 3, sans
    /// allonger la barre latérale.
    static let maxAffiches = 3

    /// Corps d'une ligne de projet.
    static let tailleNom: CGFloat = 13

    /// Les projets de la liste des récents, dans l'ordre de la liste.
    ///
    /// - Résolus par `Project.stableID` : c'est l'identifiant que `@AppStorage`
    ///   porte, et le seul qui survive à un redémarrage.
    /// - Un identifiant qui ne désigne plus rien (projet supprimé) est ignoré
    ///   sans trouer la liste.
    /// - Les **archivés** restent : ils ont été ouverts, et les cacher ferait
    ///   croire à une perte.
    /// - Une recherche en cours filtre par `ProjectSearch` (décision **D7**),
    ///   avant la troncature à `maxAffiches`.
    static func resolve(ids: [UUID],
                        among projects: [Project],
                        query: String = "",
                        notes: (Project) -> [Meeting] = { _ in [] }) -> [Project] {
        var parIdentifiant: [UUID: Project] = [:]
        for projet in projects {
            guard let id = projet.stableID else { continue }
            parIdentifiant[id] = projet
        }
        return ids
            .compactMap { parIdentifiant[$0] }
            .filter { ProjectSearch.matches($0, query: query, notes: notes($0)) }
            .prefix(maxAffiches)
            .map { $0 }
    }

    let projets: [Project]
    let indentation: CGFloat
    let ouvrir: (Project) -> Void

    var body: some View {
        Group {
            if !projets.isEmpty {
                Text(Self.libelle)
                    .sectionLabel()
                ForEach(projets, id: \.persistentModelID) { projet in
                    Button {
                        ouvrir(projet)
                    } label: {
                        HStack(spacing: 6) {
                            Text(projet.name)
                                .font(.plexSans(Self.tailleNom))
                                .foregroundStyle(One2OneToken.ink1)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, indentation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
