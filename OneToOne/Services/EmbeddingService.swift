import Foundation
import os

private let embedLog = Logger(subsystem: "com.onetoone.app", category: "embed")

// MARK: - EmbeddingService (Ollama nomic-embed-text)

/// Calcule des embeddings locaux via Ollama (par défaut `nomic-embed-text`).
/// Configuration :
///   - URL   : `UserDefaults.standard.string(forKey: "onetoone_ollama_url")` ou `http://localhost:11434`
///   - model : `UserDefaults.standard.string(forKey: "onetoone_embedding_model")` ou `nomic-embed-text`
struct EmbeddingService {

    static let defaultBaseURL = "http://localhost:11434"
    static let defaultModel = "nomic-embed-text"

    static let baseURLKey = "onetoone_ollama_url"
    static let modelKey = "onetoone_embedding_model"

    // MARK: - Backend (MLX in-process par défaut, Ollama legacy)

    enum Backend: String { case mlx, ollama }

    /// Rôle du texte pour les modèles asymétriques (nomic) :
    /// `.document` à l'indexation, `.query` pour la recherche.
    enum Role { case document, query }

    static let backendKey = "onetoone_embedding_backend"
    /// e5-base multilingue (xlm-roberta, positions absolues). nomic v1.5 est
    /// inchargeable via MLXEmbedders : bug upstream NomicBert qui exige des
    /// positions absolues alors que le checkpoint est 100 % rotary
    /// (« Key embeddings.position_embeddings… » au verify des poids).
    static let defaultMLXModel = "intfloat/multilingual-e5-base"

    static var backend: Backend {
        Backend(rawValue: UserDefaults.standard.string(forKey: backendKey) ?? "") ?? .mlx
    }

    /// Préfixes asymétriques par famille de modèle — seulement en backend MLX.
    /// nomic : search_document: / search_query: ; e5 : passage: / query:
    /// (requis par l'entraînement de ces familles). Le chemin Ollama reste
    /// sans préfixe (comportement historique, cohérent avec l'index existant).
    static func prefixedText(_ text: String, role: Role, backend: Backend, model: String) -> String {
        guard backend == .mlx else { return text }
        let family = model.lowercased()
        if family.contains("nomic") {
            switch role {
            case .document: return "search_document: " + text
            case .query:    return "search_query: " + text
            }
        }
        if family.contains("e5") {
            switch role {
            case .document: return "passage: " + text
            case .query:    return "query: " + text
            }
        }
        return text
    }

    /// Erreurs remontées par les appels d'embedding Ollama.
    enum EmbeddingError: LocalizedError {
        /// URL de base Ollama invalide / inconstruisible.
        case invalidURL
        /// Réponse HTTP hors 2xx : code de statut + corps brut (tronqué à l'affichage).
        case httpStatus(Int, String)
        /// Échec de décodage JSON de la réponse : message d'erreur sous-jacent.
        case decodeFailed(String)
        /// Ollama a renvoyé un vecteur d'embedding vide.
        case emptyVector

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL Ollama invalide."
            case .httpStatus(let code, let body):
                return "Ollama HTTP \(code): \(body.prefix(240))"
            case .decodeFailed(let d): return "Décodage réponse embeddings échoué: \(d)"
            case .emptyVector: return "Embedding vide renvoyé par Ollama."
            }
        }
    }

    static var baseURL: String {
        UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL
    }

    static var model: String {
        if let stored = UserDefaults.standard.string(forKey: modelKey), !stored.isEmpty {
            return stored
        }
        switch backend {
        case .mlx:    return defaultMLXModel
        case .ollama: return defaultModel
        }
    }

    /// Embed un texte via Ollama. Appel synchrone logique, async signature.
    /// Reçoit le texte déjà strippé (le guard `!stripped.isEmpty` est fait par
    /// l'appelant `embed`).
    private static func embedOllama(_ stripped: String) async throws -> [Float] {
        let raw = baseURL.trimmingCharacters(in: .whitespaces)
        let cleaned = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let url = URL(string: "\(cleaned)/api/embeddings") else {
            throw EmbeddingError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        struct Body: Encodable { let model: String; let prompt: String }
        req.httpBody = try JSONEncoder().encode(Body(model: model, prompt: stripped))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw EmbeddingError.httpStatus(0, "no response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            embedLog.error("embed HTTP \(http.statusCode, privacy: .public) — \(body, privacy: .public)")
            throw EmbeddingError.httpStatus(http.statusCode, body)
        }

        struct Resp: Decodable { let embedding: [Double] }
        let decoded: Resp
        do {
            decoded = try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw EmbeddingError.decodeFailed(error.localizedDescription)
        }
        guard !decoded.embedding.isEmpty else { throw EmbeddingError.emptyVector }
        return decoded.embedding.map { Float($0) }
    }

    /// Embed un texte selon le backend courant.
    static func embed(_ text: String, role: Role = .document) async throws -> [Float] {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return [] }
        switch backend {
        case .mlx:
            let prefixed = prefixedText(stripped, role: role, backend: .mlx, model: model)
            let vectors = try await MLXEmbeddingEngine.embedBatch([prefixed], modelRepo: model)
            return vectors.first ?? []
        case .ollama:
            return try await embedOllama(stripped)
        }
    }

    /// Batch embed. En backend MLX, les textes sont préfixés (rôle) et envoyés
    /// à `MLXEmbeddingEngine` en sous-lots de 16 (borne mémoire GPU), l'ordre
    /// de `texts` étant préservé. En backend Ollama, concurrence limitée
    /// (via `AsyncSemaphore`, min. 1) — comportement historique inchangé.
    /// L'ordre du tableau renvoyé suit celui de `texts` (réindexation par
    /// position), indépendamment de l'ordre d'achèvement des tâches.
    /// Aucune logique de retry : la première erreur d'`embed` propage et annule
    /// le groupe. Un texte vide ou en échec se traduit par un vecteur vide.
    static func embedBatch(_ texts: [String], role: Role = .document, concurrency: Int = 4) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        if backend == .mlx {
            let currentModel = model
            var results = [[Float]](repeating: [], count: texts.count)
            // Indices des textes non vides, préfixés, envoyés par sous-lots de 16.
            let nonEmpty: [(Int, String)] = texts.enumerated().compactMap { i, t in
                let stripped = t.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stripped.isEmpty else { return nil }
                return (i, prefixedText(stripped, role: role, backend: .mlx, model: currentModel))
            }
            var cursor = 0
            while cursor < nonEmpty.count {
                let slice = Array(nonEmpty[cursor..<min(cursor + 16, nonEmpty.count)])
                let vectors = try await MLXEmbeddingEngine.embedBatch(slice.map(\.1), modelRepo: currentModel)
                for (offset, (originalIndex, _)) in slice.enumerated() where offset < vectors.count {
                    results[originalIndex] = vectors[offset]
                }
                cursor += 16
            }
            return results
        }

        // Chemin Ollama historique (concurrence limitée).
        var results: [Int: [Float]] = [:]
        let sem = AsyncSemaphore(value: max(1, concurrency))
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (i, t) in texts.enumerated() {
                await sem.wait()
                group.addTask {
                    defer { Task { await sem.signal() } }
                    let v = try await embed(t, role: role)
                    return (i, v)
                }
            }
            for try await (i, v) in group {
                results[i] = v
            }
        }
        return texts.indices.map { results[$0] ?? [] }
    }

    /// Similarité cosinus. Retourne -1…1.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}

// MARK: - AsyncSemaphore (utilitaire local)

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.value = value }

    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let w = waiters.first {
            waiters.removeFirst()
            w.resume()
        } else {
            value += 1
        }
    }
}
