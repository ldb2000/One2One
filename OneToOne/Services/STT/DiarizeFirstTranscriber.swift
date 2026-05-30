import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Orchestration diarize-first : Pyannote → fusion des tours → STT (Voxtral)
/// par tour → blocs attribués. Délègue le STT à un `STTEngine` et la
/// diarisation à `PyannoteDiarizer`.
@MainActor
enum DiarizeFirstTranscriber {
    static let maxGap: Double = 0.5
    static let minTurnDuration: Double = 0.6
    static let maxTokensPerTurn: Int = 1024
    static let sampleRate: Int = 16_000

    static func run(audioURL: URL,
                    engine: STTEngine,
                    language: String,
                    clusterThreshold: Float,
                    onPhase: ((TranscriptionPhase) -> Void)?,
                    onProgress: ((Double, String) -> Void)?) async throws
        -> (blocks: [TurnMerger.Block], embeddings: [Int: [Float]]) {
        #if canImport(MLXAudioSTT)
        let diar = try await PyannoteDiarizer.shared.diarize(
            audioURL: audioURL, clusterThreshold: clusterThreshold,
            onPhase: onPhase, onProgress: onProgress)

        let merged = TurnMerger.mergeAdjacent(diar.turns, maxGap: maxGap)

        onPhase?(.transcribing)
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: sampleRate)
        let total = audio.shape.last ?? 0
        var blocks: [TurnMerger.Block] = []
        let n = max(1, merged.count)
        for (i, t) in merged.enumerated() {
            try Task.checkCancellation()
            onProgress?(Double(i) / Double(n), "Tour \(i + 1) / \(merged.count)")
            guard (t.endSec - t.startSec) >= minTurnDuration else { continue }
            let a = max(0, Int((t.startSec * Double(sampleRate)).rounded(.down)))
            let b = min(total, Int((t.endSec * Double(sampleRate)).rounded(.down)))
            guard b > a else { continue }
            let clip = audio[a..<b]
            let text = await engine.transcribe(clip: clip, language: language, maxTokens: maxTokensPerTurn)
            guard !text.isEmpty else { continue }
            blocks.append(TurnMerger.Block(speaker: t.clusterID, start: t.startSec, end: t.endSec, text: text))
        }
        onProgress?(1.0, "Terminé")
        return (blocks, diar.perClusterEmbedding)
        #else
        throw STTError.mlxNotLinked
        #endif
    }
}
