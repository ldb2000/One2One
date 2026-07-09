import Testing
import Foundation
@testable import OneToOne

/// Tests du chemin de repli RMS de `LiveVADSegmenter` (Silero non chargé
/// dans ces tests → `useSilero == false`, donc `feedRMS` est exercé).
struct LiveVADSegmenterTests {

    private let sampleRate: Double = 16_000

    /// Génère une sinusoïde analytique (déterministe) d'amplitude `amplitude`
    /// sur `count` samples, en continuant la phase depuis `startIndex`.
    private func tone(amplitude: Float, frequency: Double, startIndex: Int, count: Int) -> [Float] {
        (0..<count).map { n in
            let t = Double(startIndex + n) / sampleRate
            return amplitude * Float(sin(2 * Double.pi * frequency * t))
        }
    }

    /// Découpe un tableau en tranches de taille `chunkSize` (dernière tranche possiblement plus petite).
    private func chunks<T>(_ array: [T], of chunkSize: Int) -> [[T]] {
        var result: [[T]] = []
        var i = 0
        while i < array.count {
            let end = min(i + chunkSize, array.count)
            result.append(Array(array[i..<end]))
            i = end
        }
        return result
    }

    /// Défaut 2 : les buffers plus petits qu'une frame (480 samples à 16 kHz)
    /// ne doivent jamais être perdus grâce au tampon de report (`pendingSamples`).
    /// On nourrit un signal parole (~1.5 s) puis silence (~1 s) en tranches de 100
    /// samples (< frameSamples) et on vérifie qu'au moins un segment se clôt.
    @Test func residualSamplesAreBufferedAcrossSmallFeeds() async {
        let segmenter = LiveVADSegmenter()

        let speechSamples = Int(1.5 * sampleRate)
        let silenceSamples = Int(1.0 * sampleRate)
        let speech = tone(amplitude: 0.3, frequency: 300, startIndex: 0, count: speechSamples)
        let silence = [Float](repeating: 0, count: silenceSamples)
        let signal = speech + silence

        var closed: [ClosedRange<Double>] = []
        for chunk in chunks(signal, of: 100) {
            closed += await segmenter.feed(chunk, sampleRate: sampleRate)
        }
        closed += await segmenter.flush()

        #expect(!closed.isEmpty, "un segment de parole doit se clôturer même nourri par petites tranches")
    }

    /// Défaut 1 : le plancher de bruit ne doit pas poursuivre le signal pendant
    /// une parole continue et longue — sinon le seuil finit par dépasser le
    /// niveau de parole et le segment se referme faussement en cours de route.
    @Test func longContinuousSpeechIsNotChoppedByDriftingNoiseFloor() async {
        let segmenter = LiveVADSegmenter()

        let totalSamples = Int(20.0 * sampleRate)
        let signal = tone(amplitude: 0.3, frequency: 300, startIndex: 0, count: totalSamples)

        var closedDuringFeed: [ClosedRange<Double>] = []
        for chunk in chunks(signal, of: 1_600) {
            closedDuringFeed += await segmenter.feed(chunk, sampleRate: sampleRate)
        }

        #expect(closedDuringFeed.isEmpty, "aucun segment ne doit se clôturer au milieu d'une parole continue")

        let flushed = await segmenter.flush()
        #expect(flushed.count == 1)
        if let segment = flushed.first {
            let duration = segment.upperBound - segment.lowerBound
            #expect(duration > 19.9, "le segment final doit couvrir l'essentiel des 20 s de parole")
        }
    }
}
