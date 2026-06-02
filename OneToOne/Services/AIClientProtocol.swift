import Foundation

/// Lightweight protocol around `AIClient.send` so manager services can be
/// unit-tested with a mock. The production conformance is `LiveAIClient`,
/// declared in `AIClient.swift` and exposed as `AIClient.live`.
protocol AIClientProtocol: Sendable {
    /// Envoie `prompt` au modèle configuré dans `settings` et renvoie la
    /// réponse texte brute. `throws` en cas d'erreur réseau/API.
    func send(prompt: String, settings: AppSettings) async throws -> String
}
