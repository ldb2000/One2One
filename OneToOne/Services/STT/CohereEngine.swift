import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Moteur STT Cohere Transcribe (MLX local). Reprend la résolution de dossier
/// historique (cache HF + managed + chemin manuel UserDefaults).
@MainActor
final class CohereEngine: STTEngine {
    static let repoId = "beshkenadze/cohere-transcribe-03-2026-mlx-8bit"
    static let manualPathKey = "onetoone_cohere_manual_model_path"

    #if canImport(MLXAudioSTT)
    private var model: CohereTranscribeModel?
    #endif

    var isLoaded: Bool {
        #if canImport(MLXAudioSTT)
        return model != nil
        #else
        return false
        #endif
    }

    func load() async throws {
        #if canImport(MLXAudioSTT)
        guard model == nil else { return }
        guard let dir = STTModelResolver.resolveExistingDirectory(
            repoId: Self.repoId, manualKey: Self.manualPathKey,
            contains: { STTModelResolver.containsSafetensors($0) }) else {
            throw STTError.modelMissing(searched: STTModelResolver.candidateDirectories(
                repoId: Self.repoId, manualKey: Self.manualPathKey))
        }
        do {
            model = try CohereTranscribeModel.fromDirectory(dir)
        } catch {
            throw STTError.loadFailed(error.localizedDescription)
        }
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    #if canImport(MLX)
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) async -> String {
        #if canImport(MLXAudioSTT)
        guard let model else { return "" }
        let params = STTGenerateParameters(
            maxTokens: maxTokens, temperature: 0.0, topP: 1.0, topK: 0,
            verbose: false, language: language,
            chunkDuration: 1200.0, minChunkDuration: 1.0)
        struct Box: @unchecked Sendable {
            let model: CohereTranscribeModel; let clip: MLXArray; let params: STTGenerateParameters
        }
        let box = Box(model: model, clip: clip, params: params)
        return await Task.detached(priority: .userInitiated) {
            box.model.generate(audio: box.clip, generationParameters: box.params)
                .text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        #else
        return ""
        #endif
    }
    #endif
}
