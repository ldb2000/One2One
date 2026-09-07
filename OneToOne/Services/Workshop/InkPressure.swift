import AppKit
import Foundation

/// La pression du stylet du mode Manuscrit (spec §7.1 : « tracé
/// stylet/trackpad, **pression si disponible** »).
///
/// Pourquoi passer par AppKit et non par la page : dans un `WKWebView`, les
/// `PointerEvent` de macOS n'apportent pas la pression d'une tablette — le
/// moteur retombe alors sur `simulatePressure`, qui déduit l'épaisseur de la
/// vitesse du geste. La pression réelle, elle, arrive dans les `NSEvent`
/// (`pressure`, `.tabletPoint`). On la lit côté natif et on la **pousse** dans
/// la page (`setPressure`), qui la pose sur le tracé en cours avec
/// `simulatePressure = false`.
///
/// La règle de conversion est ici, pure et testée ; le geste lui-même demande
/// une tablette et n'est pas vérifiable en test (cf. `STATUS.md`).
enum InkPressure {

    /// Facteur d'épaisseur à pleine pression. 2,2 : un trait appuyé est
    /// nettement plus gras, sans devenir une tache.
    static let maximumFactor: Double = 2.2

    /// Facteur d'épaisseur à pression nulle. Non nul : un stylet posé sans
    /// appuyer doit laisser une trace, sinon le début de chaque trait manque.
    static let minimumFactor: Double = 0.35

    /// Normalise une pression brute d'`NSEvent`.
    ///
    /// - Returns: `nil` quand l'événement ne vient pas d'une tablette — une
    ///   souris rapporte une pression, mais c'est une constante (0 ou 1) qui ne
    ///   dit rien du geste. Épaisseur fixe dans ce cas, comme le veut la spec
    ///   (« pression **si disponible** »).
    static func normalized(raw: Double, isTablet: Bool) -> Double? {
        guard isTablet else { return nil }
        return min(1, max(0, raw))
    }

    /// L'épaisseur effective d'un trait : l'épaisseur choisie dans la barre
    /// d'outils, modulée par la pression. Sans pression, l'épaisseur choisie,
    /// inchangée.
    static func strokeWidth(base: Double, pressure: Double?) -> Double {
        guard let pressure else { return base }
        let borne = min(1, max(0, pressure))
        return base * (minimumFactor + (maximumFactor - minimumFactor) * borne)
    }
}

/// Le moniteur d'événements qui lit la pression du stylet.
///
/// `NSEvent.addLocalMonitorForEvents` est **enveloppé** derrière deux
/// fermetures injectables : le test alimente le moniteur à la main et vérifie
/// qu'il publie la dernière valeur et qu'il se retire à l'arrêt, sans qu'aucune
/// boucle d'événements AppKit ne tourne.
@MainActor
final class StylusPressureMonitor {

    /// Un échantillon lu sur un `NSEvent`.
    struct Sample: Equatable, Sendable {
        var pressure: Double
        /// Vrai pour un événement de tablette (`.tabletPoint`, ou une souris
        /// dont le sous-type est `tabletPoint`).
        var isTablet: Bool
    }

    /// Installe le moniteur et rend son jeton (celui d'AppKit, ou n'importe
    /// quoi en test).
    typealias Install = @MainActor (@escaping @MainActor (Sample) -> Void) -> Any?
    /// Retire le moniteur désigné par son jeton.
    typealias Teardown = @MainActor (Any) -> Void

    /// Dernière pression connue, déjà normalisée. `nil` = aucune tablette.
    private(set) var pressure: Double?

    private(set) var isRunning = false

    /// Appelé à chaque changement de pression — c'est par là que la page est
    /// prévenue.
    var onChange: (@MainActor (Double?) -> Void)?

    private let install: Install
    private let teardown: Teardown
    private var token: Any?

    init(install: Install? = nil, teardown: Teardown? = nil) {
        self.install = install ?? StylusPressureMonitor.installLocalMonitor
        self.teardown = teardown ?? StylusPressureMonitor.removeLocalMonitor
    }

    /// Démarre l'écoute. Idempotent : un remontage de la vue ne doit pas
    /// empiler un second moniteur.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        token = install { [weak self] echantillon in
            self?.receive(echantillon)
        }
    }

    /// Arrête l'écoute et oublie la pression : le prochain trait repart de
    /// l'épaisseur choisie, pas du dernier appui.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let token { teardown(token) }
        token = nil
        if pressure != nil {
            pressure = nil
            onChange?(nil)
        }
    }

    private func receive(_ echantillon: Sample) {
        let valeur = InkPressure.normalized(raw: echantillon.pressure,
                                            isTablet: echantillon.isTablet)
        guard valeur != pressure else { return }
        pressure = valeur
        onChange?(valeur)
    }

    // MARK: - AppKit

    /// Le vrai moniteur : les trois types d'événements qui portent une
    /// pression de stylet sur macOS.
    private static let installLocalMonitor: Install = { rappel in
        NSEvent.addLocalMonitorForEvents(
            matching: [.pressure, .tabletPoint, .leftMouseDragged]
        ) { event in
            let tablette = event.type == .tabletPoint || event.subtype == .tabletPoint
            MainActor.assumeIsolated {
                rappel(Sample(pressure: Double(event.pressure), isTablet: tablette))
            }
            // On observe, on n'intercepte pas : l'événement continue sa route
            // vers le `WKWebView`, qui dessine.
            return event
        }
    }

    private static let removeLocalMonitor: Teardown = { token in
        NSEvent.removeMonitor(token)
    }
}
