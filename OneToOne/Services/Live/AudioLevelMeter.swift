import Foundation
import Accelerate

/// Calcul du niveau d'entrée (VU-mètre) à partir d'un buffer mono Float32.
/// Renvoie des dBFS (0 = pleine échelle), plancher fixé à −160 dB pour le
/// silence, afin de préserver le contrat des VU-mètres existants.
enum AudioLevelMeter {

    static let floor: Float = -160

    /// - Parameter samples: buffer mono Float32, amplitudes dans [−1, 1].
    /// - Returns: `(average, peak)` en dBFS.
    static func levels(from samples: [Float]) -> (average: Float, peak: Float) {
        guard !samples.isEmpty else { return (floor, floor) }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        var peakMagnitude: Float = 0
        vDSP_maxmgv(samples, 1, &peakMagnitude, vDSP_Length(samples.count))

        return (dBFS(rms), dBFS(peakMagnitude))
    }

    private static func dBFS(_ linear: Float) -> Float {
        guard linear > 0 else { return floor }
        return max(floor, 20 * log10(linear))
    }
}
