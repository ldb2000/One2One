import Foundation

/// Origine attribuée à un intervalle de la transcription.
///
/// Cette attribution ne vient **pas** de la diarisation : elle vient de la
/// piste d'origine, qu'on connaît gratuitement puisqu'on capture deux sources
/// séparées. `PyannoteDiarizer` reste chargé de séparer les voix *à
/// l'intérieur* de la piste distante (spec §4).
enum TrackProvenance: String, Equatable, Sendable {
    /// Micro dominant — l'utilisateur, ou quelqu'un dans la pièce.
    case me
    /// Audio système dominant — un participant à l'appel Teams.
    case remote
    /// Les deux pistes portent une énergie comparable : on ne tranche pas.
    case mixed
    /// Silence, ou intervalle hors chronologie.
    case unknown
}

/// Énergie des deux pistes à un instant donné, relative au début de
/// l'enregistrement.
struct TrackEnergySample: Equatable, Sendable {
    let time: TimeInterval
    let micEnergy: Float
    let systemEnergy: Float
}

/// Mixage de deux pistes et conservation de leur provenance. Fonctions pures :
/// aucun état, aucun framework audio, testables sans matériel.
enum AudioTrackMixer {

    /// En deçà de cette énergie moyenne cumulée, on considère qu'il ne se passe
    /// rien et on n'attribue pas l'intervalle.
    static let defaultSilenceThreshold: Float = 0.01
    /// Rapport d'énergie au-delà duquel une piste est dite dominante.
    static let defaultDominanceRatio: Float = 2.0

    /// Somme les deux pistes, échantillon par échantillon, en bornant à ±1.
    ///
    /// La piste la plus courte est complétée de silence plutôt que tronquée :
    /// tronquer décalerait tout ce qui suit, et un décalage cumulatif ruinerait
    /// l'alignement de la chronologie de provenance.
    static func mix(mic: [Float], system: [Float]) -> [Float] {
        if system.isEmpty { return mic }
        if mic.isEmpty { return system }
        let count = max(mic.count, system.count)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let a = i < mic.count ? mic[i] : 0
            let b = i < system.count ? system[i] : 0
            out[i] = max(-1, min(1, a + b))
        }
        return out
    }

    /// Énergie efficace du buffer, dans `[0, 1]`. Un buffer vide vaut 0 plutôt
    /// que `NaN`.
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// Attribue un intervalle de temps à une provenance, en comparant l'énergie
    /// cumulée des deux pistes sur cet intervalle.
    static func provenance(forRange range: ClosedRange<TimeInterval>,
                           in timeline: [TrackEnergySample],
                           silenceThreshold: Float = defaultSilenceThreshold,
                           dominanceRatio: Float = defaultDominanceRatio) -> TrackProvenance {
        let inRange = timeline.filter { range.contains($0.time) }
        guard !inRange.isEmpty else { return .unknown }

        let micTotal = inRange.reduce(Float(0)) { $0 + $1.micEnergy }
        let systemTotal = inRange.reduce(Float(0)) { $0 + $1.systemEnergy }
        let count = Float(inRange.count)
        guard (micTotal / count) >= silenceThreshold || (systemTotal / count) >= silenceThreshold else {
            return .unknown
        }
        if micTotal >= systemTotal * dominanceRatio { return .me }
        if systemTotal >= micTotal * dominanceRatio { return .remote }
        return .mixed
    }
}
