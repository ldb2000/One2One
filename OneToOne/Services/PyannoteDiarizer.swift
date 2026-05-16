import Foundation
import AVFoundation
import os

#if canImport(SpeechVAD)
import SpeechVAD
#endif

private let diarLog = Logger(subsystem: "com.onetoone.app", category: "PyannoteDiarizer")

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

    struct DiarizeOutput {
        let turns: [TurnAligner.DiarTurn]
        let perClusterEmbedding: [Int: [Float]]
    }

    private init() {}

    /// Lazy-load the pipeline on first call. Triggers HuggingFace download
    /// on first run (cached afterwards).
    func diarize(audioURL: URL) async throws -> DiarizeOutput {
        #if canImport(SpeechVAD)
        if pipeline == nil {
            diarLog.info("loading PyannoteDiarizationPipeline (first call)")
            pipeline = try await PyannoteDiarizationPipeline.fromPretrained(useVADFilter: true)
        }
        guard let pipeline else {
            throw NSError(domain: "PyannoteDiarizer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "pipeline unavailable"])
        }
        let samples = try Self.loadMono16k(url: audioURL)
        let result = pipeline.diarize(audio: samples, sampleRate: 16000, config: .default)

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
        diarLog.info("diarize done turns=\(turns.count) speakers=\(result.numSpeakers)")
        return DiarizeOutput(turns: turns, perClusterEmbedding: embeddings)
        #else
        throw NSError(domain: "PyannoteDiarizer", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "SpeechVAD non disponible — speech-swift pas linké."])
        #endif
    }

    /// Loads WAV/M4A and returns 16 kHz mono Float32 samples via AVAudioEngine
    /// (resamples + downmixes if needed).
    private static func loadMono16k(url: URL) throws -> [Float] {
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
