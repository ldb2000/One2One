import SwiftUI
import SwiftData

/// L'écran **Portfolio** (capture `1a-portfolio.png`) : trouver un projet par
/// filtre plutôt que par dépliage.
///
/// **C'est un assembleur, pas un calculateur.** L'état vit dans
/// `PortfolioModel` (`@Observable`, décision **D11**), les règles dans
/// `PortfolioBuilder`, `ProjectPeople` et `ProjectBatchActions` — quatre
/// services purs testés avant cette vue. `body` ne compte rien, ne trie rien,
/// ne compare aucune date : il monte cinq bandes, de haut en bas.
///
/// | Bande | Fichier |
/// | --- | --- |
/// | En-tête (48 px) | `PortfolioHeader` |
/// | Barre de filtres (42 px) + vues enregistrées | `PortfolioFilterBar`, `SavedViewMenu` |
/// | Barre d'actions en lot, si sélection | `ProjectBatchBar` |
/// | Tableau ou groupement | `PortfolioTable`, `PortfolioGroupedView` |
/// | Pied | `PortfolioBuilder.footer` |
///
/// **Trois requêtes seulement.** Les projets, les réunions et les entités. Les
/// jalons viennent par la relation (`Project.milestones`) et le chef de projet
/// par la sienne ; le tableau se reconstruit quand l'une des trois change, une
/// fois, par `recharger`.
struct PortfolioView: View {

    /// Le pied du tableau : mesure « méta » du handoff.
    static let taillePied: CGFloat = 12

    @Environment(MainRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query(sort: \Project.name) private var projets: [Project]
    @Query private var reunions: [Meeting]
    @Query(sort: \Entity.name) private var entites: [Entity]
    @Query private var reglages: [AppSettings]

    @State private var model = PortfolioModel()
    @State private var nomDeVue = ""
    @State private var demandeDeNom = false

    private var vues: [PortfolioSavedView] {
        PortfolioSavedViewStore.vues(reglages.canonicalSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PortfolioHeader(sousTitre: model.summary,
                            mode: Binding(get: { model.mode }, set: { model.mode = $0 }),
                            nouveau: creerUnProjet)

            PortfolioFilterBar(model: model,
                               vues: vues,
                               enregistrerVue: { nomDeVue = ""; demandeDeNom = true },
                               supprimerVue: { supprimerLaVue($0) })

            if !model.selection.isEmpty {
                ProjectBatchBar(nombre: model.selection.count,
                                entites: entites,
                                deselectionner: { model.selection.removeAll() },
                                changerPhase: changerLaPhase,
                                changerStatut: changerLeStatut,
                                changerEntite: changerLEntite,
                                archiverAction: archiver,
                                supprimerAction: supprimer)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch model.mode {
                    case .tableau:
                        PortfolioTable(lignes: model.filtered,
                                       tri: model.sort,
                                       selection: model.selection,
                                       trierPar: trierPar,
                                       ouvrir: ouvrir,
                                       basculerSelection: { model.basculerSelection($0.id) })
                    case .parEntite:
                        PortfolioGroupedView(groupes: model.groupes,
                                             tri: model.sort,
                                             selection: model.selection,
                                             trierPar: trierPar,
                                             ouvrir: ouvrir,
                                             basculerSelection: { model.basculerSelection($0.id) })
                    }

                    Text(model.footer)
                        .font(.plexSans(Self.taillePied))
                        .foregroundStyle(One2OneToken.ink4)
                        .padding(.horizontal, PortfolioTable.marge)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(One2OneToken.bgApp)
        .sheet(isPresented: $demandeDeNom) {
            SavedViewNameSheet(nom: $nomDeVue,
                               valider: enregistrerLaVue,
                               annuler: { demandeDeNom = false })
        }
        .onAppear {
            model.recharger(projects: projets, meetings: reunions)
            appliquerLaVueDeRecette()
        }
        // Les `@Query` changent quand le store change : le tableau se
        // reconstruit alors une fois, hors de `body` (D11).
        .onChange(of: projets) { model.recharger(projects: projets, meetings: reunions) }
        .onChange(of: reunions) { model.recharger(projects: projets, meetings: reunions) }
    }

    // MARK: - Tri et navigation

    /// Clic sur un en-tête : la même colonne inverse le sens, une autre
    /// devient la colonne de tri, en croissant.
    private func trierPar(_ colonne: PortfolioSort.Column) {
        if model.sort.column == colonne {
            model.sort = PortfolioSort(column: colonne, ascending: !model.sort.ascending)
        } else {
            model.sort = PortfolioSort(column: colonne, ascending: true)
        }
    }

    /// Clic sur une ligne : l'écran du projet. Le lot 4 y montera l'écran à six
    /// onglets ; jusque-là la route ouvre la fiche complète.
    private func ouvrir(_ ligne: PortfolioRow) {
        guard let projet = model.projet(ligne) else { return }
        router.openProject(projet)
    }

    // MARK: - Création

    private func creerUnProjet() {
        let projet = ProjectCreation.creer(among: projets, in: context)
        model.recharger(projects: projets, meetings: reunions)
        router.openProject(projet)
    }

    // MARK: - Actions en lot

    private func changerLaPhase(_ phase: String) {
        ProjectBatchActions.setPhase(phase, on: model.projetsSelectionnes)
        model.recharger(projects: projets, meetings: reunions)
    }

    private func changerLeStatut(_ statut: String) {
        ProjectBatchActions.setStatus(statut, on: model.projetsSelectionnes)
        model.recharger(projects: projets, meetings: reunions)
    }

    private func changerLEntite(_ entite: Entity?) {
        ProjectBatchActions.setEntity(entite, on: model.projetsSelectionnes)
        model.recharger(projects: projets, meetings: reunions)
    }

    private func archiver() {
        ProjectBatchActions.archive(model.projetsSelectionnes)
        model.selection.removeAll()
        model.recharger(projects: projets, meetings: reunions)
    }

    private func supprimer() {
        ProjectBatchActions.delete(model.projetsSelectionnes, in: context)
        model.selection.removeAll()
        model.recharger(projects: projets, meetings: reunions)
    }

    // MARK: - Vues enregistrées

    private func enregistrerLaVue() {
        let nom = nomDeVue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty else { return }
        let vue = PortfolioSavedViewStore.enregistrer(model.vueCourante(nommee: nom), in: context)
        model.vueActive = vue.id
        demandeDeNom = false
    }

    private func supprimerLaVue(_ vue: PortfolioSavedView) {
        PortfolioSavedViewStore.supprimer(vue.id, in: context)
        if model.vueActive == vue.id { model.vueActive = nil }
    }

    /// Active la vue que l'écran de recette `p1a` a posée, s'il y en a une.
    ///
    /// Même mécanisme que le terme en attente de la palette
    /// (`MainRouter.pendingPaletteQuery`) : la recette ne peut pas cliquer, et
    /// une vue enregistrée est un état d'écran que le semis ne pose pas.
    private func appliquerLaVueDeRecette() {
        guard let id = router.consumePendingPortfolioSavedView(),
              let vue = vues.first(where: { $0.id == id }) else { return }
        model.appliquer(vue)
    }
}
