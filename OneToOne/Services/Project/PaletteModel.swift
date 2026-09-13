import Foundation
import Observation
import SwiftData

/// L'état de la palette `⌘K` — ce qu'elle montre, où est le curseur, et ce que
/// les deux touches d'action font (capture `1c-palette-cmdk.png`, décisions
/// **D1**, **D8** et **D11**).
///
/// **La vue ne calcule rien.** `CommandPalette` lit `projets`, `actions`,
/// `index` et les libellés statiques d'ici ; elle n'écrit que le terme frappé.
/// C'est la règle du dépôt (D11) et c'est ce qui rend testable, avant toute
/// vue, l'ordre des résultats, les bornes de `↑`/`↓` et l'effet de `⌘↩`.
///
/// **La recherche est celle de tout le monde** (décision **D7**) :
/// `ProjectSearch.rank`, la même que la barre latérale et le Portfolio, avec
/// la même correspondance pliant casse et accents.
///
/// **Le portefeuille entier, archivés compris.** Le Portfolio ne montre que
/// les projets actifs ; la palette, non — la capture 1c fait remonter
/// « RH – Migration GED documentaire », qui est archivé. Chercher un projet
/// qu'on sait clos est un usage légitime de la palette, et c'est précisément
/// ce que le semis met en scène.
@MainActor
@Observable
final class PaletteModel {

    // MARK: - Mesures et libellés

    /// Nombre maximum de projets listés. Six lignes tiennent sous le champ
    /// sans faire défiler la feuille, et une palette qui défile n'est plus une
    /// palette.
    static let maxProjets = 6

    /// Les deux libellés de groupe, rendus en majuscules par `.sectionLabel()`.
    static let titreProjets = "Projets"
    static let titreActions = "Actions"

    /// Ce que la palette affiche à la place d'une liste de projets quand le
    /// terme ne trouve rien. Un terme **vide** n'affiche pas ce libellé : rien
    /// n'a été cherché.
    static let libelleAucunProjet = "Aucun projet"

    /// La pastille du champ, à droite : la touche qui referme la palette.
    static let pastilleEsc = "esc"

    /// Le pied, tel que le handoff l'écrit. Rendu en trois segments espacés de
    /// 14 pt, comme la maquette les dessine — d'où `piedSegments`, qui est la
    /// seule chose que la vue lit.
    static let pied = "↑↓ naviguer · ↩ ouvrir · ⌘↩ épingler"

    /// Les trois segments du pied, dans l'ordre.
    static var piedSegments: [String] { pied.components(separatedBy: " · ") }

    /// L'invite du champ, quand rien n'est frappé.
    static let invite = "Nom, code, sponsor, chef de projet…"

    // MARK: - Les deux actions

    /// Ce que la palette sait faire en plus d'ouvrir un projet.
    ///
    /// Deux entrées, toujours dans cet ordre, et toujours les deux ensemble :
    /// la maquette les montre côte à côte sous le groupe `ACTIONS`.
    enum Action: String, CaseIterable, Equatable, Sendable {
        /// Crée un projet portant le terme pour nom, puis l'ouvre.
        case creer
        /// Ouvre la recherche lexicale dans les comptes rendus (décision
        /// **D8** : les CR seulement, pas les mails).
        case chercher

        /// Le symbole SF de la colonne de gauche.
        var icone: String {
            switch self {
            case .creer:    return "plus"
            case .chercher: return "line.3.horizontal"
            }
        }
    }

    /// Le libellé d'une action pour ce terme, guillemets français compris.
    ///
    /// « Chercher « x » dans les CR » et non « dans les CR et mails », que la
    /// maquette écrit : décision **D8**, tranchée par Laurent le 2026-09-09.
    static func libelle(_ action: Action, terme: String) -> String {
        let net = terme.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .creer:    return "Créer un projet « \(net) »"
        case .chercher: return "Chercher « \(net) » dans les CR"
        }
    }

    // MARK: - La ligne sélectionnée

    /// Ce que `↩` activerait. `nil` quand la palette n'a aucune ligne.
    ///
    /// Le projet est désigné par son **rang** et non par son objet : une
    /// sélection doit rester comparable dans un test, et `Project` n'est pas
    /// `Equatable` au sens où on l'entendrait ici.
    enum Selection: Equatable, Sendable {
        case projet(Int)
        case action(Action)
    }

    // MARK: - État

    /// Le terme retenu, rogné. C'est lui que les libellés d'action citent.
    private(set) var terme: String = ""

    /// Les projets à montrer, du plus pertinent au moins pertinent, bornés à
    /// `maxProjets`.
    private(set) var projets: [Project] = []

    /// Les actions à montrer : les deux, ou aucune si le terme est vide.
    private(set) var actions: [Action] = []

    /// Le rang de la ligne sélectionnée, projets puis actions.
    private(set) var index: Int = 0

    // MARK: - Chargement

    /// Recharge la palette pour ce terme.
    ///
    /// Appelée à chaque frappe : la sélection repart sur la première ligne,
    /// parce qu'un curseur qui reste au rang 3 pendant que la liste change
    /// désigne un autre projet à chaque caractère.
    func recharger(projects: [Project], terme: String) {
        let net = terme.trimmingCharacters(in: .whitespacesAndNewlines)
        self.terme = net
        guard !net.isEmpty else {
            projets = []
            actions = []
            index = 0
            return
        }
        projets = Array(ProjectSearch.rank(projects, query: net).prefix(Self.maxProjets))
        actions = Action.allCases
        index = 0
    }

    // MARK: - Lecture

    /// Rien à montrer : le terme est vide.
    var estVide: Bool { terme.isEmpty }

    /// Un terme a été cherché et n'a rien trouvé — le cas qui affiche
    /// « Aucun projet ».
    var aucunProjet: Bool { !terme.isEmpty && projets.isEmpty }

    /// Le nombre de lignes navigables : les projets, puis les actions.
    var nombreDeLignes: Int { projets.count + actions.count }

    var selection: Selection? {
        guard nombreDeLignes > 0 else { return nil }
        let rang = min(index, nombreDeLignes - 1)
        if rang < projets.count { return .projet(rang) }
        return .action(actions[rang - projets.count])
    }

    /// Le projet sélectionné, ou `nil` si le curseur est sur une action.
    var projetSelectionne: Project? {
        guard case .projet(let rang) = selection else { return nil }
        return projets[rang]
    }

    /// Cette ligne est-elle celle du curseur ? La vue s'en sert pour le fond
    /// `actionBg` et le `↩` de droite.
    func estSelectionne(_ selection: Selection) -> Bool { self.selection == selection }

    // MARK: - Clavier

    /// `↓`. Ne sort pas de la liste : une palette n'est pas cyclique — arriver
    /// en bas et revenir en haut fait perdre le fil de ce qu'on lisait.
    func suivant() {
        guard nombreDeLignes > 0 else { return }
        index = min(index + 1, nombreDeLignes - 1)
    }

    /// `↑`. Même borne, en haut.
    func precedent() {
        guard nombreDeLignes > 0 else { return }
        index = max(index - 1, 0)
    }

    /// `⌘↩` : bascule l'épinglage du projet sélectionné et le rend, ou `nil`
    /// si le curseur n'est pas sur un projet.
    ///
    /// **La liste n'est pas rechargée.** Épingler remonte un projet dans
    /// `ProjectSearch.rank` : réordonner ici ferait sauter sous le curseur la
    /// ligne qu'on vient d'épingler, et la palette reste ouverte (c'est tout
    /// l'intérêt de `⌘↩` : en épingler plusieurs d'affilée).
    ///
    /// L'enregistrement est laissé à l'appelant, qui tient le contexte : un
    /// modèle d'écran n'écrit pas dans le store.
    @discardableResult
    func basculerEpinglage() -> Project? {
        guard let projet = projetSelectionne else { return nil }
        projet.pinned.toggle()
        return projet
    }

    // MARK: - La sous-ligne mono

    /// `code · entité · phase · chef de projet`, les segments vides omis.
    ///
    /// **Le chef de projet vient de la relation seule** (décision **D3**) : un
    /// projet dont seul le nom xlsx est renseigné n'affiche pas de chef, comme
    /// la colonne du Portfolio et la carte Interlocuteurs. La capture 1c le
    /// montre pour « RH – Migration GED documentaire », dont la sous-ligne
    /// s'arrête à la phase.
    ///
    /// La phase est rendue par sa table (décision **D14**) quand elle y
    /// figure, et telle quelle sinon : le portfolio externe écrit ce qu'il veut
    /// dans cette colonne, et « Réalisation » doit s'afficher, pas disparaître.
    static func sousLigne(_ projet: Project) -> String {
        let phase = ProjectPhase(raw: projet.phase)?.label
            ?? projet.phase.trimmingCharacters(in: .whitespaces)
        let segments = [
            projet.code,
            projet.entity?.name,
            phase,
            ProjectPeople.manager(of: projet),
        ]
        return segments
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
