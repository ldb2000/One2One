import Testing
import Foundation
@testable import OneToOne

/// Le mixage jette de l'information si on n'y prend pas garde : une fois les
/// deux pistes sommées, plus rien ne dit qui parlait. Ces tests verrouillent
/// les deux moitiés du contrat — un mixage qui ne sature pas, et une
/// chronologie qui conserve la provenance.
@Suite("AudioTrackMixer — mixage et provenance")
struct AudioTrackMixerTests {

    // MARK: - Mixage

    @Test("Deux pistes de même longueur sont sommées échantillon par échantillon")
    func mixesEqualLengths() {
        #expect(AudioTrackMixer.mix(mic: [0.1, 0.2], system: [0.3, 0.4]) == [0.4, 0.6])
    }

    @Test("La somme est bornée à ±1 : jamais de saturation destructive")
    func clampsToUnitRange() {
        #expect(AudioTrackMixer.mix(mic: [0.9, -0.9], system: [0.8, -0.8]) == [1.0, -1.0])
    }

    @Test("Une piste absente laisse l'autre intacte")
    func passthroughWhenOneTrackEmpty() {
        #expect(AudioTrackMixer.mix(mic: [0.5, -0.25], system: []) == [0.5, -0.25])
        #expect(AudioTrackMixer.mix(mic: [], system: [0.5, -0.25]) == [0.5, -0.25])
    }

    @Test("Des longueurs inégales n'introduisent pas de décalage : la plus courte est complétée de silence")
    func padsShorterTrack() {
        #expect(AudioTrackMixer.mix(mic: [0.5, 0.5, 0.5], system: [0.5]) == [1.0, 0.5, 0.5])
    }

    @Test("Deux pistes vides donnent un buffer vide")
    func bothEmpty() {
        #expect(AudioTrackMixer.mix(mic: [], system: []).isEmpty)
    }

    // MARK: - Énergie

    @Test("Le RMS d'un silence est nul, celui d'un signal plein vaut 1")
    func rmsBounds() {
        #expect(AudioTrackMixer.rms([0, 0, 0]) == 0)
        #expect(AudioTrackMixer.rms([1, -1, 1, -1]) == 1)
    }

    @Test("Le RMS d'un buffer vide est nul plutôt qu'indéfini")
    func rmsOfEmptyIsZero() {
        #expect(AudioTrackMixer.rms([]) == 0)
    }

    // MARK: - Prélèvement aligné

    @Test("Le prélèvement ne dépasse jamais la taille du bloc micro")
    func takeNeverExceedsMicBlock() {
        var pending: [Float] = [1, 2, 3, 4, 5]
        let taken = AudioTrackMixer.takeAligned(from: &pending, count: 3)
        #expect(taken == [1, 2, 3])
        #expect(pending == [4, 5])
    }

    @Test("Un reliquat court est prélevé en entier, le silence comblera")
    func shortPendingIsTakenWhole() {
        var pending: [Float] = [1, 2]
        let taken = AudioTrackMixer.takeAligned(from: &pending, count: 8)
        #expect(taken == [1, 2])
        #expect(pending.isEmpty)
    }

    @Test("Le reliquat est borné en jetant le plus ancien")
    func remainderIsCappedDroppingOldest() {
        var pending = [Float](repeating: 0, count: 10) + [1, 2, 3]
        _ = AudioTrackMixer.takeAligned(from: &pending, count: 0, capRemainder: 3)
        #expect(pending == [1, 2, 3])
    }

    // MARK: - Provenance

    private let timeline: [TrackEnergySample] = [
        TrackEnergySample(time: 0.0, micEnergy: 0.40, systemEnergy: 0.01),
        TrackEnergySample(time: 1.0, micEnergy: 0.35, systemEnergy: 0.02),
        TrackEnergySample(time: 2.0, micEnergy: 0.01, systemEnergy: 0.50),
        TrackEnergySample(time: 3.0, micEnergy: 0.02, systemEnergy: 0.45),
        TrackEnergySample(time: 4.0, micEnergy: 0.30, systemEnergy: 0.28),
        TrackEnergySample(time: 5.0, micEnergy: 0.001, systemEnergy: 0.001)
    ]

    @Test("Le micro domine → c'est moi qui parle")
    func micDominanceIsMe() {
        #expect(AudioTrackMixer.provenance(forRange: 0.0...1.0, in: timeline) == .me)
    }

    @Test("L'audio système domine → c'est l'interlocuteur distant")
    func systemDominanceIsRemote() {
        #expect(AudioTrackMixer.provenance(forRange: 2.0...3.0, in: timeline) == .remote)
    }

    @Test("Deux pistes d'énergie comparable → on ne tranche pas")
    func comparableEnergiesAreMixed() {
        #expect(AudioTrackMixer.provenance(forRange: 4.0...4.0, in: timeline) == .mixed)
    }

    @Test("Le silence n'est attribué à personne")
    func silenceIsUnknown() {
        #expect(AudioTrackMixer.provenance(forRange: 5.0...5.0, in: timeline) == .unknown)
    }

    @Test("Un intervalle hors chronologie n'est attribué à personne")
    func rangeOutsideTimelineIsUnknown() {
        #expect(AudioTrackMixer.provenance(forRange: 90.0...95.0, in: timeline) == .unknown)
        #expect(AudioTrackMixer.provenance(forRange: 0.0...1.0, in: []) == .unknown)
    }
}
