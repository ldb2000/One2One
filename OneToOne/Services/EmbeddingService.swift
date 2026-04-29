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

    enum EmbeddingError: LocalizedError {
        case invalidURL
        case httpStatus(Int, String)
        case decodeFailed(String)
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
        UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
    }

    /// Embed un texte. Appel synchrone logique, async signature.
    static func embed(_ text: String) async throws -> [Float] {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return [] }

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

    /// Batch embed avec concurrence limitée pour ne pas saturer Ollama.
    static func embedBatch(_ texts: [String], concurrency: Int = 4) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        var results: [Int: [Float]] = [:]
        let sem = AsyncSemaphore(value: max(1, concurrency))

        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (i, t) in texts.enumerated() {
                await sem.wait()
                group.addTask {
                    defer { Task { await sem.signal() } }
                    let v = try await embed(t)
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
