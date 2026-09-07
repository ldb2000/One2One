import CoreGraphics
import Foundation
import Observation

/// Ce que la barre du haut affiche de la capture (spec §5.2). Une énumération
/// et non trois booléens : `armée`, `perdue` et `au repos` s'excluent, et un
/// écran qui afficherait deux d'entre eux en même temps serait un mensonge.
enum CapturePillState: Equatable, Sendable {
    /// Aucune session : bouton neutre `Capture`.
    case idle
    /// `● Capture · Teams 3 ⌄`. `automatic` dit si la détection écrit d'
    /// elle-même — armée sans détection, la capture n'attend qu'un geste.
    case armed(source: CaptureSource, count: Int, automatic: Bool)
    /// `Source perdue` : fenêtre fermée, autorisation refusée, écran débranché.
    case lost(count: Int)

    /// Le libellé de la pilule, tel qu'il apparaît sur la capture 4a.
    var label: String {
        switch self {
        case .idle: return "Capture"
        case .armed(let source, let count, _): return "Capture · \(source.label) \(count)"
        case .lost: return "Source perdue"
        }
    }

    /// Nombre de captures de la séance, lisible dans **tous** les états :
    /// c'est la moitié du critère d'acceptation n° 1 du chantier 4.
    var count: Int {
        switch self {
        case .idle: return 0
        case .armed(_, let count, _), .lost(let count): return count
        }
    }
}

/// L'état d'écran de la capture : source choisie, bascules, sélection de la
/// bande, ouverture du sélecteur.
///
/// Une seule ligne dans `MeetingScreenModel` (`var capture = CaptureState()`),
/// tout le reste ici : les lots parallèles ajoutent tous « en fin de type », et
/// c'est ce geste qui a produit six conflits à l'intégration des lots 2 et 3.
///
/// Les décisions sont des **fonctions pures statiques**, testables sans vue :
/// la couche d'interface est la seule sans tests, et c'est là que les défauts
/// survivent (leçon de `One2One-specs.md`).
@MainActor
@Observable
final class CaptureState {

    /// Les lignes du sélecteur, reconstruites à l'ouverture du popover.
    var options: [CaptureSourceOption] = []
    /// La source retenue. `nil` tant que rien n'a été choisi : `⌘⇧S` ouvre
    /// alors le sélecteur au lieu de capturer au hasard.
    var selected: CaptureSourceOption?
    /// Le sélecteur est déplié.
    var showPopover = false
    /// Chargement du catalogue en cours (le popover dit « Recherche… »).
    var isLoadingOptions = false
    /// Autorisation d'enregistrement d'écran refusée : le popover explique et
    /// mène aux Réglages système, sans dialogue bloquant (spec §5.2).
    var permissionDenied = false
    /// Message du catalogue (échec d'énumération), distinct de `lastError` du
    /// service, qui parle de la capture elle-même.
    var catalogError: String?

    /// Bascule « Capturer à chaque changement de partage » (spec §5.1).
    var detectsAutomatically = true
    /// Bascule « Toutes les 2 minutes ».
    var periodicCapture: Duration?
    /// Ce que l'utilisateur a réglé à la main : changer de type de réunion ne
    /// le réécrit pas.
    var tuning = CaptureTuning()
    /// Vrai une fois les défauts du type appliqués : les rejouer à chaque
    /// ouverture écraserait les bascules qu'on vient de toucher.
    var didApplyKindDefaults = false

    /// La capture sélectionnée dans la bande (bordure 2 px `accent/action`).
    var selectedCaptureID: UUID?

    /// Intervalle de la bascule périodique (spec §5.1 : « Toutes les 2 minutes »).
    static let periodicInterval: Duration = .seconds(120)

    // MARK: - Défauts par type de réunion

    /// Applique les défauts du type, une seule fois par écran, en épargnant les
    /// bascules déjà touchées à la main (`CaptureTuning`).
    func applyDefaultsIfNeeded(for kind: MeetingKind) {
        guard !didApplyKindDefaults else { return }
        didApplyKindDefaults = true
        let profil = kind.captureProfile
        if !tuning.contains(.automaticDetection) { detectsAutomatically = profil.detectsAutomatically }
        if !tuning.contains(.periodicCapture) { periodicCapture = profil.periodicCapture }
    }

    func setAutomaticDetection(_ enabled: Bool) {
        detectsAutomatically = enabled
        tuning.markTouched(.automaticDetection)
    }

    func setPeriodicCapture(_ interval: Duration?) {
        periodicCapture = interval
        tuning.markTouched(.periodicCapture)
    }

    /// Retient la source choisie et la garde à jour quand le catalogue se
    /// reconstruit : l'identifiant de fenêtre change à chaque relance de Teams,
    /// et une sélection figée capturerait une fenêtre qui n'existe plus.
    func refresh(options nouvelles: [CaptureSourceOption]) {
        options = nouvelles
        if let courante = selected {
            selected = nouvelles.first { $0.source == courante.source } ?? courante
        }
    }

    // MARK: - Décisions pures

    /// L'état de la pilule de la barre du haut (spec §5.2).
    ///
    /// Dérivé, jamais stocké : un état de pilule tenu à part finirait par
    /// annoncer une capture armée sur une session close.
    static func pill(sessionOpen: Bool,
                     sourceLost: Bool,
                     source: CaptureSource?,
                     count: Int,
                     automatic: Bool) -> CapturePillState {
        guard sessionOpen else { return .idle }
        if sourceLost { return .lost(count: count) }
        return .armed(source: source ?? .screen, count: count, automatic: automatic)
    }

    /// Ce que fait `⌘⇧S` (spec §5.1 : « première utilisation ; ensuite `⌘⇧S`
    /// capture directement la dernière source valide »).
    enum ShortcutOutcome: Equatable, Sendable {
        /// Ouvrir le sélecteur : aucune source valide n'est encore choisie.
        case openSelector
        /// Capturer tout de suite sur la source retenue.
        case captureNow
    }

    /// - Parameters:
    ///   - selected: la source retenue, `nil` à la première utilisation.
    ///   - sourceLost: la source retenue a disparu — on rouvre le sélecteur
    ///     plutôt que de capturer dans le vide.
    static func shortcutOutcome(selected: CaptureSourceOption?,
                                sourceLost: Bool) -> ShortcutOutcome {
        guard let selected, selected.isActive, !sourceLost else { return .openSelector }
        return .captureNow
    }

    /// Sous-titre de la bande et de l'en-tête du sélecteur : `3 · source Teams`
    /// (capture 4a). Sans source choisie, on ne prétend pas en avoir une.
    static func stripSubtitle(count: Int, source: CaptureSource?) -> String {
        guard let source else { return "\(count) · aucune source" }
        return "\(count) · source \(source.label)"
    }

    /// L'explication affichée quand la première bascule est indisponible
    /// (spec §5.1 : « une source inactive rend la première bascule
    /// indisponible **avec l'explication** »).
    static func automaticUnavailableReason(for option: CaptureSourceOption?) -> String? {
        guard let option else {
            return "Choisissez d'abord une source : sans fenêtre à lire, il n'y a pas de partage à détecter."
        }
        guard !option.supportsAutomaticDetection else { return nil }
        return "\(option.title) n'a aucune fenêtre à lire : la détection de changement de partage restera sans effet."
    }
}
