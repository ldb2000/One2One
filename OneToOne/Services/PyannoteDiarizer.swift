import Foundation
import AVFoundation
import os

#if canImport(SpeechVAD)
import SpeechVAD
#endif

private let diarLog = Logger(subsystem: "com.onetoone.app", category: "PyannoteDiarizer")

/// Drapeau d'annulation partagé entre la Task parente et le worker MLX détaché.
/// `Task.detached` casse la propagation structured concurrency, donc on relaie
/// l'annulation via cette boîte atomique consultée dans `progressHandler`.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }
    func markCancelled() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
}

/// Wraps speech-swift's `PyannoteDiarizationPipeline`.
/// Provides:
/// - turns: [(startSec, endSec, clusterID)]
/// - perClusterEmbedding: [clusterID: 256-dim Float] (taken directly from
///   `DiarizationResult.speakerEmbeddings`).
@MainActor
final class PyannoteDiarizer {

    static let shared = PyannoteDiarizer()

    #if canImport(SpeechVAD)
    private var pipeline: PyannoteDiarizationPipeline?
    #endif

    struct DiarizeOutput: Sendable {
        let turns: [TurnAligner.DiarTurn]
        let perClusterEmbedding: [Int: [Float]]
    }

    private init() {}

    /// Lazy-load the pipeline on first call. Triggers HuggingFace download
    /// on first run (cached afterwards). `onPhase` is called with `.loadingModel`
    /// before the (potentially slow) `fromPretrained` step, then `.diarizing`
    /// once compute starts. `onProgress` reports (fraction 0..1, status string)
    /// during both download (first call) and diarization stages.
    func diarize(audioURL: URL,
                 clusterThreshold: Float? = nil,
                 onPhase: ((TranscriptionPhase) -> Void)? = nil,
                 onProgress: ((Double, String) -> Void)? = nil) async throws -> DiarizeOutput {
        #if canImport(SpeechVAD)
        if pipeline == nil {
            diarLog.info("loading PyannoteDiarizationPipeline (first call)")
            onPhase?(.loadingModel)
            pipeline = try await PyannoteDiarizationPipeline.fromPretrained(
                useVADFilter: true,
                progressHandler: { fraction, status in
                    onProgress?(fraction, status)
                }
            )
        }
        onPhase?(.diarizing)
        onProgress?(0.0, "Préparation de l'audio")
        guard let pipeline else {
            throw NSError(domain: "PyannoteDiarizer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "pipeline unavailable"])
        }

        // Run AVAudio load + MLX compute OFF the main actor — they're CPU-heavy
        // (30-60s for 25min audio) and would freeze the UI otherwise.
        struct SendableBox: @unchecked Sendable { let value: PyannoteDiarizationPipeline }
        let boxed = SendableBox(value: pipeline)
        let url = audioURL
        var diarConfig = DiarizationConfig.default
        if let ct = clusterThreshold { diarConfig.clusteringThreshold = ct }
        let configToUse = diarConfig
        let progressForward: (@Sendable (Double, String) -> Void)? = onProgress.map { handler in
            { fraction, status in
                Task { @MainActor in handler(fraction, status) }
            }
        }

        // Capture la cancellation parente pour la propager au worker MLX :
        // `Task.detached` n'hérite pas de la structured concurrency, donc on
        // pose un flag atomique qu'on consulte dans le progressHandler.
        let cancelFlag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                progressForward?(0.02, "Lecture du fichier audio")
                let samples = try Self.loadMono16k(url: url)
                try Task.checkCancellation()
                progressForward?(0.05, "Démarrage de la diarisation")
                let result = boxed.value.diarize(
                    audio: samples,
                    sampleRate: 16000,
                    config: configToUse,
                    progressHandler: { fraction, status in
                        // 0.05–0.95 range to leave headroom for post-processing.
                        let scaled = 0.05 + Double(fraction) * 0.90
                        progressForward?(scaled, status)
                        return !cancelFlag.isCancelled
                    }
                )
                try Task.checkCancellation()
                progressForward?(0.96, "Finalisation")

                let turns = result.segments.map { seg in
                    TurnAligner.DiarTurn(
                        startSec: Double(seg.startTime),
                        endSec: Double(seg.endTime),
                        clusterID: seg.speakerId
                    )
                }
                var embeddings: [Int: [Float]] = [:]
                for (idx, emb) in result.speakerEmbeddings.enumerated() {
                    embeddings[idx] = emb
                }
                progressForward?(1.0, "Terminé")
                diarLog.info("diarize done turns=\(turns.count) speakers=\(result.numSpeakers)")
                return DiarizeOutput(turns: turns, perClusterEmbedding: embeddings)
            }.value
        } onCancel: {
            cancelFlag.markCancelled()
            diarLog.info("diarize cancelled by parent task")
        }
        #else
        throw NSError(domain: "PyannoteDiarizer", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "SpeechVAD non disponible — speech-swift pas linké."])
        #endif
    }

    /// Loads WAV/M4A and returns 16 kHz mono Float32 samples via AVAudioEngine
    /// (resamples + downmixes if needed). Non-isolated so it can run from a
    /// `Task.detached` block off the main actor.
    nonisolated private static func loadMono16k(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { throw NSError(domain: "PyannoteDiarizer", code: 2) }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "PyannoteDiarizer", code: 4)
        }
        let frameCapacity = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCapacity),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(frameCapacity) * 16000.0 / inFormat.sampleRate) + 1024) else {
            throw NSError(domain: "PyannoteDiarizer", code: 3)
        }
        try file.read(into: inBuf)

        var error: NSError?
        var consumed = false
        _ = converter.convert(to: outBuf, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuf
        }
        if let error { throw error }

        let n = Int(outBuf.frameLength)
        guard let ptr = outBuf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: n))
    }
}
