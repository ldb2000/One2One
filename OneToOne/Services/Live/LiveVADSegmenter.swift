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
    private var lastSpeechEnd: Double = 0
    // Noise floor glissant pour le fallback.
    private var noiseFloor: Float = 0.005

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
        lastSpeechEnd = 0
        noiseFloor = 0.005
    }

    /// Segments de parole clos détectés dans ce buffer.
    func feed(_ samples: [Float], sampleRate: Double) -> [ClosedRange<Double>] {
        #if canImport(SpeechVAD)
        if useSilero, let processor {
            let events = processor.process(samples: samples)
            elapsedSeconds += Double(samples.count) / sampleRate
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
        var closed: [ClosedRange<Double>] = []
        var i = 0
        while i + frameSamples <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress!.advanced(by: i), 1, &rms, vDSP_Length(frameSamples))
            }
            let frameDur = Double(frameSamples) / sampleRate
            elapsedSeconds += frameDur
            // Noise floor glissant (EMA lente).
            noiseFloor = 0.995 * noiseFloor + 0.005 * rms
            let threshold = max(0.005, noiseFloor * 1.5)
            if rms >= threshold {
                if speechOpenStart == nil { speechOpenStart = elapsedSeconds - frameDur }
                silenceAccumulated = 0
            } else if speechOpenStart != nil {
                silenceAccumulated += frameDur
                if silenceAccumulated >= Double(minSilenceSeconds) {
                    let start = speechOpenStart!
                    closed.append(contentsOf: splitLongWindow(start...(elapsedSeconds - silenceAccumulated)))
                    speechOpenStart = nil
                    silenceAccumulated = 0
                }
            }
            i += frameSamples
        }
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
