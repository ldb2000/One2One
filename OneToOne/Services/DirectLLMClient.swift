import Foundation

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

/// Provider **« Directe »** : exécute un LLM (par défaut Gemma MLX) directement
/// en Swift, **in-process**, sans serveur externe (contrairement à Ollama).
///
/// Le modèle est chargé paresseusement depuis le cache HuggingFace
/// (`~/.cache/huggingface`) — téléchargé au premier usage s'il est absent —
/// puis mis en cache pour les appels suivants. La génération est streamée.
///
/// Le calcul lourd (chargement des poids + inférence) s'exécute dans l'acteur
/// `ModelContainer` de MLX, hors du main actor : `await`-er ces appels depuis le
/// main actor ne gèle donc pas l'UI. Le cache statique est isolé `@MainActor`.
@MainActor
enum DirectLLMClient {
    /// Repo HuggingFace MLX utilisé si `AppSettings.directModelRepo` est vide.
    static let defaultModelRepo = "mlx-community/gemma-4-31b-8bit"

    #if canImport(MLXLLM)
    /// Conteneur chargé et repo associé. Cache mono-modèle : si l'utilisateur
    /// change de modèle dans les réglages, on recharge.
    private static var container: ModelContainer?
    private static var loadedRepo: String?

    /// Renvoie le `ModelContainer` pour `repo`, en le chargeant (et téléchargeant
    /// si nécessaire) au premier appel. Reporte la progression de téléchargement
    /// via `onProgress` (utile : un modèle 8-bit ~26-31 Go met du temps).
    private static func ensureContainer(
        repo: String,
        onProgress: AIClient.ProgressCallback?
    ) async throws -> ModelContainer {
        if let container, loadedRepo == repo { return container }
        if let onProgress { await onProgress("Chargement du modèle \(repo)…") }

        let progressForward: @Sendable (Progress) -> Void = { progress in
            guard let onProgress else { return }
            let pct = Int(progress.fractionCompleted * 100)
            Task { @MainActor in await onProgress("Téléchargement du modèle \(repo) : \(pct) %") }
        }

        let loaded = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            id: repo,
            progressHandler: progressForward
        )
        container = loaded
        loadedRepo = repo
        return loaded
    }

    /// Envoie `prompt` au modèle `modelRepo` (ou le défaut si vide) et renvoie
    /// la réponse. `onProgress` reçoit le texte accumulé au fil de la génération.
    static func send(
        prompt: String,
        modelRepo: String,
        onProgress: AIClient.ProgressCallback?
    ) async throws -> String {
        let repo = modelRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultModelRepo
            : modelRepo
        let container = try await ensureContainer(repo: repo, onProgress: onProgress)

        var parameters = GenerateParameters()
        parameters.temperature = 0.1
        parameters.maxTokens = 8192

        let session = ChatSession(container, generateParameters: parameters)
        var accumulated = ""
        for try await chunk in session.streamResponse(to: prompt) {
            accumulated += chunk
            if let onProgress { await onProgress(accumulated) }
        }
        return accumulated
    }
    #else
    static func send(
        prompt: String,
        modelRepo: String,
        onProgress: AIClient.ProgressCallback?
    ) async throws -> String {
        throw IngestionError.networkError("LLM MLX indisponible dans ce build (MLXLLM non lié).")
    }
    #endif
}
