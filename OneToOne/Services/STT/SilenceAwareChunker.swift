import Foundation

/// Découpe un signal 16 kHz mono en morceaux d'environ une minute dont les
/// frontières tombent sur le creux d'énergie le plus proche de la cible — au
/// lieu de couper au milieu d'un mot à 60 s pile. Inspiré du pipeline
/// d'import d'Open WebUI (`split_on_silence`), adapté à un STT par fenêtres.
///
/// Fonctions pures : pas d'I/O, pas de MLX — testables sur des signaux
/// synthétiques.
enum SilenceAwareChunker {

    /// Taille de trame pour la mesure d'énergie : 200 ms à 16 kHz.
    static let frameSamples = 3_200
    /// Longueur visée d'un morceau : 60 s, comme les fenêtres historiques.
    static let targetChunkSamples = 60 * 16_000
    /// Rayon de recherche du creux autour de la cible : ±5 s.
    static let searchRadiusSamples = 5 * 16_000

    /// Énergie RMS par trame de `frameSamples`. La dernière trame, incomplète,
    /// est mesurée sur ce qu'il reste.
    static func frameEnergies(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var energies: [Float] = []
        energies.reserveCapacity(samples.count / frameSamples + 1)
        var start = 0
        while start < samples.count {
            let end = min(start + frameSamples, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            energies.append((sum / Float(end - start)).squareRoot())
            start = end
        }
        return energies
    }

    /// Bornes des morceaux couvrant `0..<sampleCount`, contiguës et sans
    /// recouvrement. Chaque frontière est posée au début de la trame la moins
    /// énergique dans `[cible − rayon, cible + rayon]` ; à égalité, la
    /// première gagne (déterministe).
    static func chunkRanges(sampleCount: Int,
                            energies: [Float],
                            frameSamples: Int = frameSamples,
                            targetChunkSamples: Int = targetChunkSamples,
                            searchRadiusSamples: Int = searchRadiusSamples) -> [Range<Int>] {
        guard sampleCount > 0 else { return [] }
        var ranges: [Range<Int>] = []
        var cursor = 0
        // Tant qu'il reste plus d'un morceau « cible + rayon », on coupe ; le
        // reste part d'un bloc — jamais de miette finale d'une poignée de
        // secondes, que Whisper hallucinerait.
        while sampleCount - cursor > targetChunkSamples + searchRadiusSamples {
            let target = cursor + targetChunkSamples
            let windowStart = max(cursor + frameSamples, target - searchRadiusSamples)
            let windowEnd = min(sampleCount - frameSamples, target + searchRadiusSamples)
            var bestBoundary = target
            var bestEnergy = Float.greatestFiniteMagnitude
            var frame = windowStart / frameSamples
            while frame * frameSamples <= windowEnd {
                let boundary = frame * frameSamples
                if boundary > cursor, frame < energies.count, energies[frame] < bestEnergy {
                    bestEnergy = energies[frame]
                    bestBoundary = boundary
                }
                frame += 1
            }
            ranges.append(cursor..<bestBoundary)
            cursor = bestBoundary
        }
        ranges.append(cursor..<sampleCount)
        return ranges
    }
}
