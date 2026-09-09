import Foundation

/// Une vue enregistrée du Portfolio : un jeu de filtres et un tri, nommés —
/// « Vue enregistrée : Mes projets ASP » de la capture `1a-portfolio.png`.
///
/// **Aucun nouveau `@Model`** (décision **D4**) : la liste est encodée en JSON
/// dans `AppSettings.portfolioSavedViewsJSON`, selon le motif de
/// `managerCategoriesJSON` — le seul disponible pour une structure persistée
/// (constat §2.20). D'où le `Codable` ici, et pas de `SchemaV4`.
struct PortfolioSavedView: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var filters: PortfolioFilters
    var sort: PortfolioSort

    init(id: UUID = UUID(),
         name: String,
         filters: PortfolioFilters = .aucun,
         sort: PortfolioSort = .parDefaut) {
        self.id = id
        self.name = name
        self.filters = filters
        self.sort = sort
    }
}

/// Les facettes du Portfolio, telles que les chips de la capture 1a les
/// montrent : `Entité : ASP`, `Risque ≥ Modéré`, `Phase ⌄`, `Statut ⌄`,
/// `Chef de projet ⌄`, plus le champ « Nom, code, sponsor… ».
///
/// Des `String` et non les enums de **D14** : une facette doit pouvoir retenir
/// une valeur que la table ne connaît pas (`"Réalisation"` existe dans le
/// store), sinon filtrer sur elle serait impossible.
struct PortfolioFilters: Codable, Equatable, Sendable {
    var entities: Set<String>
    var phases: Set<String>
    var statuses: Set<String>
    /// Seuil de gravité, par libellé (`"Modéré"`). `nil` = aucun seuil.
    var riskAtLeast: String?
    /// Chefs de projet retenus, par nom.
    var managers: Set<String>
    /// Le terme du champ de recherche.
    var text: String

    /// Aucune facette : le Portfolio complet.
    static let aucun = PortfolioFilters(entities: [], phases: [], statuses: [],
                                        riskAtLeast: nil, managers: [], text: "")

    /// Vrai quand rien n'est filtré — la barre de chips n'a alors rien à
    /// afficher.
    var estVide: Bool {
        entities.isEmpty && phases.isEmpty && statuses.isEmpty
            && riskAtLeast == nil && managers.isEmpty && text.isEmpty
    }

    init(entities: Set<String> = [],
         phases: Set<String> = [],
         statuses: Set<String> = [],
         riskAtLeast: String? = nil,
         managers: Set<String> = [],
         text: String = "") {
        self.entities = entities
        self.phases = phases
        self.statuses = statuses
        self.riskAtLeast = riskAtLeast
        self.managers = managers
        self.text = text
    }
}

/// Le tri du tableau : une colonne et un sens. Les colonnes sont celles de
/// l'en-tête de la capture 1a (`PROJET ↑`, `ENTITÉ`, `PHASE`, `RISQUE`,
/// `CHEF DE PROJET`, `JALON`, `DERNIÈRE RÉU.`).
struct PortfolioSort: Codable, Equatable, Sendable {

    enum Column: String, Codable, CaseIterable, Sendable {
        case name, entity, phase, risk, manager, milestone, lastMeeting

        /// L'intitulé de l'en-tête, en majuscules comme la capture.
        var header: String {
            switch self {
            case .name:        return "PROJET"
            case .entity:      return "ENTITÉ"
            case .phase:       return "PHASE"
            case .risk:        return "RISQUE"
            case .manager:     return "CHEF DE PROJET"
            case .milestone:   return "JALON"
            case .lastMeeting: return "DERNIÈRE RÉU."
            }
        }
    }

    var column: Column
    var ascending: Bool

    /// Le tri d'ouverture : nom croissant (`PROJET ↑` de la capture 1a).
    static let parDefaut = PortfolioSort(column: .name, ascending: true)
}
