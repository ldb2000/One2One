import Testing
import Foundation
@testable import OneToOne

/// Couper à 60 s pile tombe au milieu d'un mot ; couper au creux d'énergie le
/// plus proche tombe entre deux phrases. Ces tests verrouillent le contrat :
/// couverture totale, aucun recouvrement, frontière dans la fenêtre de
/// recherche, et sur le creux quand il existe.
@Suite("SilenceAwareChunker — frontières sur les silences")
struct SilenceAwareChunkerTests {

    /// Signal déterministe : `seconds` de « voix » (sinusoïde d'amplitude 0,5).
    private func voice(seconds: Int) -> [Float] {
        (0..<(seconds * 16_000)).map { 0.5 * sin(Float($0) * 0.3) }
    }

    private func silence(seconds: Int) -> [Float] {
        [Float](repeating: 0, count: seconds * 16_000)
    }

    // MARK: - Énergie par trame

    @Test("Le silence a une énergie nulle, la voix non")
    func energiesSeparateSilenceFromVoice() {
        let energies = SilenceAwareChunker.frameEnergies(voice(seconds: 1) + silence(seconds: 1))
        let half = energies.count / 2
        #expect(energies.prefix(half).allSatisfy { $0 > 0.1 })
        #expect(energies.suffix(half).allSatisfy { $0 < 0.001 })
    }

    @Test("Un signal vide n'a pas de trames")
    func emptySignalHasNoFrames() {
        #expect(SilenceAwareChunker.frameEnergies([]).isEmpty)
    }

    @Test("La dernière trame, incomplète, est mesurée quand même")
    func partialLastFrameIsMeasured() {
        let energies = SilenceAwareChunker.frameEnergies(
            [Float](repeating: 0.5, count: SilenceAwareChunker.frameSamples + 100))
        #expect(energies.count == 2)
        #expect(energies[1] > 0.1)
    }

    // MARK: - Bornes des morceaux

    private func ranges(for samples: [Float]) -> [Range<Int>] {
        SilenceAwareChunker.chunkRanges(sampleCount: samples.count,
                                        energies: SilenceAwareChunker.frameEnergies(samples))
    }

    @Test("Un signal court tient dans un seul morceau")
    func shortSignalIsOneChunk() {
        let samples = voice(seconds: 30)
        #expect(ranges(for: samples) == [0..<samples.count])
    }

    @Test("La frontière tombe dans le trou de silence proche de la cible")
    func boundaryLandsInTheSilenceGap() {
        // 57 s de voix, 2 s de silence, 60 s de voix : la cible à 60 s a un
        // creux à portée (57–59 s, dans le rayon de ±5 s). Total 119 s : après
        // la coupe à 57 s il reste 62 s, sous le seuil « cible + rayon » (65 s),
        // donc exactement deux morceaux — pas de troisième coupe forcée.
        let samples = voice(seconds: 57) + silence(seconds: 2) + voice(seconds: 60)
        let result = ranges(for: samples)
        #expect(result.count == 2)
        let boundary = result[0].upperBound
        #expect(boundary >= 57 * 16_000 && boundary <= 59 * 16_000,
                "la coupe doit tomber dans le silence, pas à 60 s pile")
    }

    @Test("Sans creux à portée, la frontière reste dans la fenêtre de recherche")
    func withoutGapBoundaryStaysInWindow() {
        let samples = voice(seconds: 130)
        let result = ranges(for: samples)
        #expect(result.count >= 2)
        let boundary = result[0].upperBound
        #expect(boundary >= 55 * 16_000 && boundary <= 65 * 16_000)
    }

    @Test("Les morceaux couvrent tout le signal, sans recouvrement ni trou")
    func chunksTileTheSignal() {
        for seconds in [30, 61, 130, 200] {
            let samples = voice(seconds: 40) + silence(seconds: 1) + voice(seconds: max(0, seconds - 41))
            let result = ranges(for: samples)
            #expect(result.first?.lowerBound == 0)
            #expect(result.last?.upperBound == samples.count)
            for (a, b) in zip(result, result.dropFirst()) {
                #expect(a.upperBound == b.lowerBound)
                #expect(!a.isEmpty)
            }
        }
    }

    @Test("Un signal vide ne produit aucun morceau")
    func emptySignalHasNoChunks() {
        #expect(SilenceAwareChunker.chunkRanges(sampleCount: 0, energies: []).isEmpty)
    }
}
