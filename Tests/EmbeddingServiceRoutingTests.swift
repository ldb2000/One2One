import Testing
import Foundation
@testable import OneToOne

// .serialized : les tests mutent les mêmes clés UserDefaults globales —
// l'exécution parallèle par défaut de Swift Testing les rendrait flaky.
@Suite("EmbeddingService — routage backend et préfixes nomic", .serialized)
struct EmbeddingServiceRoutingTests {

    /// Sauvegarde/restaure les clés UserDefaults touchées par un test.
    private func withDefaults(_ values: [String: String?], _ body: () throws -> Void) rethrows {
        let keys = [EmbeddingService.backendKey, EmbeddingService.modelKey]
        let saved = keys.map { ($0, UserDefaults.standard.string(forKey: $0)) }
        defer {
            for (k, v) in saved {
                if let v { UserDefaults.standard.set(v, forKey: k) }
                else { UserDefaults.standard.removeObject(forKey: k) }
            }
        }
        for (k, v) in values {
            if let v { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
        try body()
    }

    @Test("Backend par défaut = mlx, modèle par défaut dépend du backend")
    func defaultBackendAndModel() throws {
        try withDefaults([EmbeddingService.backendKey: nil, EmbeddingService.modelKey: nil]) {
            #expect(EmbeddingService.backend == .mlx)
            #expect(EmbeddingService.model == "nomic-ai/nomic-embed-text-v1.5")
        }
        try withDefaults([EmbeddingService.backendKey: "ollama", EmbeddingService.modelKey: nil]) {
            #expect(EmbeddingService.backend == .ollama)
            #expect(EmbeddingService.model == "nomic-embed-text")
        }
    }

    @Test("Un modèle explicite en UserDefaults prime sur le défaut")
    func explicitModelWins() throws {
        try withDefaults([EmbeddingService.backendKey: "mlx", EmbeddingService.modelKey: "BAAI/bge-m3"]) {
            #expect(EmbeddingService.model == "BAAI/bge-m3")
        }
    }

    @Test("Préfixes nomic appliqués seulement en mlx + modèle nomic")
    func nomicPrefixes() {
        let t = "Compte rendu du copil"
        #expect(EmbeddingService.prefixedText(t, role: .document, backend: .mlx,
                                              model: "nomic-ai/nomic-embed-text-v1.5")
                == "search_document: Compte rendu du copil")
        #expect(EmbeddingService.prefixedText(t, role: .query, backend: .mlx,
                                              model: "nomic-ai/nomic-embed-text-v1.5")
                == "search_query: Compte rendu du copil")
        // Ollama : jamais de préfixe (comportement historique conservé)
        #expect(EmbeddingService.prefixedText(t, role: .document, backend: .ollama,
                                              model: "nomic-embed-text") == t)
        // Modèle non-nomic en mlx : pas de préfixe
        #expect(EmbeddingService.prefixedText(t, role: .query, backend: .mlx,
                                              model: "BAAI/bge-m3") == t)
    }
}
