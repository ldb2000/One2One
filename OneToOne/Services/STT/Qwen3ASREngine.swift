import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Moteur STT Qwen3-ASR (MLX local, 0.6B — léger). Contrairement à Cohere et
/// Voxtral (qui auto-détectent et ne peuvent pas être contraints), Qwen3-ASR
/// **force la langue de décodage** : `STTGenerateParameters.language` est
/// normalisé (« fr » → « French ») puis injecté dans le prompt. C'est le moteur
/// à utiliser pour éviter les bascules de langue intempestives (ex.
/// hallucinations en japonais sur du français).
@MainActor
final class Qwen3ASREngine: STTEngine {
    /// Dépôt HuggingFace résolu localement (cache HF / managed / chemin manuel),
    /// jamais téléchargé à la volée. Cf. [[stt-diarization-ops]].
    static let repoIds = ["aufklarer/Qwen3-ASR-0.6B-MLX-4bit"]
    static let manualPathKey = "onetoone_qwen3asr_manual_model_path"

    #if canImport(MLXAudioSTT)
    private var model: Qwen3ASRModel?
    #endif

    var isLoaded: Bool {
        #if canImport(MLXAudioSTT)
        return model != nil
        #else
        return false
        #endif
    }

    /// Charge le modèle depuis le premier dossier candidat valide (idempotent :
    /// no-op si déjà chargé). Chargement disque hors du main thread. Lève
    /// `STTError` si le modèle est introuvable ou KO.
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
            struct Box: @unchecked Sendable { let model: Qwen3ASRModel }
            let box = try await Task.detached(priority: .userInitiated) {
                Box(model: try await Qwen3ASRModel.fromModelDirectory(dir))
            }.value
            model = box.model
        } catch {
            throw STTError.loadFailed(error.localizedDescription)
        }
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    /// Transcrit un clip 16 kHz mono déjà découpé, en **forçant** `language`.
    /// Génération déterministe (temperature 0) hors du main thread ; renvoie le
    /// texte trimmé, ou "" si le modèle n'est pas chargé.
    #if canImport(MLX)
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) async -> String {
        #if canImport(MLXAudioSTT)
        guard let model else { return "" }
        let params = STTGenerateParameters(
            maxTokens: maxTokens, temperature: 0.0, topP: 1.0, topK: 0,
            verbose: false, language: language,
            chunkDuration: 1200.0, minChunkDuration: 1.0)
        struct Box: @unchecked Sendable {
            let model: Qwen3ASRModel; let clip: MLXArray; let params: STTGenerateParameters
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
