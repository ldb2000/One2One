import Foundation

/// Lightweight protocol around `AIClient.send` so manager services can be
/// unit-tested with a mock. The production conformance is `LiveAIClient`,
/// declared in `AIClient.swift` and exposed as `AIClient.live`.
protocol AIClientProtocol: Sendable {
    func send(prompt: String, settings: AppSettings) async throws -> String
}
