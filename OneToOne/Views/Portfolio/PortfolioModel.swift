import Foundation
import Observation
import SwiftData

/// L'état de l'écran Portfolio (capture `1a-portfolio.png`), **hors des
/// vues** (décision **D11**).
///
/// **Rien n'est calculé dans un `body`.** `recharger` reconstruit les lignes
/// par `PortfolioBuilder.rows`, puis les filtre et les trie une fois ;
/// `PortfolioView` les lit telles quelles. Le tableau se recalcule quand les
/// `@Query` changent, quand une facette change ou quand le tri change — pas à
/// chaque passe de rendu.
///
/// **Le terme de recherche est débouncé à 250 ms**, comme celui de la barre
/// latérale (`Sidebar.searchDebounceTask`) : `champDeRecherche` suit la
/// frappe, `filters.text` ne bouge qu'après la pause, et c'est lui qui filtre.
/// Vider le champ s'applique immédiatement — attendre un quart de seconde pour
/// revoir tout le tableau se sent.
///
/// **Un objet et non des `@State` dispersés** : la barre de filtres, le menu
/// de vues enregistrées, l'en-tête de tableau et la barre d'actions en lot
/// touchent tous au même état, et un `@Binding` qui traverserait quatre
/// niveaux est ce que la refonte de l'écran de réunion a proscrit.
@MainActor
@Observable
final class PortfolioModel {

    /// Le délai de debounce du champ de recherche, en nanosecondes.
    static let debounceRecherche: UInt64 = 250_000_000

    // MARK: - Ce que l'utilisateur règle

    /// Les facettes actives. En changer déclenche un recalcul.
    var filters: PortfolioFilters = .aucun {
        didSet { guard filters != oldValue else { return }; recalculer() }
    }

    /// La colonne et le sens du tri (défaut : nom croissant).
    var sort: PortfolioSort = .parDefaut {
        didSet { guard sort != oldValue else { return }; recalculer() }
    }

    /// La sélection multiple (⇧-clic), par `PersistentIdentifier` — l'identité
    /// que `ProjectBatchActions` attend (décision **D15**).
    var selection: Set<PersistentIdentifier> = []

    /// Le contenu du champ de recherche, à la frappe. `filters.text` le suit
    /// après le debounce.
    var champDeRecherche: String = ""

    /// Le mode d'affichage : le segmenté « Tableau / Groupé par entité ».
    var mode: Mode = .tableau

    /// La vue enregistrée active, ou `nil` pour « Aucune ».
    var vueActive: UUID?

    enum Mode: String, CaseIterable, Sendable {
        case tableau
        case parEntite

        /// Le libellé du segment, tel que la capture l'écrit.
        var libelle: String {
            switch self {
            case .tableau:   return "Tableau"
            case .parEntite: return "Groupé par entité"
            }
        }
    }

    // MARK: - Ce que la vue lit

    /// Toutes les lignes actives, avant filtrage.
    private(set) var rows: [PortfolioRow] = []
    /// Les lignes affichées : filtrées puis triées.
    private(set) var filtered: [PortfolioRow] = []
    /// Le groupement du mode « Groupé par entité ».
    private(set) var groupes: [(entite: String, lignes: [PortfolioRow])] = []
    /// Le sous-titre de l'en-tête (« 62 actifs · 8 entités · 14 archivés »).
    private(set) var summary: String = ""

    /// Le pied du tableau (« 8 lignes sur 62 · sélection multiple… »).
    var footer: String {
        PortfolioBuilder.footer(affichees: filtered.count, total: rows.count)
    }

    /// Les valeurs qu'un menu de facette propose, calculées sur **toutes** les
    /// lignes et non sur les lignes filtrées : sinon, filtrer sur ASP retirerait
    /// les autres entités du menu et interdirait d'en changer.
    func valeurs(de facette: PortfolioFacet) -> [String] {
        PortfolioBuilder.values(of: facette, in: rows)
    }

    // MARK: - Recalcul

    /// Les projets, indexés par leur identité de ligne — la vue en a besoin
    /// pour router (`MainRouter.openProject`) et pour les actions en lot, que
    /// `PortfolioRow`, simple valeur, ne peut pas porter.
    private var projetsParID: [PersistentIdentifier: Project] = [:]
    private var tousLesProjets: [Project] = []
    private var tacheDeRecherche: Task<Void, Never>?

    /// Reconstruit tout depuis le store. Appelée à l'apparition de l'écran et à
    /// chaque changement des `@Query` de la vue.
    func recharger(projects: [Project], meetings: [Meeting], today: Date = Date()) {
        tousLesProjets = projects
        projetsParID = Dictionary(projects.map { ($0.persistentModelID, $0) },
                                  uniquingKeysWith: { premier, _ in premier })
        rows = PortfolioBuilder.rows(projects: projects, meetings: meetings, today: today)
        summary = PortfolioBuilder.summary(projects: projects)
        recalculer()
    }

    /// Refiltre et retrie sans relire le store. Purge au passage la sélection
    /// des lignes qui ont disparu : une barre d'actions en lot annonçant
    /// « 3 projets sélectionnés » alors qu'un seul existe encore ferait agir
    /// sur du vide.
    private func recalculer() {
        filtered = PortfolioBuilder.sort(PortfolioBuilder.apply(filters, to: rows), by: sort)
        groupes = PortfolioBuilder.groups(filtered)
        let presents = Set(rows.map(\.id))
        selection.formIntersection(presents)
    }

    // MARK: - Recherche

    /// Applique le terme après 250 ms, ou tout de suite s'il est vide.
    func rechercher(_ terme: String) {
        champDeRecherche = terme
        tacheDeRecherche?.cancel()
        guard !terme.isEmpty else {
            filters.text = ""
            return
        }
        tacheDeRecherche = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceRecherche)
            guard !Task.isCancelled, let self else { return }
            self.filters.text = terme
        }
    }

    // MARK: - Facettes

    /// Bascule une valeur dans une facette (les menus de chips sont à cocher).
    func basculer(_ valeur: String, dans facette: PortfolioFacet) {
        switch facette {
        case .entity:  basculer(valeur, dans: &filters.entities)
        case .phase:   basculer(valeur, dans: &filters.phases)
        case .status:  basculer(valeur, dans: &filters.statuses)
        case .manager: basculer(valeur, dans: &filters.managers)
        case .risk:
            // Un seuil, pas une liste : rechoisir le même cran l'annule.
            filters.riskAtLeast = filters.riskAtLeast == valeur ? nil : valeur
        }
        vueActive = nil
    }

    private func basculer(_ valeur: String, dans ensemble: inout Set<String>) {
        if ensemble.contains(valeur) { ensemble.remove(valeur) } else { ensemble.insert(valeur) }
    }

    /// Vide une facette — la croix d'une chip active.
    func effacer(_ facette: PortfolioFacet) {
        switch facette {
        case .entity:  filters.entities = []
        case .phase:   filters.phases = []
        case .status:  filters.statuses = []
        case .manager: filters.managers = []
        case .risk:    filters.riskAtLeast = nil
        }
        vueActive = nil
    }

    /// Les valeurs actives d'une facette, dans un ordre stable — le libellé
    /// d'une chip ne doit pas changer d'un rendu à l'autre.
    func actives(_ facette: PortfolioFacet) -> [String] {
        switch facette {
        case .entity:  return filters.entities.sorted()
        case .phase:   return filters.phases.sorted()
        case .status:  return filters.statuses.sorted()
        case .manager: return filters.managers.sorted()
        case .risk:    return filters.riskAtLeast.map { [$0] } ?? []
        }
    }

    // MARK: - Vues enregistrées

    /// Applique une vue enregistrée : ses facettes, son tri, son nom.
    func appliquer(_ vue: PortfolioSavedView) {
        sort = vue.sort
        filters = vue.filters
        champDeRecherche = vue.filters.text
        vueActive = vue.id
    }

    /// Remet le tableau à son état d'ouverture : aucun filtre, aucun texte,
    /// aucune vue active, tri par défaut.
    ///
    /// La sélection multiple et le mode d'affichage ne sont **pas** touchés :
    /// ce sont des choix de manipulation, pas un point de vue sur les données.
    func reinitialiser() {
        tacheDeRecherche?.cancel()
        filters = .aucun
        champDeRecherche = ""
        vueActive = nil
        sort = .parDefaut
    }

    /// La vue que « Enregistrer la vue actuelle… » créerait, sous ce nom.
    func vueCourante(nommee nom: String) -> PortfolioSavedView {
        PortfolioSavedView(name: nom, filters: filters, sort: sort)
    }

    // MARK: - Sélection

    /// ⇧-clic : entre ou sort une ligne de la sélection.
    func basculerSelection(_ id: PersistentIdentifier) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Les projets sélectionnés, pour `ProjectBatchActions`.
    var projetsSelectionnes: [Project] {
        ProjectBatchActions.resolve(selection, among: tousLesProjets)
    }

    /// Le projet d'une ligne — ce qu'un clic ouvre.
    func projet(_ ligne: PortfolioRow) -> Project? {
        projetsParID[ligne.id]
    }

    /// Tous les projets du store, pour la création (`ProjectCreation`).
    var projets: [Project] { tousLesProjets }
}

/// La lecture et l'écriture des vues enregistrées du Portfolio, dans
/// `AppSettings.portfolioSavedViews` (décision **D4** : aucun nouveau
/// `@Model`).
///
/// Trois fonctions, parce que trois appelants en ont besoin : le menu de la
/// barre de filtres, et l'écran de recette `p1a`, qui doit pouvoir poser
/// « Mes projets ASP » avant la capture sans passer par l'interface.
///
/// **Idempotent par identifiant** : réenregistrer une vue de même `id` la
/// remplace au lieu d'en créer une seconde — c'est ce qui rend le semis de
/// recette rejouable.
@MainActor
enum PortfolioSavedViewStore {

    /// Les vues enregistrées, ou un tableau vide.
    static func vues(_ settings: AppSettings?) -> [PortfolioSavedView] {
        settings?.portfolioSavedViews ?? []
    }

    /// Enregistre (ou remplace) une vue et la rend.
    ///
    /// Crée l'`AppSettings` s'il n'existe pas : un store neuf n'en a pas, et
    /// l'écran de recette est précisément lancé sur un store neuf.
    @discardableResult
    static func enregistrer(_ vue: PortfolioSavedView,
                            in context: ModelContext) -> PortfolioSavedView {
        let reglages = reglages(in: context)
        var liste = reglages.portfolioSavedViews
        if let index = liste.firstIndex(where: { $0.id == vue.id }) {
            liste[index] = vue
        } else {
            liste.append(vue)
        }
        reglages.portfolioSavedViews = liste
        try? context.save()
        return vue
    }

    /// Supprime une vue par son identifiant.
    static func supprimer(_ id: UUID, in context: ModelContext) {
        let reglages = reglages(in: context)
        reglages.portfolioSavedViews = reglages.portfolioSavedViews.filter { $0.id != id }
        try? context.save()
    }

    private static func reglages(in context: ModelContext) -> AppSettings {
        if let existants = (try? context.fetch(FetchDescriptor<AppSettings>()))?.canonicalSettings {
            return existants
        }
        let neufs = AppSettings()
        context.insert(neufs)
        return neufs
    }
}
