import Foundation
import SwiftData

/// La cellule « JALON » du tableau du Portfolio — les trois formes que la
/// capture `1a-portfolio.png` montre : `J−4`, `retard`, `—`.
///
/// Un `enum` et non une chaîne : la teinte dépend de la forme (rouge à sept
/// jours ou moins, rouge pour un retard, neutre pour l'absence), et une vue
/// qui reparserait « J−4 » pour savoir si elle doit rougir serait absurde.
enum MilestoneCell: Equatable, Sendable {

    /// Le prochain jalon non fait est dans `n` jours (`n >= 0`).
    case days(Int)
    /// Un jalon est échu et non fait, ou déclaré `MilestoneState.late`.
    case late
    /// Le projet n'a aucun jalon daté restant.
    case none

    /// En deçà de ce nombre de jours, l'échéance s'affiche en `reportInk` :
    /// c'est le seuil du handoff (« l'alerte de deadline en `reportInk` si J−7
    /// ou moins », §1d) et celui de la ligne `J−4` de la capture 1a.
    static let seuilAlerte = 7

    /// Le libellé de la cellule.
    ///
    /// Le signe est un **moins typographique** (U+2212) et non un trait
    /// d'union : c'est ce que la capture affiche, et en Plex Mono les deux ne
    /// font pas la même largeur.
    var libelle: String {
        switch self {
        case .days(let jours): return "J−\(jours)"
        case .late:            return "retard"
        case .none:            return "—"
        }
    }

    /// La cellule doit-elle s'afficher en rouge ?
    var estAlerte: Bool {
        switch self {
        case .days(let jours): return jours <= Self.seuilAlerte
        case .late:            return true
        case .none:            return false
        }
    }

    /// Clé de tri, du plus urgent au moins urgent : un retard d'abord, puis
    /// les échéances par ordre croissant, l'absence de jalon en dernier.
    var rangDeTri: Int {
        switch self {
        case .late:            return -1
        case .days(let jours): return jours
        case .none:            return Int.max
        }
    }
}

/// Une ligne du tableau du Portfolio (capture `1a-portfolio.png`),
/// **entièrement calculée d'avance** (décision **D11**).
///
/// C'est une valeur, pas un projet : la vue n'a plus de relation à traverser
/// ni de date à comparer dans son `body`. Elle est construite une fois par
/// affichage par `PortfolioBuilder.rows`, et le filtrage comme le tri
/// travaillent sur elle — donc se testent sans monter d'écran.
///
/// **`phaseRaw` à côté de `phase`**, et pas seulement l'enum : `Project.phase`
/// reste une `String` libre (décision **D14**) et le store contient
/// « Réalisation », que la table ne connaît pas. `phase` vaut alors `nil`
/// (badge neutre) mais `phaseRaw` porte la valeur, qui reste filtrable et
/// triable — sinon un projet hors table serait invisible à sa propre facette.
struct PortfolioRow: Identifiable, Equatable, Sendable {

    /// Identité de la ligne, et clé de la sélection multiple (décision
    /// **D15** : « identité par `PersistentIdentifier` »).
    let id: PersistentIdentifier

    /// L'identifiant inter-fenêtres du projet, pour router vers son écran.
    /// Optionnel : les projets créés avant la colonne en portent `nil`
    /// (`repairStoreIfNeeded` les backfille au lancement, mais un constructeur
    /// pur n'écrit pas dans le store).
    let stableID: UUID?

    let name: String
    let code: String
    let type: String

    /// L'entité affichée : `Project.entity?.name`, à défaut `domain`, `nil` si
    /// les deux sont vides (la colonne affiche alors un tiret).
    let entity: String?

    /// Le sponsor, jamais affiché dans le tableau : il est là parce que le
    /// champ de recherche s'annonce « Nom, code, sponsor… ».
    let sponsor: String

    /// La phase connue, ou `nil` pour une valeur hors table.
    let phase: ProjectPhase?
    /// La phase telle qu'elle est persistée.
    let phaseRaw: String

    let status: ProjectStatus?
    let risk: RiskLevel?

    /// Le chef de projet — `projectManager?.name` **seulement** (décision
    /// **D3** : la relation fait foi). `nil` s'affiche « Non affecté ».
    let manager: String?

    let nextMilestone: MilestoneCell

    /// La date de la dernière réunion tenue, pour le tri.
    let lastMeeting: Date?
    /// Son libellé relatif (« hier », « il y a 3 j », « jamais »), pour
    /// l'affichage.
    let lastMeetingLabel: String

    let pinned: Bool

    /// Le libellé du statut, tel que `StatusIcon` l'attend.
    ///
    /// Une valeur hors table et `Unknown` rendent tous deux la pastille
    /// neutre : la chaîne vide suffit, et évite de transporter un `statusRaw`
    /// que rien d'autre ne lirait.
    var statusLabel: String { status?.label ?? "" }

    /// Le libellé de la colonne « Entité » : l'entité, ou un tiret.
    var entityLabel: String { entity ?? "—" }
}
