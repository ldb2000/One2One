import Foundation
import Observation

/// L'écran affiché par la fenêtre principale, et comment on y arrive
/// (décision **D0**).
///
/// **Un état, pas une vue.** La barre latérale sélectionne `route` ;
/// `MainDetailView` la lit et monte l'écran. Tout le reste — palette `⌘K`
/// (lot 3), section « Récents » (lot 1), fil d'Ariane de la capture 1d
/// (lot 4), `SearchPopover` du menu système — appelle `open(_:)` ou
/// `openProject(_:tab:)`. Aucun `@Binding` ne traverse plus d'un niveau, comme
/// pour `MeetingScreenModel`.
///
/// **Un singleton, parce que le menu système n'est pas dans la hiérarchie
/// SwiftUI.** `MenuBarController` est un `NSObject` : il ne peut pas lire un
/// `@Environment`. `MainRouter.shared` est donc le routeur de l'application,
/// et `ContentView` l'injecte tel quel dans l'environnement. Les tests
/// construisent leur propre instance avec leurs propres réglages.
@MainActor
@Observable
final class MainRouter {

    /// Le routeur de l'application. `ContentView` l'injecte par
    /// `.environment(_:)` ; `MenuBarController` l'appelle directement.
    static let shared = MainRouter()

    /// Nombre d'écrans quittés que `back()` sait remonter.
    static let historyLimit = 20

    /// L'écran affiché. `nil` est possible — c'est ce qu'une `List(selection:)`
    /// écrit quand l'utilisateur désélectionne — et vaut le tableau de bord.
    var route: MainRoute? = .dashboard

    /// Les écrans quittés, du plus ancien au plus récent. Borné à
    /// `historyLimit` : c'est un fil d'Ariane, pas un journal.
    private(set) var history: [MainRoute] = []

    /// Terme que la palette doit afficher à sa prochaine ouverture, posé par
    /// l'écran de recette `p1c` (« ged ») et consommé par le lot 3. Ici parce
    /// que la palette n'existe pas encore et que le routeur est le seul objet
    /// que la recette peut atteindre avant elle.
    var pendingPaletteQuery: String?

    /// Les réglages où s'écrit la liste des projets récents. Injectable : une
    /// suite de tests ne doit pas écrire dans les réglages de l'utilisateur.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Navigation

    /// Affiche `route` et pousse l'écran quitté dans l'histoire.
    ///
    /// Réouvrir l'écran courant n'empile rien : sinon cliquer deux fois la
    /// même entrée de la barre latérale rendrait « revenir » inopérant.
    func open(_ route: MainRoute) {
        guard self.route != route else { return }
        if let precedente = self.route {
            history.append(precedente)
            if history.count > Self.historyLimit {
                history.removeFirst(history.count - Self.historyLimit)
            }
        }
        self.route = route
    }

    /// Revient à l'écran précédent. Sans histoire, ne fait rien.
    func back() {
        guard let precedente = history.popLast() else { return }
        route = precedente
    }

    // MARK: - Projets

    /// Ouvre l'écran d'un projet et l'inscrit dans les récents.
    ///
    /// `ensuredStableID` et non `stableID` : les projets créés avant l'ajout de
    /// la colonne en portent `nil`, et une route ne peut pas désigner un projet
    /// sans identifiant.
    func openProject(_ project: Project, tab: ProjectTab = .pilotage) {
        let id = project.ensuredStableID
        open(.project(id, tab))
        pushRecent(id)
    }

    /// Les cinq derniers projets ouverts, du plus récent au plus ancien
    /// (décision **D4**, format tenu par `RecentProjects`).
    var recentProjectIDs: [UUID] {
        RecentProjects.ids(from: defaults.string(forKey: RecentProjects.key) ?? "")
    }

    private func pushRecent(_ id: UUID) {
        let brut = defaults.string(forKey: RecentProjects.key) ?? ""
        defaults.set(RecentProjects.push(id, into: brut), forKey: RecentProjects.key)
    }

    // MARK: - Palette

    /// Rend le terme en attente et le retire, pour qu'une seconde ouverture de
    /// la palette reparte vide.
    func consumePendingPaletteQuery() -> String? {
        defer { pendingPaletteQuery = nil }
        return pendingPaletteQuery
    }
}
