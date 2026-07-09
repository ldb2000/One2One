import Foundation
import os

#if canImport(MLXEmbedders)
import MLX
import MLXEmbedders
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

private let embedEngineLog = Logger(subsystem: "com.onetoone.app", category: "embed-mlx")

/// Moteur d'embedding MLX in-process (nomic-embed-text-v1.5 par défaut).
/// Cache statique mono-modèle, même pattern que `DirectLLMClient` : le
/// container est rechargé si le repo change. Les textes reçus sont supposés
/// déjà préfixés (`search_document:` / `search_query:`) par l'appelant.
@MainActor
enum MLXEmbeddingEngine {

    enum EngineError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "Embeddings MLX indisponibles dans ce build (MLXEmbedders non lié)."
        }
    }

#if canImport(MLXEmbedders)
    private static var container: EmbedderModelContainer?
    private static var loadedRepo: String?

    private static func ensureContainer(repo: String) async throws -> EmbedderModelContainer {
        if let container, loadedRepo == repo { return container }
        embedEngineLog.info("chargement embedder \(repo, privacy: .public)")
        let loaded = try await EmbedderModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: repo)
        )
        container = loaded
        loadedRepo = repo
        return loaded
    }

    /// Embedde un lot de textes. Retourne un vecteur (768 dim pour e5-base)
    /// par texte, dans l'ordre d'entrée.
    static func embedBatch(_ texts: [String], modelRepo: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let container = try await ensureContainer(repo: modelRepo)
        let applyLayerNorm = modelRepo.lowercased().contains("nomic")
        return try await container.perform { context in
            let tokenizer = context.tokenizer
            let encoded = texts.map { tokenizer.encode(text: $0, addSpecialTokens: true) }
            let padId = tokenizer.eosTokenId ?? 0
            let maxLength = encoded.reduce(into: 16) { $0 = max($0, $1.count) }
            let padded = stacked(encoded.map { ids in
                MLXArray(ids + Array(repeating: padId, count: maxLength - ids.count))
            })
            let mask = (padded .!= padId)
            let tokenTypes = MLXArray.zeros(like: padded)
            let output = context.model(
                padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask)
            // Pooling (stratégie chargée depuis 1_Pooling/config.json du repo) + L2 ;
            // mask passé pour exclure le padding de la moyenne. applyLayerNorm fait
            // partie de la recette Matryoshka de nomic uniquement — il fausserait
            // les vecteurs des autres familles (e5, bge…).
            let result = context.pooling(
                output, mask: mask.asType(.float32),
                normalize: true, applyLayerNorm: applyLayerNorm)
            result.eval()
            return result.map { $0.asArray(Float.self) }
        }
    }
#else
    static func embedBatch(_ texts: [String], modelRepo: String) async throws -> [[Float]] {
        throw EngineError.unavailable
    }
#endif
}
