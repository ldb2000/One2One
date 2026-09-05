import Foundation
import SwiftData

/// Niveau de raisonnement demandé au modèle. « Défaut » n'ajoute rien à la requête.
enum AIReasoningLevel: String, Codable, CaseIterable, Sendable {
    case modelDefault = "default"
    case off, low, medium, high, xhigh

    var displayName: String {
        switch self {
        case .modelDefault: return "Défaut du modèle"
        case .off: return "Désactivé"
        case .low: return "Faible"
        case .medium: return "Moyen"
        case .high: return "Élevé"
        case .xhigh: return "Maximal"
        }
    }

    /// Valeur d'effort compatible OpenAI (Ollama `reasoning_effort`, OpenRouter
    /// `reasoning.effort`) ; nil pour laisser le modèle décider.
    var effort: String? {
        switch self {
        case .modelDefault: return nil
        case .off: return "none"
        default: return rawValue
        }
    }

    /// LM Studio 0.4.23 ignore les paramètres de raisonnement de l'API (vérifié
    /// sur le prompt rendu). Seule une consigne système reprenant le texte du
    /// template Qwen agit ; `high` est aligné sur `xhigh`, comme le fait Ollama.
    var lmStudioInstruction: String? {
        switch self {
        case .modelDefault, .off: return nil
        case .low: return "Reasoning effort is set to low. Keep your thinking brief and focused, moving directly to the conclusion without unnecessary elaboration."
        case .medium: return "Reasoning effort is set to medium. Think through the task with a balanced level of detail, then answer without unnecessary elaboration."
        case .high, .xhigh: return "Reasoning effort is set to xhigh. Please think carefully through the task, validate key assumptions, consider plausible alternatives, and prioritize correctness, consistency, and clarity in the final answer."
        }
    }

    /// La désactivation sur LM Studio préremplit un bloc de réflexion vide,
    /// propre au template Qwen : elle n'est proposée que pour cette famille.
    static func available(for profile: AIEndpointProfile) -> [AIReasoningLevel] {
        switch profile.provider {
        case .ollama, .openRouter: return allCases
        case .lmStudio: return profile.usesQwenTemplate ? allCases : allCases.filter { $0 != .off }
        default: return [.modelDefault]
        }
    }
}

/// Configuration persistable : les secrets restent exclusivement au Trousseau.
struct AIEndpointProfile: Codable, Equatable, Sendable {
    var provider: AIProvider
    var baseURL: String
    var model: String
    var credentialID: String? = nil
    var maxOutputTokens: Int = Self.defaultOutputTokens
    var reasoning: AIReasoningLevel = .modelDefault

    /// Réflexion et rapport partagent cette limite : trois fois l'ancienne valeur
    /// pour qu'un modèle qui raisonne ne tronque plus le rapport.
    static let defaultOutputTokens = 24576
    static let legacyDefaultOutputTokens = 8192

    /// Préremplissage `</think>` du template Qwen (LM Studio).
    static let qwenEmptyThinkingPrefill = "\n</think>\n\n"

    var usesQwenTemplate: Bool { model.lowercased().contains("qwen") }

    static func defaults(for provider: AIProvider) -> Self {
        let endpoint: String
        let model: String
        switch provider {
        case .lmStudio: (endpoint, model) = ("http://localhost:1234/v1", "")
        case .openRouter: (endpoint, model) = ("https://openrouter.ai/api/v1", "")
        case .direct: (endpoint, model) = ("", AIProvider.legacyDirectModelRepo)
        case .ollama: (endpoint, model) = ("http://localhost:11434/v1", "")
        case .openai: (endpoint, model) = ("https://api.openai.com/v1", "gpt-4o")
        case .anthropic: (endpoint, model) = ("https://api.anthropic.com/v1", "claude-sonnet-4-5")
        case .gemini: (endpoint, model) = ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.5-pro")
        case .geminiOAuth: (endpoint, model) = ("", "gemini-2.5-pro")
        }
        return Self(provider: provider, baseURL: endpoint, model: model)
    }

    var requiresAPIKey: Bool {
        ![.lmStudio, .ollama, .direct, .geminiOAuth].contains(provider)
    }

    /// Même LM Studio peut viser une machine distante : seule la boucle locale
    /// permet le classement automatique sans l'option d'envoi distant.
    var isOnDevice: Bool {
        if provider == .direct { return true }
        guard provider == .lmStudio || provider == .ollama,
              let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    func url(for path: String) throws -> URL {
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme, ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw AIEndpointError.invalidURL }
        if provider == .openRouter && (scheme != "https" || host.lowercased() != "openrouter.ai") {
            throw AIEndpointError.invalidURL
        }
        var prefix = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if prefix.isEmpty { prefix = provider == .openRouter ? "api/v1" : "v1" }
        parts.path = "/" + prefix + "/" + path
        guard let url = parts.url else { throw AIEndpointError.invalidURL }
        return url
    }
}

extension AIEndpointProfile {
    private enum CodingKeys: String, CodingKey { case provider, baseURL, model, credentialID, maxOutputTokens, reasoning }

    /// Lecture tolérante des profils enregistrés avant le réglage de raisonnement :
    /// clé absente → défaut, et l'ancienne limite par défaut est relevée une seule
    /// fois. Un niveau inconnu retombe sur le défaut sans invalider le profil.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decode(AIProvider.self, forKey: .provider)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        credentialID = try values.decodeIfPresent(String.self, forKey: .credentialID)
        let limit = try values.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? Self.defaultOutputTokens
        if let raw = try values.decodeIfPresent(String.self, forKey: .reasoning) {
            reasoning = AIReasoningLevel(rawValue: raw) ?? .modelDefault
            maxOutputTokens = limit
        } else {
            reasoning = .modelDefault
            maxOutputTokens = limit == Self.legacyDefaultOutputTokens ? Self.defaultOutputTokens : limit
        }
    }

    /// Un JSON sans clé `reasoning` date d'avant le réglage : il est réécrit une fois.
    static func needsRewrite(_ json: String) -> Bool { !json.isEmpty && !json.contains("\"reasoning\"") }
}

/// Valeur figée avant tout await réseau ; aucun objet SwiftData dans le transport.
struct AIRequestConfiguration: Sendable {
    var profile: AIEndpointProfile
    var apiKey: String

    func validate(requireModel: Bool = true, requireAPIKey: Bool = true) throws {
        _ = try profile.url(for: "models")
        if requireAPIKey && profile.requiresAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIEndpointError.missingKey
        }
        if requireModel && profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIEndpointError.missingModel
        }
        guard (1...131072).contains(profile.maxOutputTokens) else { throw AIEndpointError.invalidTokenLimit }
    }
}

@MainActor
enum AIConfigurationStore {
    static func profiles(for settings: AppSettings) throws -> [AIEndpointProfile] {
        if !settings.aiProfilesJSON.isEmpty {
            guard let data = settings.aiProfilesJSON.data(using: .utf8),
                  let profiles = try? JSONDecoder().decode([AIEndpointProfile].self, from: data),
                  Set(profiles.map(\.provider)).count == profiles.count else {
                throw AIEndpointError.invalidConfiguration
            }
            return profiles
        }
        guard let provider = AIProvider(rawValue: settings.providerRaw) else {
            throw AIEndpointError.invalidConfiguration
        }
        var current = AIEndpointProfile.defaults(for: provider)
        current.baseURL = settings.apiEndpoint
        current.model = provider == .direct ? settings.directModelRepo : settings.modelName
        return [current]
    }

    static func profile(for settings: AppSettings) throws -> AIEndpointProfile {
        guard let provider = AIProvider(rawValue: settings.providerRaw) else {
            throw AIEndpointError.invalidConfiguration
        }
        guard let profile = try profiles(for: settings).first(where: { $0.provider == provider }) else {
            throw AIEndpointError.invalidConfiguration
        }
        return profile
    }

    static func encode(_ profiles: [AIEndpointProfile]) throws -> String {
        String(decoding: try JSONEncoder().encode(profiles), as: UTF8.self)
    }

    /// Migration additive, idempotente. Ne vide jamais l'ancien champ si le
    /// Trousseau ou la sauvegarde échoue. Pas de mutation pour un brouillon détaché.
    static func migrate(_ settings: AppSettings, credentials: any AICredentialStore = KeychainAICredentialStore()) throws {
        guard settings.modelContext != nil else { return }
        var profiles = try profiles(for: settings)
        let retiringDirect = settings.providerRaw == AIProvider.direct.rawValue
        guard !settings.cloudToken.isEmpty || settings.aiProfilesJSON.isEmpty || retiringDirect
                || AIEndpointProfile.needsRewrite(settings.aiProfilesJSON) else { return }
        let previousJSON = settings.aiProfilesJSON
        let previousToken = settings.cloudToken
        let previousSelection = (settings.providerRaw, settings.apiEndpoint, settings.modelName)
        if !previousToken.isEmpty {
            guard let index = profiles.firstIndex(where: { $0.provider.rawValue == settings.providerRaw }) else {
                throw AIEndpointError.invalidConfiguration
            }
            let id = UUID().uuidString
            try credentials.write(previousToken, id: id)
            guard try credentials.read(id: id) == previousToken else { throw AIEndpointError.credentialStorage }
            profiles[index].credentialID = id
        }
        if retiringDirect {
            // Ne pas inventer de correspondance entre le repo HF et un modèle
            // servi par LM Studio. Conserver son profil s'il était déjà configuré.
            let local = profiles.first { $0.provider == .lmStudio } ?? .defaults(for: .lmStudio)
            profiles.removeAll { $0.provider == .direct || $0.provider == .lmStudio }
            profiles.append(local)
            settings.provider = .lmStudio
            settings.apiEndpoint = local.baseURL
            settings.modelName = local.model
        }
        settings.aiProfilesJSON = try encode(profiles)
        settings.cloudToken = ""
        do { try settings.modelContext?.save() }
        catch {
            settings.aiProfilesJSON = previousJSON
            settings.cloudToken = previousToken
            (settings.providerRaw, settings.apiEndpoint, settings.modelName) = previousSelection
            throw error
        }
    }

    static func resolve(_ settings: AppSettings, credentials: any AICredentialStore = KeychainAICredentialStore()) throws -> AIRequestConfiguration {
        try migrate(settings, credentials: credentials)
        let profile = try profile(for: settings)
        let key: String
        if let id = profile.credentialID { key = try credentials.read(id: id) ?? "" }
        else { key = settings.cloudToken }
        return AIRequestConfiguration(profile: profile, apiKey: key)
    }

    /// Écrit une nouvelle référence plutôt que modifier un secret actif avant
    /// le commit SwiftData. Les clés d'un profil ne sont jamais réutilisées ailleurs.
    static func save(_ profile: AIEndpointProfile, apiKey: String, settings: AppSettings,
                     credentials: any AICredentialStore = KeychainAICredentialStore()) throws {
        guard profile.provider != .direct else { throw AIEndpointError.retiredProvider }
        try migrate(settings, credentials: credentials)
        var profiles = try profiles(for: settings)
        var saved = profile
        saved.credentialID = nil
        if !apiKey.isEmpty {
            if let previous = profiles.first(where: { $0.provider == profile.provider && $0.baseURL == profile.baseURL }),
               let id = previous.credentialID, try credentials.read(id: id) == apiKey {
                saved.credentialID = id
            } else {
                let id = UUID().uuidString
                try credentials.write(apiKey, id: id)
                guard try credentials.read(id: id) == apiKey else { throw AIEndpointError.credentialStorage }
                saved.credentialID = id
            }
        }
        profiles.removeAll { $0.provider == profile.provider }
        profiles.append(saved)
        let old = (settings.aiProfilesJSON, settings.providerRaw, settings.apiEndpoint, settings.modelName, settings.directModelRepo)
        settings.aiProfilesJSON = try encode(profiles)
        settings.provider = profile.provider
        settings.apiEndpoint = profile.baseURL
        settings.modelName = profile.model
        if profile.provider == .direct { settings.directModelRepo = profile.model }
        do { try settings.modelContext?.save() }
        catch {
            (settings.aiProfilesJSON, settings.providerRaw, settings.apiEndpoint, settings.modelName, settings.directModelRepo) = old
            throw error
        }
    }
}

enum AIEndpointError: LocalizedError, Equatable {
    case invalidURL, missingKey, missingModel, invalidTokenLimit, invalidConfiguration, credentialStorage
    case http(Int), serverError, invalidResponse, emptyResponse, incompleteResponse, truncatedResponse, refused
    case unavailable(String), timedOut, retiredProvider
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Adresse d’endpoint invalide. OpenRouter nécessite https://openrouter.ai/api/v1."
        case .missingKey: return "Renseignez la clé API de cet endpoint."
        case .missingModel: return "Choisissez un modèle dans les réglages IA."
        case .invalidTokenLimit: return "La limite de sortie doit être comprise entre 1 et 131 072 tokens."
        case .invalidConfiguration: return "Configuration IA illisible ou fournisseur inconnu. Vérifiez les réglages sans écraser les données existantes."
        case .credentialStorage: return "Impossible de lire ou d’enregistrer la clé dans le Trousseau."
        case .http(401), .http(403): return "Clé API refusée ou accès au modèle non autorisé."
        case .http(402): return "Crédit insuffisant sur l’endpoint IA."
        case .http(404): return "Endpoint ou modèle introuvable. Actualisez la liste des modèles."
        case .http(429): return "Limite de débit atteinte. Réessayez plus tard."
        case .http(400), .http(413): return "Requête refusée : vérifiez le modèle, la taille du contexte et la limite de sortie."
        case .http(let status): return "L’endpoint IA a répondu HTTP \(status)."
        case .serverError: return "Le fournisseur a interrompu la génération avec une erreur."
        case .invalidResponse: return "Réponse de l’endpoint IA illisible."
        case .emptyResponse: return "Le modèle n’a retourné aucun texte exploitable."
        case .incompleteResponse: return "Connexion interrompue avant la fin de la réponse. Le texte partiel n’est pas validé."
        case .truncatedResponse: return "Réponse tronquée par la limite de sortie. Augmentez cette limite ou réduisez le contexte."
        case .refused: return "Le modèle a refusé la demande ou demandé un outil non disponible."
        case .unavailable(let provider): return "\(provider) est injoignable. Vérifiez l’adresse, le réseau et le démarrage du serveur."
        case .timedOut: return "L’endpoint IA n’a pas répondu à temps. Vérifiez le chargement du modèle ou réduisez la demande."
        case .retiredProvider: return "Le moteur Direct a été retiré. Choisissez LM Studio, Ollama ou OpenRouter dans les réglages IA."
        }
    }
}
