import CoreGraphics
import Foundation

/// Toutes les valeurs numériques réglables de la capture de slides, en un seul endroit.
struct SlideCaptureSettings: Equatable, Sendable {

    /// Sensibilité de la détection de **mouvement**. Plus elle est élevée, plus le seuil
    /// de changement est bas. Elle n'agit pas sur l'anti-doublon (`identityThreshold`).
    enum Sensitivity: String, CaseIterable, Identifiable, Sendable {
        case low, normal, high

        var id: String { rawValue }

        /// Écart moyen normalisé (image N contre N−1) à partir duquel « ça bouge ».
        /// Points de départ issus de la spec source, à affiner sur une réunion réelle.
        var movementThreshold: Double {
            switch self {
            case .high: return 0.010
            case .normal: return 0.020
            case .low: return 0.045
            }
        }

        var label: String {
            switch self {
            case .high: return "Élevée"
            case .normal: return "Normale"
            case .low: return "Faible"
            }
        }
    }

    /// Période de polling de la source.
    var tickInterval: Duration = .milliseconds(500)

    /// Ticks stables consécutifs exigés avant d'écrire. À 500 ms par tick, 2 laisse
    /// environ une seconde à une transition animée pour se terminer.
    var stableTicksRequired: Int = 2

    var sensitivity: Sensitivity = .normal

    var movementThreshold: Double { sensitivity.movementThreshold }

    /// Seuil d'**identité** pour l'anti-doublon (image contre l'historique enregistré).
    /// Indépendant de la sensibilité : la coupler rendait l'anti-doublon laxiste quand
    /// on augmentait la sensibilité (piège 5 de la spec source).
    var identityThreshold: Double = 0.020

    /// Une fenêtre plus petite ne peut pas contenir un slide lisible.
    static let minimumWindowSide: CGFloat = 200

    init(sensitivity: Sensitivity = .normal) {
        self.sensitivity = sensitivity
    }
}
