import Foundation
import SwiftData
import Testing
@testable import OneToOne

private actor AIActivityRecorder {
    var values: [AIClient.Activity] = []
    func append(_ activity: AIClient.Activity) { values.append(activity) }
}

private final class MemoryAICredentials: AICredentialStore {
    var values: [String: String] = [:]
    var failWrites = false
    var failReads = false
    func read(id: String) throws -> String? {
        if failReads { throw AIEndpointError.credentialStorage }
        return values[id]
    }
    func write(_ secret: String, id: String) throws {
        if failWrites { throw AIEndpointError.credentialStorage }
        values[id] = secret
    }
}

@MainActor
@Suite("Configuration des endpoints IA")
struct AIConfigurationTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
    }

    @Test("Une installation neuve propose LM Studio sans inventer de modèle")
    func freshInstall() throws {
        let settings = AppSettings()
        let config = try AIConfigurationStore.resolve(settings, credentials: MemoryAICredentials())
        #expect(config.profile.provider == .lmStudio)
        #expect(config.profile.baseURL == "http://localhost:1234/v1")
        #expect(config.profile.maxOutputTokens == 24576)
        #expect(config.profile.reasoning == .modelDefault)
        #expect(throws: AIEndpointError.missingModel) { try config.validate() }
    }

    @Test("Les profils enregistrés sans niveau de raisonnement gardent leurs valeurs, sauf l'ancienne limite par défaut")
    func legacyProfileDecoding() throws {
        let legacy = #"[{"provider":"lmStudio","baseURL":"http://localhost:1234/v1","model":"qwen3.8-27b","maxOutputTokens":8192}]"#
        let bumped = try JSONDecoder().decode([AIEndpointProfile].self, from: Data(legacy.utf8))
        #expect(bumped.first?.reasoning == .modelDefault)
        #expect(bumped.first?.maxOutputTokens == 24576)
        #expect(bumped.first?.model == "qwen3.8-27b")
        let custom = #"[{"provider":"Ollama","baseURL":"http://localhost:11434/v1","model":"m","maxOutputTokens":4096}]"#
        #expect(try JSONDecoder().decode([AIEndpointProfile].self, from: Data(custom.utf8)).first?.maxOutputTokens == 4096)
        // Une limite de 8 192 choisie après l'arrivée du réglage n'est plus touchée.
        let explicit = #"[{"provider":"Ollama","baseURL":"http://localhost:11434/v1","model":"m","maxOutputTokens":8192,"reasoning":"xhigh"}]"#
        let kept = try JSONDecoder().decode([AIEndpointProfile].self, from: Data(explicit.utf8))
        #expect(kept.first?.maxOutputTokens == 8192)
        #expect(kept.first?.reasoning == .xhigh)
        let minimal = #"[{"provider":"openRouter","baseURL":"https://openrouter.ai/api/v1","model":"vendor/m"}]"#
        let defaults = try JSONDecoder().decode([AIEndpointProfile].self, from: Data(minimal.utf8))
        #expect(defaults.first?.maxOutputTokens == 24576)
        #expect(defaults.first?.credentialID == nil)
        var profile = AIEndpointProfile.defaults(for: .ollama)
        profile.reasoning = .off
        let roundTrip = try JSONDecoder().decode([AIEndpointProfile].self, from: try JSONEncoder().encode([profile]))
        #expect(roundTrip == [profile])
    }

    @Test("La migration relève l'ancienne limite par défaut une seule fois et conserve les autres valeurs")
    func migrationBumpsLegacyLimit() throws {
        let context = try context()
        let settings = AppSettings(provider: .ollama)
        settings.aiProfilesJSON = #"[{"provider":"Ollama","baseURL":"http://localhost:11434/v1","model":"m","maxOutputTokens":8192},{"provider":"openRouter","baseURL":"https://openrouter.ai/api/v1","model":"v/m","maxOutputTokens":4096}]"#
        context.insert(settings)
        try context.save()
        let keys = MemoryAICredentials()
        try AIConfigurationStore.migrate(settings, credentials: keys)
        let profiles = try AIConfigurationStore.profiles(for: settings)
        #expect(profiles.first { $0.provider == .ollama }?.maxOutputTokens == 24576)
        #expect(profiles.first { $0.provider == .openRouter }?.maxOutputTokens == 4096)
        #expect(settings.aiProfilesJSON.contains("\"reasoning\""))
        let migrated = settings.aiProfilesJSON
        try AIConfigurationStore.migrate(settings, credentials: keys)
        #expect(settings.aiProfilesJSON == migrated)
        var manual = try AIConfigurationStore.profile(for: settings)
        manual.maxOutputTokens = 8192
        manual.reasoning = .low
        try AIConfigurationStore.save(manual, apiKey: "", settings: settings, credentials: keys)
        try AIConfigurationStore.migrate(settings, credentials: keys)
        let resolved = try AIConfigurationStore.resolve(settings, credentials: keys)
        #expect(resolved.profile.maxOutputTokens == 8192)
        #expect(resolved.profile.reasoning == .low)
    }

    @Test("Les anciens fournisseurs migrent sans changer leur modèle", arguments: [AIProvider.ollama, .anthropic, .openai, .gemini, .geminiOAuth])
    func legacyMigration(provider: AIProvider) throws {
        let context = try context()
        let settings = AppSettings(cloudToken: "old-secret", apiEndpoint: "https://example.test/custom/v1",
                                   modelName: "custom-model", provider: provider)
        settings.directModelRepo = "custom/hf-repo"
        context.insert(settings)
        try context.save()
        let credentials = MemoryAICredentials()
        try AIConfigurationStore.migrate(settings, credentials: credentials)
        let firstJSON = settings.aiProfilesJSON
        try AIConfigurationStore.migrate(settings, credentials: credentials)
        #expect(settings.aiProfilesJSON == firstJSON)
        #expect(credentials.values.count == 1)
        #expect(settings.cloudToken.isEmpty)
        let config = try AIConfigurationStore.resolve(settings, credentials: credentials)
        #expect(config.profile.provider == provider)
        #expect(config.profile.model == "custom-model")
        #expect(config.profile.baseURL == "https://example.test/custom/v1")
        #expect(config.apiKey == "old-secret")
    }

    @Test("Direct est retiré et migre vers LM Studio sans inventer un modèle")
    func retiringDirect() throws {
        let context = try context()
        let settings = AppSettings(provider: .direct)
        settings.directModelRepo = "old/downloaded-model"
        context.insert(settings)
        let keys = MemoryAICredentials()
        try AIConfigurationStore.migrate(settings, credentials: keys)
        #expect(settings.provider == .lmStudio)
        #expect(try AIConfigurationStore.profile(for: settings).model.isEmpty)
        #expect(settings.directModelRepo == "old/downloaded-model")
        #expect(!AIProvider.selectableProviders.contains(.direct))
        #expect(AIProvider.endpointProviders.contains(.ollama))
        #expect(throws: AIEndpointError.retiredProvider) {
            try AIConfigurationStore.save(.defaults(for: .direct), apiKey: "", settings: settings, credentials: keys)
        }
    }

    @Test("Retirer Direct préserve le profil LM Studio déjà enregistré")
    func retiringDirectKeepsEndpoint() throws {
        let context = try context()
        let settings = AppSettings(provider: .direct)
        var local = AIEndpointProfile.defaults(for: .lmStudio)
        local.model = "server-model"
        settings.aiProfilesJSON = try AIConfigurationStore.encode([.defaults(for: .direct), local])
        context.insert(settings)
        try AIConfigurationStore.migrate(settings, credentials: MemoryAICredentials())
        #expect(settings.provider == .lmStudio)
        #expect(settings.modelName == "server-model")
    }

    @Test("Un échec du Trousseau conserve la clé et les réglages historiques")
    func failedMigration() throws {
        let context = try context()
        let settings = AppSettings(cloudToken: "retain-me", provider: .openai)
        context.insert(settings)
        let credentials = MemoryAICredentials()
        credentials.failWrites = true
        #expect(throws: AIEndpointError.credentialStorage) { try AIConfigurationStore.migrate(settings, credentials: credentials) }
        #expect(settings.cloudToken == "retain-me")
        #expect(settings.aiProfilesJSON.isEmpty)
        credentials.failWrites = false
        credentials.failReads = true
        #expect(throws: AIEndpointError.credentialStorage) { try AIConfigurationStore.migrate(settings, credentials: credentials) }
        #expect(settings.cloudToken == "retain-me")
        #expect(settings.aiProfilesJSON.isEmpty)
    }

    @Test("Chaque endpoint garde son modèle et son secret, l'instantané reste stable")
    func switchingAndSnapshot() throws {
        let context = try context()
        let settings = AppSettings()
        context.insert(settings)
        let keys = MemoryAICredentials()
        var local = AIEndpointProfile.defaults(for: .lmStudio)
        local.model = "local-model"
        try AIConfigurationStore.save(local, apiKey: "local-key", settings: settings, credentials: keys)
        let snapshot = try AIConfigurationStore.resolve(settings, credentials: keys)
        var remote = AIEndpointProfile.defaults(for: .openRouter)
        remote.model = "vendor/model"
        try AIConfigurationStore.save(remote, apiKey: "remote-key", settings: settings, credentials: keys)
        #expect(snapshot.profile.model == "local-model")
        #expect(snapshot.apiKey == "local-key")
        let profiles = try AIConfigurationStore.profiles(for: settings)
        let retained = try #require(profiles.first { $0.provider == .lmStudio })
        #expect(retained.model == "local-model")
        #expect(try keys.read(id: #require(retained.credentialID)) == "local-key")
        #expect(try AIConfigurationStore.resolve(settings, credentials: keys).apiKey == "remote-key")
        #expect(!settings.aiProfilesJSON.contains("remote-key"))
        #expect(!settings.aiProfilesJSON.contains("local-key"))
    }

    @Test("Valeur inconnue ou JSON corrompu : aucun repli ni écrasement silencieux")
    func invalidConfiguration() throws {
        let settings = AppSettings()
        settings.providerRaw = "future-provider"
        #expect(throws: AIEndpointError.invalidConfiguration) { try AIConfigurationStore.profile(for: settings) }
        #expect(settings.providerRaw == "future-provider")
        settings.provider = .lmStudio
        settings.aiProfilesJSON = "not-json"
        #expect(throws: AIEndpointError.invalidConfiguration) { try AIConfigurationStore.profiles(for: settings) }
        #expect(settings.aiProfilesJSON == "not-json")
    }

    @Test("Réouverture d'un store disque avec profils et référence Trousseau")
    func diskRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.store")
        let keys = MemoryAICredentials()
        do {
            let container = try ModelContainer(for: Schema(CurrentSchema.models), configurations: [ModelConfiguration(url: url)])
            let context = ModelContext(container)
            let settings = AppSettings(cloudToken: "migrate-secret", apiEndpoint: "http://localhost:11434/v1", modelName: "legacy-model", provider: .ollama)
            context.insert(settings)
            try context.save()
            try AIConfigurationStore.migrate(settings, credentials: keys)
        }
        let reopened = try ModelContainer(for: Schema(CurrentSchema.models), configurations: [ModelConfiguration(url: url)])
        let context = ModelContext(reopened)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.cloudToken.isEmpty)
        let configuration = try AIConfigurationStore.resolve(settings, credentials: keys)
        #expect(configuration.profile.model == "legacy-model")
        #expect(configuration.apiKey == "migrate-secret")
    }

    @Test("Sauvegarde sans clés, restauration des profils et lecture d'un ancien export")
    func backupRoundTrip() throws {
        let source = try context()
        let settings = AppSettings(cloudToken: "never-export", provider: .openai)
        source.insert(settings)
        let keys = MemoryAICredentials()
        var remote = AIEndpointProfile.defaults(for: .openRouter)
        remote.model = "vendor/model"
        try AIConfigurationStore.save(remote, apiKey: "remote-secret", settings: settings, credentials: keys)
        let data = try BackupService().backup(settings: settings, entities: [], projects: [], collaborators: [])
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("never-export"))
        #expect(!text.contains("remote-secret"))
        #expect(!text.contains("credentialID"))
        #expect(!text.contains("cloudToken"))
        let target = try context()
        try BackupService().restore(from: data, into: target)
        let restored = try #require(target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(restored.provider == .openRouter)
        #expect(try AIConfigurationStore.profile(for: restored).model == "vendor/model")
        #expect(try AIConfigurationStore.resolve(restored, credentials: keys).apiKey == "")

        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var oldSettings = try #require(json["settings"] as? [String: Any])
        oldSettings.removeValue(forKey: "aiProfilesJSON")
        oldSettings.removeValue(forKey: "aiConfigurationVersion")
        oldSettings["provider"] = AIProvider.openai.rawValue
        oldSettings["cloudToken"] = "import-old-key"
        json["settings"] = oldSettings
        let oldTarget = try context()
        try BackupService().restore(from: JSONSerialization.data(withJSONObject: json), into: oldTarget)
        let oldRestored = try #require(oldTarget.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(try AIConfigurationStore.resolve(oldRestored, credentials: keys).apiKey == "import-old-key")
        #expect(oldRestored.cloudToken.isEmpty)
    }

    @Test("Backup de version inconnue refusé avant de supprimer les données")
    func futureBackupRejected() throws {
        let target = try context()
        let settings = AppSettings()
        target.insert(settings)
        let data = try BackupService().backup(settings: settings, entities: [], projects: [], collaborators: [])
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var config = try #require(json["settings"] as? [String: Any])
        config["aiConfigurationVersion"] = 999
        json["settings"] = config
        let future = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: AIEndpointError.invalidConfiguration) { try BackupService().restore(from: future, into: target) }
        #expect(try target.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }
}

@Suite("Contrat de transport des endpoints")
struct AIEndpointContractTests {
    @Test("URL, auth et limite de sortie sont validées sans réseau")
    func requests() throws {
        var local = AIEndpointProfile.defaults(for: .lmStudio)
        local.model = "test"
        local.baseURL = "http://localhost:1234/v1/"
        var config = AIRequestConfiguration(profile: local, apiKey: "")
        let request = try OpenAICompatibleClient().request(configuration: config, path: "chat/completions")
        #expect(request.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        config.apiKey = "local-token"
        #expect(try OpenAICompatibleClient().request(configuration: config, path: "models").value(forHTTPHeaderField: "Authorization") == "Bearer local-token")
        config.profile = .defaults(for: .openRouter)
        config.profile.model = "vendor/test"
        #expect(try config.profile.url(for: "models").absoluteString == "https://openrouter.ai/api/v1/models")
        config.apiKey = ""
        #expect(throws: AIEndpointError.missingKey) { try config.validate() }
        config.profile.baseURL = "https://another-host.test/v1"
        #expect(throws: AIEndpointError.invalidURL) { try config.validate() }
    }

    private func body(_ provider: AIProvider, model: String = "qwen3.8-27b", _ level: AIReasoningLevel) throws -> [String: Any] {
        var profile = AIEndpointProfile.defaults(for: provider)
        profile.model = model
        profile.reasoning = level
        let data = try OpenAICompatibleClient.requestBody(prompt: "Bonjour", configuration: AIRequestConfiguration(profile: profile, apiKey: "k"), stream: false)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Le niveau par défaut laisse la requête strictement inchangée", arguments: AIProvider.endpointProviders)
    func defaultReasoningBody(provider: AIProvider) throws {
        let json = try body(provider, .modelDefault)
        #expect(Set(json.keys) == ["model", "messages", "stream", "max_tokens"])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Bonjour"]])
        #expect(json["max_tokens"] as? Int == 24576)
    }

    @Test("Ollama reçoit reasoning_effort, OpenRouter reasoning.effort", arguments: [
        (AIReasoningLevel.low, "low"), (.medium, "medium"), (.high, "high"), (.xhigh, "xhigh"), (.off, "none")])
    func remoteReasoningBodies(level: AIReasoningLevel, wire: String) throws {
        let ollama = try body(.ollama, level)
        #expect(ollama["reasoning_effort"] as? String == wire)
        #expect(ollama["reasoning"] == nil)
        #expect((ollama["messages"] as? [[String: String]])?.count == 1)
        let openRouter = try body(.openRouter, level)
        #expect((openRouter["reasoning"] as? [String: String]) == ["effort": wire])
        #expect(openRouter["reasoning_effort"] == nil)
        #expect((openRouter["messages"] as? [[String: String]])?.count == 1)
    }

    @Test("LM Studio : consigne système reprise du template Qwen, désactivation par préremplissage")
    func lmStudioReasoningBodies() throws {
        let low = try body(.lmStudio, .low)
        #expect(low["reasoning_effort"] == nil && low["reasoning"] == nil)
        let lowMessages = try #require(low["messages"] as? [[String: String]])
        #expect(lowMessages.count == 2)
        #expect(lowMessages[0]["role"] == "system")
        #expect(lowMessages[0]["content"]?.hasPrefix("Reasoning effort is set to low.") == true)
        #expect(lowMessages[1] == ["role": "user", "content": "Bonjour"])
        for level in [AIReasoningLevel.xhigh, .high] {
            let messages = try #require(try body(.lmStudio, level)["messages"] as? [[String: String]])
            #expect(messages.first?["content"]?.hasPrefix("Reasoning effort is set to xhigh.") == true)
        }
        #expect((try body(.lmStudio, .medium)["messages"] as? [[String: String]])?.first?["content"]?.hasPrefix("Reasoning effort is set to medium.") == true)
        let off = try #require(try body(.lmStudio, .off)["messages"] as? [[String: String]])
        #expect(off == [["role": "user", "content": "Bonjour"], ["role": "assistant", "content": "\n</think>\n\n"]])
        // Hors famille Qwen, le préremplissage n'est pas envoyé : requête par défaut.
        let gemma = try #require(try body(.lmStudio, model: "google/gemma-4-31b", .off)["messages"] as? [[String: String]])
        #expect(gemma == [["role": "user", "content": "Bonjour"]])
    }

    @Test("Les niveaux proposés dépendent du fournisseur et du modèle")
    func reasoningSupport() {
        var profile = AIEndpointProfile.defaults(for: .lmStudio)
        profile.model = "Qwen3.8-27B"
        #expect(AIReasoningLevel.available(for: profile) == AIReasoningLevel.allCases)
        profile.model = "google/gemma-4-31b"
        #expect(AIReasoningLevel.available(for: profile) == AIReasoningLevel.allCases.filter { $0 != .off })
        profile.model = ""
        #expect(!AIReasoningLevel.available(for: profile).contains(.off))
        for provider in [AIProvider.ollama, .openRouter] {
            #expect(AIReasoningLevel.available(for: .defaults(for: provider)) == AIReasoningLevel.allCases)
        }
        #expect(AIReasoningLevel.available(for: .defaults(for: .openai)) == [.modelDefault])
        #expect(AIReasoningLevel.allCases.map(\.rawValue) == ["default", "off", "low", "medium", "high", "xhigh"])
    }

    @Test("Décode SSE multiligne, Unicode et métadonnées sans polluer le texte")
    func streaming() throws {
        var parser = AICompletionStream()
        let lines = [": heartbeat", "", "data: {\"choices\": [", "data: {\"delta\":{\"content\":\"Été 🌞\",\"reasoning\":\"secret\"}}]}", "",
                     "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}", "",
                     "data: {\"choices\":[],\"usage\":{\"total_tokens\":4}}", "", "data: [DONE]", ""]
        for line in lines { _ = try parser.consume(line: line) }
        #expect(try parser.result() == "Été 🌞")
    }

    @Test("Fin manquante, troncature et erreur HTTP 200 ne deviennent pas un succès")
    func brokenStreaming() throws {
        var parser = AICompletionStream()
        _ = try parser.consume(line: "data: {\"choices\":[{\"delta\":{\"content\":\"partiel\"}}]}")
        _ = try parser.consume(line: "")
        #expect(throws: AIEndpointError.incompleteResponse) { try parser.result() }
        _ = try parser.consume(line: "data: {\"error\":{\"message\":\"private request\"}}")
        #expect(throws: AIEndpointError.serverError) { try parser.consume(line: "") }
        var truncated = AICompletionStream()
        _ = try truncated.consume(line: "data: {\"choices\":[{\"finish_reason\":\"length\"}]}")
        #expect(throws: AIEndpointError.truncatedResponse) { try truncated.consume(line: "") }
    }
}

private final class AIStubURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, String, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let (code, body, type) = try handler!(request)
            if code == 0 { return } // laisse la requête en attente pour tester l'annulation
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Découpe aussi au milieu des caractères UTF-8.
            for byte in body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite("HTTP IA simulé", .serialized)
struct AIEndpointHTTPTests {
    @Test("Le catalogue public OpenRouter ne requiert ni clé ni modèle")
    func publicOpenRouterCatalog() async throws {
        let client = client { request in
            #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (200, #"{"data":[{"id":"vendor/model"}]}"#, "application/json")
        }
        defer { client.session.invalidateAndCancel() }
        let configuration = AIRequestConfiguration(profile: .defaults(for: .openRouter), apiKey: "")
        #expect(try await client.models(configuration: configuration).map(\.id) == ["vendor/model"])
        await #expect(throws: AIEndpointError.missingKey) { try await client.send(prompt: "test", configuration: configuration) }
    }

    @Test("Ollama utilise le catalogue et le transport communs")
    func ollamaCatalogAndChat() async throws {
        let client = client { request in
            #expect(request.url?.host == "localhost")
            #expect(request.url?.port == 11434)
            if request.url?.path == "/v1/models" {
                return (200, #"{"data":[{"id":"qwen3:8b"}]}"#, "application/json")
            }
            #expect(request.url?.path == "/v1/chat/completions")
            return (200, #"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#, "application/json")
        }
        defer { client.session.invalidateAndCancel() }
        var configuration = AIRequestConfiguration(profile: .defaults(for: .ollama), apiKey: "")
        #expect(try await client.models(configuration: configuration).map(\.id) == ["qwen3:8b"])
        configuration.profile.model = "qwen3:8b"
        #expect(try await client.send(prompt: "test", configuration: configuration) == "OK")
    }

    @Test("Catalogue public réel — vérification réseau facultative")
    func livePublicCatalog() async throws {
        guard ProcessInfo.processInfo.environment["ONETOONE_AI_LIVE_CATALOG"] == "1" else { return }
        let configuration = AIRequestConfiguration(profile: .defaults(for: .openRouter), apiKey: "")
        let models = try await OpenAICompatibleClient().models(configuration: configuration)
        #expect(!models.isEmpty)
        print("Catalogue OpenRouter décodé : \(models.count) modèles textuels")
    }
    /// Vérification réelle des niveaux de raisonnement sur les serveurs locaux,
    /// à la demande : `ONETOONE_AI_LIVE_REASONING=1 swift test --filter liveReasoning`.
    /// Modèles surchargeables via `ONETOONE_LIVE_LMSTUDIO_MODEL` et `ONETOONE_LIVE_OLLAMA_MODEL` ;
    /// `ONETOONE_LIVE_PROVIDERS` (valeurs persistées, ex. `Ollama`) restreint les serveurs testés.
    @Test("Niveaux de raisonnement réels sur LM Studio et Ollama — facultatif")
    func liveReasoning() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["ONETOONE_AI_LIVE_REASONING"] == "1" else { return }
        let cases: [(AIProvider, String, AIReasoningLevel, Bool)] = [
            (.lmStudio, env["ONETOONE_LIVE_LMSTUDIO_MODEL"] ?? "qwen3.8-27b", .modelDefault, true),
            (.lmStudio, env["ONETOONE_LIVE_LMSTUDIO_MODEL"] ?? "qwen3.8-27b", .off, false),
            (.ollama, env["ONETOONE_LIVE_OLLAMA_MODEL"] ?? "qwen3.8:27b-mlx", .xhigh, true),
            (.ollama, env["ONETOONE_LIVE_OLLAMA_MODEL"] ?? "qwen3.8:27b-mlx", .off, false),
        ]
        let providers = (env["ONETOONE_LIVE_PROVIDERS"] ?? "lmStudio,Ollama").split(separator: ",").map(String.init)
        for (provider, model, level, expectsReasoning) in cases where providers.contains(provider.rawValue) {
            var profile = AIEndpointProfile.defaults(for: provider)
            profile.model = model
            profile.reasoning = level
            profile.maxOutputTokens = 512
            let recorder = AIActivityRecorder()
            let text = try await OpenAICompatibleClient().send(prompt: "Réponds uniquement par : OK",
                configuration: AIRequestConfiguration(profile: profile, apiKey: env["ONETOONE_LIVE_LMSTUDIO_TOKEN"] ?? ""),
                onActivity: { await recorder.append($0) })
            let activities = await recorder.values
            let reasoned = activities.contains { if case .reasoning = $0 { return true } else { return false } }
            #expect(text.contains("OK"), "\(provider) \(level)")
            #expect(reasoned == expectsReasoning, "\(provider) \(level) → \(activities)")
            print("Live \(provider.displayName) \(level.rawValue): raisonnement=\(reasoned) texte=\(text.prefix(40))")
        }
    }

    @Test("L'annulation interrompt une requête en attente")
    func cancelRequest() async throws {
        let client = client { _ in (0, "", "") }
        defer { client.session.invalidateAndCancel() }
        let task = Task { try await client.send(prompt: "test", configuration: configuration) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Le client HTTP rejette les sorties vides, tronquées et refusées", arguments: ["length", "content_filter", "tool_calls", "stop"])
    func invalidResponses(reason: String) async throws {
        let client = client { _ in
            (200, "{\"choices\":[{\"message\":{\"content\":\"\"},\"finish_reason\":\"\(reason)\"}]}", "application/json")
        }
        defer { client.session.invalidateAndCancel() }
        let expected: AIEndpointError = reason == "length" ? .truncatedResponse : (reason == "stop" ? .emptyResponse : .refused)
        await #expect(throws: expected) { try await client.send(prompt: "test", configuration: configuration) }
    }

    @Test("Une erreur en SSE après du texte ne valide pas le brouillon")
    func streamFailure() async throws {
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"partiel\"}}]}\r\n\r\n" +
                   "data: {\"error\":{\"message\":\"private\"}}\r\n\r\n"
        let client = client { _ in (200, body, "text/event-stream") }
        defer { client.session.invalidateAndCancel() }
        await #expect(throws: AIEndpointError.serverError) {
            try await client.send(prompt: "test", configuration: configuration, onProgress: { _ in })
        }
    }
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, String, String)) -> OpenAICompatibleClient {
        AIStubURLProtocol.lock.lock()
        AIStubURLProtocol.handler = handler
        AIStubURLProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AIStubURLProtocol.self]
        return OpenAICompatibleClient(session: URLSession(configuration: config))
    }
    private var configuration: AIRequestConfiguration {
        var profile = AIEndpointProfile.defaults(for: .lmStudio)
        profile.model = "test-model"
        return AIRequestConfiguration(profile: profile, apiKey: "")
    }

    @Test("Requête et réponse texte sans secret local obligatoire")
    func send() async throws {
        let client = client { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (200, #"{"choices":[{"message":{"content":"Bonjour"},"finish_reason":"stop"}]}"#, "application/json")
        }
        defer { client.session.invalidateAndCancel() }
        #expect(try await client.send(prompt: "test", configuration: configuration) == "Bonjour")
    }

    @Test("Streaming HTTP réel du client, octets UTF-8 et lignes vides")
    func streamOverHTTP() async throws {
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"Été 🌞\"}}]}\n\n" +
                   "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
                   "data: [DONE]\n\n"
        let client = client { _ in (200, body, "text/event-stream") }
        defer { client.session.invalidateAndCancel() }
        #expect(try await client.send(prompt: "test", configuration: configuration, onProgress: { _ in }) == "Été 🌞")
    }

    @Test("Le suivi seul active le SSE et reçoit le raisonnement puis la rédaction")
    func activityWithoutTextCallback() async throws {
        let body = "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"privé\"}}]}\n\n" +
                   "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"},\"finish_reason\":\"stop\"}]}\n\n" +
                   "data: [DONE]\n\n"
        let recorder = AIActivityRecorder()
        let client = client { request in
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            return (200, body, "text/event-stream")
        }
        defer { client.session.invalidateAndCancel() }
        let result = try await client.send(prompt: "test", configuration: configuration,
            onActivity: { await recorder.append($0) })
        #expect(result == "OK")
        #expect(await recorder.values == [.waiting, .reasoning(5), .writing(2)])
    }

    @Test("Catalogue : métadonnées, doublons et filtrage des modèles incompatibles")
    func catalog() async throws {
        let client = client { request in
            #expect(request.url?.path == "/v1/models")
            return (200, #"{"data":[{"id":"text","architecture":{"input_modalities":["text"],"output_modalities":["text"]}},{"id":"text"},{"id":"embed","type":"embeddings"},{"id":"audio","architecture":{"output_modalities":["audio"]}},{"id":"unknown"}]}"#, "application/json")
        }
        defer { client.session.invalidateAndCancel() }
        #expect(try await client.models(configuration: configuration).map(\.id) == ["text", "unknown"])
    }

    @Test("Erreurs HTTP lisibles sans exposer le corps de la requête", arguments: [401, 402, 404, 429, 503])
    func errors(code: Int) async throws {
        let client = client { _ in (code, "private prompt", "application/json") }
        defer { client.session.invalidateAndCancel() }
        await #expect(throws: AIEndpointError.http(code)) { try await client.send(prompt: "test", configuration: configuration) }
    }
}
