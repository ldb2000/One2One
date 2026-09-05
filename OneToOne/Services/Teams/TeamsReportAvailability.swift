import Foundation

/// Le rapport n'est proposé que si un provider IA peut effectivement répondre
/// (spec D-9). Sans cette garde, le popup promet un rapport que la génération
/// ne pourra pas produire.
enum TeamsReportAvailability {
    @MainActor
    static func isAvailable(settings: AppSettings) -> Bool {
        guard let configuration = try? AIConfigurationStore.resolve(settings) else { return false }
        if configuration.profile.provider.usesCompatibleEndpoint {
            return (try? configuration.validate()) != nil
        }
        return isAvailable(provider: configuration.profile.provider, cloudToken: configuration.apiKey)
    }

    /// Vrai si `provider` peut générer un rapport en l'état de la configuration.
    ///
    /// Les providers locaux (`.direct` en MLX in-process, `.ollama` en HTTP
    /// local, `.geminiOAuth` qui s'authentifie via la CLI) n'ont pas besoin de
    /// jeton. Les providers distants en exigent un.
    static func isAvailable(provider: AIProvider, cloudToken: String) -> Bool {
        switch provider {
        case .direct:
            return false
        case .ollama, .geminiOAuth, .lmStudio:
            return true
        case .anthropic, .openai, .gemini, .openRouter:
            return !cloudToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
