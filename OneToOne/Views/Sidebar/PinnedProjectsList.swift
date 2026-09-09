import SwiftUI

/// La sous-section « ÉPINGLÉS » de la section « Projets » : trois à cinq
/// projets, pastille de statut de 10 px et nom tronqué (capture
/// `2b-sidebar-variante-arbre-replie.png`).
///
/// **Le choix des projets est une fonction pure** (`epingles`), testée avant
/// cette vue : l'épinglage vient du champ `Project.pinned` (décision **D4**),
/// les archivés en sortent, et une recherche en cours les filtre comme elle
/// filtre déjà les collaborateurs.
struct PinnedProjectsList: View {

    /// Le sous-titre, tel que la capture l'écrit. `.sectionLabel()` le rend en
    /// majuscules ; il est écrit en majuscules ici pour que le test le lise au
    /// mot près.
    static let libelle = "ÉPINGLÉS"

    /// Diamètre de la pastille de statut dans la barre latérale. La colonne du
    /// Portfolio en demande 9 (défaut de `StatusIcon`) ; ici, 10.
    static let taillePastille: CGFloat = 10

    /// Corps d'une ligne de projet — le corps du handoff.
    static let tailleNom: CGFloat = 13

    /// Les projets épinglés à afficher, dans l'ordre.
    ///
    /// - Les **archivés** en sortent : la sous-section est un accès rapide au
    ///   travail en cours.
    /// - Le tri est **par nom** : l'épinglage n'a pas d'ordre persisté, et un
    ///   ordre d'insertion ne survivrait ni à un réimport ni à un relancement.
    ///   La maquette les montre dans l'ordre de son tableau, qu'aucune colonne
    ///   du modèle ne reproduit (écart consigné au journal du lot 1).
    /// - Une recherche en cours filtre par `ProjectSearch` (décision **D7**).
    static func epingles(among projects: [Project],
                         query: String = "",
                         notes: (Project) -> [Meeting] = { _ in [] }) -> [Project] {
        projects
            .filter { $0.pinned && !$0.isArchived }
            .filter { ProjectSearch.matches($0, query: query, notes: notes($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    let projets: [Project]
    let indentation: CGFloat
    let ouvrir: (Project) -> Void

    var body: some View {
        Group {
            if !projets.isEmpty {
                Text(Self.libelle)
                    .sectionLabel()
                // Identité **préfixée par la sous-section**
                // (`SidebarProjectRow`) : un projet à la fois épinglé et
                // récent apparaît deux fois dans la même `List`, et deux
                // lignes de même identité y rendent n'importe quoi — c'est ce
                // qui a fait disparaître deux pastilles à la recette `p1f`.
                ForEach(SidebarProjectRow.lignes(projets, section: Self.libelle)) { ligne in
                    let projet = ligne.projet
                    Button {
                        ouvrir(projet)
                    } label: {
                        HStack(spacing: 6) {
                            StatusIcon(status: projet.status, size: Self.taillePastille)
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
