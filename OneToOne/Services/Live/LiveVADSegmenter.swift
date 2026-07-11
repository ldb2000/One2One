import Foundation
import Accelerate
#if canImport(SpeechVAD)
import SpeechVAD
#endif

/// Découpe le flux audio en segments de parole aux frontières de silence.
/// Stratégie principale : Silero VAD v5 (backend CoreML / Neural Engine — ne
/// sollicite pas le GPU). Repli : détection d'énergie (RMS) + longueur max de
/// fenêtre, si Silero n'est pas chargeable (hors-ligne, modèle absent).
actor LiveVADSegmenter {

    private let minSilenceSeconds: Float
    private let maxWindowSeconds: Double

    #if canImport(SpeechVAD)
    private var processor: StreamingVADProcessor?
    #endif
    private var useSilero = false

    // État commun / fallback RMS
    private var elapsedSeconds: Double = 0
    private var speechOpenStart: Double?
    private var silenceAccumulated: Double = 0
    // Noise floor glissant pour le fallback.
    private var noiseFloor: Float = 0.005
    // Samples résiduels (< une frame) reportés d'un appel de feedRMS à l'autre.
    private var pendingSamples: [Float] = []

    init(minSilenceSeconds: Float = 0.6, maxWindowSeconds: Double = 30) {
        self.minSilenceSeconds = minSilenceSeconds
        self.maxWindowSeconds = maxWindowSeconds
    }

    func loadSilero() async -> Bool {
        #if canImport(SpeechVAD)
        do {
            let model = try await SileroVADModel.fromPretrained(engine: .coreml)
            var config = VADConfig.sileroDefault
            config.minSilenceDuration = minSilenceSeconds
            processor = StreamingVADProcessor(model: model, config: config)
            useSilero = true
            return true
        } catch {
            useSilero = false
            return false
        }
        #else
        return false
        #endif
    }

    func reset() {
        #if canImport(SpeechVAD)
        processor?.reset()
        #endif
        elapsedSeconds = 0
        speechOpenStart = nil
        silenceAccumulated = 0
        noiseFloor = 0.005
        pendingSamples = []
    }

    /// Segments de parole clos détectés dans ce buffer.
    func feed(_ samples: [Float], sampleRate: Double) -> [ClosedRange<Double>] {
        #if canImport(SpeechVAD)
        if useSilero, let processor {
            let events = processor.process(samples: samples)
            var out: [ClosedRange<Double>] = []
            for e in events {
                if case let .speechEnded(segment) = e {
                    out.append(Double(segment.startTime)...Double(segment.endTime))
                }
            }
            return out.flatMap { splitLongWindow($0) }
        }
        #endif
        return feedRMS(samples, sampleRate: sampleRate)
    }

    func flush() -> [ClosedRange<Double>] {
        #if canImport(SpeechVAD)
        if useSilero, let processor {
            let events = processor.flush()
            var out: [ClosedRange<Double>] = []
            for e in events {
                if case let .speechEnded(segment) = e {
                    out.append(Double(segment.startTime)...Double(segment.endTime))
                }
            }
            return out.flatMap { splitLongWindow($0) }
        }
        #endif
        if let start = speechOpenStart, elapsedSeconds > start {
            speechOpenStart = nil
            return splitLongWindow(start...elapsedSeconds)
        }
        return []
    }

    // MARK: - Fallback RMS
    private func feedRMS(_ samples: [Float], sampleRate: Double) -> [ClosedRange<Double>] {
        let frameSamples = max(1, Int(0.030 * sampleRate))
        // Préfixer les samples résiduels laissés par l'appel précédent : aucune
        // donnée n'est perdue même si les buffers ne sont pas multiples de frameSamples.
        let combined = pendingSamples + samples
        var closed: [ClosedRange<Double>] = []
        var i = 0
        while i + frameSamples <= combined.count {
            var rms: Float = 0
            combined.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress!.advanced(by: i), 1, &rms, vDSP_Length(frameSamples))
            }
            let frameDur = Double(frameSamples) / sampleRate
            elapsedSeconds += frameDur
            // Seuil calculé à partir du plancher de bruit AVANT toute mise à jour,
            // pour que le plancher ne poursuive pas le signal pendant la parole.
            let threshold = max(0.005, noiseFloor * 1.5)
            if rms >= threshold {
                if speechOpenStart == nil { speechOpenStart = elapsedSeconds - frameDur }
                silenceAccumulated = 0
            } else {
                // Frame de silence : seul cas où le plancher de bruit est mis à jour (EMA lente).
                noiseFloor = 0.995 * noiseFloor + 0.005 * rms
                if speechOpenStart != nil {
                    silenceAccumulated += frameDur
                    if silenceAccumulated >= Double(minSilenceSeconds) {
                        let start = speechOpenStart!
                        closed.append(contentsOf: splitLongWindow(start...(elapsedSeconds - silenceAccumulated)))
                        speechOpenStart = nil
                        silenceAccumulated = 0
                    }
                }
            }
            i += frameSamples
        }
        // Conserver les samples résiduels (< une frame) pour le prochain appel.
        pendingSamples = Array(combined[i...])
        // Forcer une coupe si la fenêtre ouverte dépasse maxWindowSeconds.
        if let start = speechOpenStart, elapsedSeconds - start >= maxWindowSeconds {
            closed.append(contentsOf: splitLongWindow(start...elapsedSeconds))
            speechOpenStart = elapsedSeconds
        }
        return closed
    }

    /// Scinde un segment plus long que maxWindowSeconds en tranches successives.
    private func splitLongWindow(_ range: ClosedRange<Double>) -> [ClosedRange<Double>] {
        guard range.upperBound - range.lowerBound > maxWindowSeconds else { return [range] }
        var out: [ClosedRange<Double>] = []
        var s = range.lowerBound
        while s < range.upperBound {
            let e = min(s + maxWindowSeconds, range.upperBound)
            out.append(s...e)
            s = e
        }
        return out
    }
}
