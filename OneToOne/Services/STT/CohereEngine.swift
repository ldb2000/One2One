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
    /// Variantes acceptées, par ordre de préférence. La résolution retient la
    /// première réellement présente en cache : 8bit (léger) si dispo, sinon la
    /// fp16 (précise, plus lourde). Évite l'échec « Modèle STT introuvable »
    /// quand seule l'une des variantes a été téléchargée.
    static let repoIds = [
        "beshkenadze/cohere-transcribe-03-2026-mlx-8bit",
        "beshkenadze/cohere-transcribe-03-2026-mlx-fp16",
    ]
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

    /// Charge le modèle depuis le premier dossier candidat valide (idempotent :
    /// no-op si déjà chargé). Le chargement disque s'exécute hors du main thread
    /// via `Task.detached`. Lève `STTError` si le modèle est introuvable ou KO.
    func load() async throws {
        #if canImport(MLXAudioSTT)
        guard model == nil else { return }
        guard let dir = STTModelResolver.resolveExistingDirectory(
            repoIds: Self.repoIds, manualKey: Self.manualPathKey,
            contains: { STTModelResolver.containsSafetensors($0) }) else {
            throw STTError.modelMissing(searched: STTModelResolver.candidateDirectories(
                repoIds: Self.repoIds, manualKey: Self.manualPathKey))
        }
        do {
            struct Box: @unchecked Sendable { let model: CohereTranscribeModel }
            let box = try await Task.detached(priority: .userInitiated) {
                Box(model: try CohereTranscribeModel.fromDirectory(dir))
            }.value
            model = box.model
        } catch {
            throw STTError.loadFailed(error.localizedDescription)
        }
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    /// Transcrit un clip 16 kHz mono déjà découpé. Génération déterministe
    /// (temperature 0) lancée hors du main thread ; renvoie le texte trimmé,
    /// ou "" si le modèle n'est pas chargé.
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
