import Foundation
import AVFoundation
import Accelerate
import os

private let diarLog = Logger(subsystem: "com.onetoone.app", category: "diarization")

/// Diarization MVP : pas de clustering audio profond pour V1 (pas de modèle
/// d'embedding téléchargé). Approche pragmatique :
///
/// 1. **VAD énergie-based** : analyse l'audio par fenêtres de 30ms, calcule
///    l'énergie RMS, repère les frontières silence/voix > 0.8s comme tours
///    de parole potentiels.
/// 2. **Découpe les segments** existants (60s Whisper) en sous-segments
///    basés sur ces frontières.
/// 3. **Assigne `speakerID` heuristique** : alterne 1/2 à chaque tour détecté.
///    C'est intentionnellement simpliste — l'utilisateur reassign via la UI.
///
/// Pour avoir une vraie diarization (qui parle vraiment), ajouter plus tard
/// un modèle d'embedding speaker (ECAPA-TDNN exporté MLX/CoreML) + clustering.
enum DiarizationService {

    /// Min silence duration (in seconds) qui marque un changement de tour.
    static let minTurnSilence: Double = 0.8

    /// RMS threshold below which a frame is considered silence. Computed
    /// dynamically from a noise floor estimate; fallback fixed value if
    /// estimation fails.
    static let silenceFallback: Float = 0.005

    /// Run a basic energy-based VAD on the WAV at `audioURL` and return an
    /// alternating speaker turn assignment. Each Output segment carries:
    /// `(startSeconds, endSeconds, speakerID)`. Always non-throwing — empty
    /// array on error.
    static func detectTurns(audioURL: URL, totalDurationSec: Double) -> [(start: Double, end: Double, speakerID: Int)] {
        do {
            let file = try AVAudioFile(forReading: audioURL)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                diarLog.error("detectTurns: unable to alloc PCM buffer")
                return fallbackSingleTurn(durationSec: totalDurationSec)
            }
            try file.read(into: buf)
            return detectTurnsFromBuffer(buf, totalDurationSec: totalDurationSec)
        } catch {
            diarLog.error("detectTurns: \(error.localizedDescription, privacy: .public)")
            return fallbackSingleTurn(durationSec: totalDurationSec)
        }
    }

    private static func detectTurnsFromBuffer(
        _ buf: AVAudioPCMBuffer,
        totalDurationSec: Double
    ) -> [(start: Double, end: Double, speakerID: Int)] {
        guard let channelData = buf.floatChannelData else {
            return fallbackSingleTurn(durationSec: totalDurationSec)
        }
        let sampleRate = buf.format.sampleRate
        let frameLength = Int(buf.frameLength)
        let frameSamples = max(1, Int(0.030 * sampleRate))   // 30ms windows
        let mono = channelData[0]

        // Compute RMS per frame.
        var rmsValues: [Float] = []
        rmsValues.reserveCapacity(frameLength / frameSamples + 1)
        var i = 0
        while i + frameSamples <= frameLength {
            var rms: Float = 0
            vDSP_rmsqv(mono.advanced(by: i), 1, &rms, vDSP_Length(frameSamples))
            rmsValues.append(rms)
            i += frameSamples
        }

        // Estimate silence threshold = 1.5× the 10th percentile of RMS values
        // (assumes < 10% of frames are silence-like, gives a noise floor).
        let sorted = rmsValues.sorted()
        let p10 = sorted.isEmpty ? silenceFallback : sorted[max(0, sorted.count / 10)]
        let threshold = max(silenceFallback, p10 * 1.5)
        diarLog.info("VAD: rmsCount=\(rmsValues.count, privacy: .public) p10=\(p10, privacy: .public) threshold=\(threshold, privacy: .public)")

        // Walk frames. A "turn boundary" is any silence stretch ≥ minTurnSilence.
        // Between two boundaries we have a turn.
        let frameDuration = Double(frameSamples) / sampleRate
        let minSilenceFrames = Int(minTurnSilence / frameDuration)

        var turns: [(start: Double, end: Double)] = []
        var inSpeech = false
        var speechStartFrame = 0
        var silenceFrames = 0

        for (idx, rms) in rmsValues.enumerated() {
            let isSilent = rms < threshold
            if inSpeech {
                if isSilent {
                    silenceFrames += 1
                    if silenceFrames >= minSilenceFrames {
                        // close the current turn at the start of the silence
                        let endIdx = idx - silenceFrames + 1
                        let s = Double(speechStartFrame) * frameDuration
                        let e = Double(max(speechStartFrame + 1, endIdx)) * frameDuration
                        turns.append((s, e))
                        inSpeech = false
                        silenceFrames = 0
                    }
                } else {
                    silenceFrames = 0
                }
            } else if !isSilent {
                inSpeech = true
                speechStartFrame = idx
                silenceFrames = 0
            }
        }
        if inSpeech {
            let s = Double(speechStartFrame) * frameDuration
            turns.append((s, totalDurationSec))
        }

        if turns.isEmpty {
            return fallbackSingleTurn(durationSec: totalDurationSec)
        }

        // Assign alternating speaker IDs. Simplistic heuristic for V1.
        let withSpeakers: [(start: Double, end: Double, speakerID: Int)] = turns.enumerated().map { (idx, t) in
            (t.start, t.end, (idx % 2) + 1)
        }
        diarLog.info("VAD: \(withSpeakers.count) turns detected")
        return withSpeakers
    }

    private static func fallbackSingleTurn(durationSec: Double) -> [(start: Double, end: Double, speakerID: Int)] {
        [(0, durationSec, 1)]
    }
}
