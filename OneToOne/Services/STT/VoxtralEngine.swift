import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Variante de poids Voxtral. Le repo HF résolu en dépend.
enum VoxtralVariant: String, Codable, CaseIterable, Sendable {
    case realtime4bit
    case realtimeFP16

    var repoId: String {
        switch self {
        case .realtime4bit: return "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
        case .realtimeFP16: return "mlx-community/Voxtral-Mini-4B-Realtime-2602"
        }
    }

    var label: String {
        switch self {
        case .realtime4bit: return "Realtime 4-bit (léger)"
        case .realtimeFP16: return "Realtime fp16 (précis)"
        }
    }
}

/// Moteur STT Voxtral (MLX local). Variante sélectionnée à l'init.
@MainActor
final class VoxtralEngine: STTEngine {
    static let manualPathKey = "onetoone_voxtral_manual_model_path"

    let variant: VoxtralVariant

    #if canImport(MLXAudioSTT)
    private var model: VoxtralRealtimeModel?
    #endif

    init(variant: VoxtralVariant) { self.variant = variant }

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
        let repoId = variant.repoId
        guard let dir = STTModelResolver.resolveExistingDirectory(
            repoId: repoId, manualKey: Self.manualPathKey,
            contains: { STTModelResolver.containsSafetensors($0) }) else {
            throw STTError.modelMissing(searched: STTModelResolver.candidateDirectories(
                repoId: repoId, manualKey: Self.manualPathKey))
        }
        do {
            model = try VoxtralRealtimeModel.fromDirectory(dir)
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
            let model: VoxtralRealtimeModel; let clip: MLXArray; let params: STTGenerateParameters
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
