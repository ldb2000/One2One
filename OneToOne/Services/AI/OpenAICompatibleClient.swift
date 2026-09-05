import Foundation
import os

/// Aucune redirection : un jeton ne doit pas suivre un changement de destination.
final class AIRequestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Appel d'outil proposé par le modèle (`message.tool_calls[]`). Défini au
/// niveau fichier — et non imbriqué dans `AICompletion`, privée — pour rester
/// réutilisable par `ToolRouter` et `AIClient`. `Encodable` en plus de
/// `Decodable` : le tour suivant de la boucle d'outils doit renvoyer ce même
/// tool_call dans le message assistant, sinon le modèle perd le fil de ce
/// qu'il a demandé.
struct ToolCall: Codable, Sendable, Equatable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable, Sendable, Equatable {
    let name: String
    let arguments: String
}

/// Résultat d'un tour `chat/completions` avec tools : soit une réponse texte
/// finale, soit une liste d'appels d'outils à exécuter localement avant de
/// reboucler (voir `AIClient.sendWithToolLoop`).
enum SendResult: Sendable {
    case text(String)
    case toolCalls([ToolCall])
}

/// Message de conversation pour la boucle tool-calling (format `messages[]`
/// OpenAI). `tool_calls` porte les appels proposés par un message assistant ;
/// `tool_call_id` identifie le résultat d'un message de rôle `tool`. Encodage
/// manuel : les champs absents (nil) ne doivent pas apparaître en JSON.
struct ConversationMessage: Encodable, Sendable {
    var role: String
    var content: String? = nil
    var tool_calls: [ToolCall]? = nil
    var tool_call_id: String? = nil

    static func user(_ content: String) -> ConversationMessage { .init(role: "user", content: content) }
    static func system(_ content: String) -> ConversationMessage { .init(role: "system", content: content) }
    static func assistant(content: String? = nil, toolCalls: [ToolCall]? = nil) -> ConversationMessage {
        .init(role: "assistant", content: content, tool_calls: toolCalls)
    }
    static func toolResult(callID: String, content: String) -> ConversationMessage {
        .init(role: "tool", content: content, tool_call_id: callID)
    }
}

struct OpenAICompatibleClient: Sendable {
    let session: URLSession
    private static let log = Logger(subsystem: "com.onetoone.app", category: "ai-endpoint")

    init(session: URLSession = .shared) { self.session = session }

    func request(configuration: AIRequestConfiguration, path: String) throws -> URLRequest {
        let catalog = path == "models"
        // OpenRouter publie son catalogue sans authentification. La génération
        // exige toujours une clé ; LM Studio/Ollama reçoivent le jeton si fourni.
        try configuration.validate(requireModel: !catalog, requireAPIKey: !catalog)
        var request = URLRequest(url: try configuration.profile.url(for: path))
        request.timeoutInterval = catalog ? 20 : (configuration.profile.isOnDevice ? 600 : 180)
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func send(prompt: String, configuration: AIRequestConfiguration,
              onProgress: AIClient.ProgressCallback? = nil,
              onActivity: AIClient.ActivityCallback? = nil) async throws -> String {
        do { return try await performSend(prompt: prompt, configuration: configuration, onProgress: onProgress, onActivity: onActivity) }
        catch { throw normalize(error, provider: configuration.profile.provider) }
    }

    private func performSend(prompt: String, configuration: AIRequestConfiguration,
                             onProgress: AIClient.ProgressCallback?,
                             onActivity: AIClient.ActivityCallback?) async throws -> String {
        let started = Date()
        let provider = configuration.profile.provider.rawValue
        defer { Self.log.info("Génération \(provider, privacy: .public) — \(Date().timeIntervalSince(started)) s") }
        var request = try request(configuration: configuration, path: "chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.requestBody(prompt: prompt, configuration: configuration,
                                                stream: onProgress != nil || onActivity != nil)
        try Task.checkCancellation()
        await onActivity?(.waiting)
        if onProgress != nil || onActivity != nil {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request, delegate: AIRequestDelegate())
            defer { bytes.task.cancel() }
            do {
                try check(response)
                var parser = AICompletionStream()
                // AsyncBytes.lines omet les lignes vides, indispensables au SSE.
                for try await byte in bytes {
                    try Task.checkCancellation()
                    let previousActivity = parser.activity
                    if let text = try parser.consume(byte: byte) { await onProgress?(text) }
                    if parser.activity != previousActivity { await onActivity?(parser.activity) }
                    if parser.isDone { break }
                }
                return try parser.result()
            } catch {
                bytes.task.cancel()
                throw error
            }
        }
        let (data, response) = try await session.data(for: request, delegate: AIRequestDelegate())
        try Task.checkCancellation()
        try check(response)
        let decoded = try decode(data)
        guard decoded.error == nil else { throw AIEndpointError.serverError }
        guard let choice = decoded.choices?.first else { throw AIEndpointError.invalidResponse }
        try validateFinish(choice.finish_reason)
        switch try Self.extractResult(from: choice) {
        case .text(let text): return text
        // `send()` n'orchestre pas de boucle d'outils : un appel non prévu ici
        // (aucun tool déclaré dans la requête) reste un refus, comme avant.
        case .toolCalls: throw AIEndpointError.refused
        }
    }

    /// Lit `message.refusal` / `message.tool_calls` / `message.content` d'un
    /// choix décodé et les range en `SendResult`. Les tool_calls ne sont plus
    /// systématiquement un refus (anti-pattern précédent) : c'est la fin
    /// normale d'un tour tool-calling, à l'appelant de décider quoi en faire.
    private static func extractResult(from choice: AICompletion.Choice) throws -> SendResult {
        guard choice.message?.refusal == nil else { throw AIEndpointError.refused }
        if let calls = choice.message?.tool_calls, !calls.isEmpty {
            return .toolCalls(calls)
        }
        guard let text = choice.message?.content, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIEndpointError.emptyResponse
        }
        return .text(text)
    }

    /// Variante tool-calling de `send()` : un tour non-streamé qui peut se
    /// terminer par du texte ou par des `tool_calls` à exécuter localement.
    /// Non-streamé par construction (voir note sur `requestBody(messages:...)`) :
    /// `AIClient.sendWithToolLoop` orchestre les tours suivants.
    func sendWithTools(
        messages: [ConversationMessage],
        configuration: AIRequestConfiguration,
        tools: [ToolSpec]
    ) async throws -> SendResult {
        do { return try await performSendWithTools(messages: messages, configuration: configuration, tools: tools) }
        catch { throw normalize(error, provider: configuration.profile.provider) }
    }

    private func performSendWithTools(
        messages: [ConversationMessage],
        configuration: AIRequestConfiguration,
        tools: [ToolSpec]
    ) async throws -> SendResult {
        var request = try request(configuration: configuration, path: "chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.requestBody(messages: messages, configuration: configuration, tools: tools)
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request, delegate: AIRequestDelegate())
        try Task.checkCancellation()
        try check(response)
        let decoded = try decode(data)
        guard decoded.error == nil else { throw AIEndpointError.serverError }
        guard let choice = decoded.choices?.first else { throw AIEndpointError.invalidResponse }
        try validateFinish(choice.finish_reason)
        return try Self.extractResult(from: choice)
    }

    /// Corps `chat/completions`. Le niveau de raisonnement n'ajoute rien par défaut ;
    /// Ollama lit `reasoning_effort`, OpenRouter `reasoning.effort`. LM Studio ignore
    /// ces champs : consigne système du template Qwen, ou bloc de réflexion vide
    /// prérempli pour désactiver (uniquement modèles Qwen, sinon requête par défaut).
    static func requestBody(prompt: String, configuration: AIRequestConfiguration, stream: Bool, tools: [ToolSpec]? = nil) throws -> Data {
        struct Message: Encodable { var role = "user"; let content: String }
        struct Reasoning: Encodable { let effort: String }
        struct Body: Encodable {
            let model: String
            var messages: [Message]
            let stream: Bool
            let max_tokens: Int
            var reasoning_effort: String? = nil
            var reasoning: Reasoning? = nil
            var tools: [ToolSpec]? = nil
        }
        let profile = configuration.profile
        var body = Body(model: profile.model, messages: [Message(content: prompt)], stream: stream, max_tokens: profile.maxOutputTokens, tools: tools)
        let level = AIReasoningLevel.available(for: profile).contains(profile.reasoning) ? profile.reasoning : .modelDefault
        if let effort = level.effort {
            switch profile.provider {
            case .ollama: body.reasoning_effort = effort
            case .openRouter: body.reasoning = Reasoning(effort: effort)
            case .lmStudio:
                if level == .off {
                    body.messages.append(Message(role: "assistant", content: AIEndpointProfile.qwenEmptyThinkingPrefill))
                } else if let instruction = level.lmStudioInstruction {
                    body.messages.insert(Message(role: "system", content: instruction), at: 0)
                }
            default: break
            }
        }
        return try JSONEncoder().encode(body)
    }

    /// Corps `chat/completions` pour un tour de boucle tool-calling : conversation
    /// complète (`messages`, y compris les tours tool précédents) plutôt qu'un
    /// prompt unique. Toujours non-streamé — voir `sendWithTools`. Le niveau de
    /// raisonnement du profil n'est volontairement pas propagé ici (hors périmètre
    /// de cette PR) ; seuls modèle, limite de sortie et tools le sont.
    static func requestBody(messages: [ConversationMessage], configuration: AIRequestConfiguration, tools: [ToolSpec]) throws -> Data {
        struct Body: Encodable {
            let model: String
            var messages: [ConversationMessage]
            let stream = false
            let max_tokens: Int
            var tools: [ToolSpec]?
        }
        let profile = configuration.profile
        let body = Body(model: profile.model, messages: messages, max_tokens: profile.maxOutputTokens, tools: tools)
        return try JSONEncoder().encode(body)
    }

    func models(configuration: AIRequestConfiguration) async throws -> [AIModelDescriptor] {
        do { return try await loadModels(configuration: configuration) }
        catch { throw normalize(error, provider: configuration.profile.provider) }
    }

    private func loadModels(configuration: AIRequestConfiguration) async throws -> [AIModelDescriptor] {
        let request = try request(configuration: configuration, path: "models")
        let (data, response) = try await session.data(for: request, delegate: AIRequestDelegate())
        try Task.checkCancellation()
        try check(response)
        struct Catalog: Decodable { let data: [AIModelDescriptor] }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            throw AIEndpointError.invalidResponse
        }
        var seen = Set<String>()
        return catalog.data.filter { !$0.id.isEmpty && $0.supportsTextGeneration && seen.insert($0.id).inserted }
            .sorted { ($0.name ?? $0.id).localizedStandardCompare($1.name ?? $1.id) == .orderedAscending }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AIEndpointError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AIEndpointError.http(http.statusCode) }
    }

    private func normalize(_ error: Error, provider: AIProvider) -> Error {
        if error is CancellationError { return error }
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .cancelled: return CancellationError()
        case .timedOut: return AIEndpointError.timedOut
        case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost:
            return AIEndpointError.unavailable(provider.displayName)
        default: return error
        }
    }
}

struct AIModelDescriptor: Decodable, Identifiable, Equatable, Sendable {
    struct Architecture: Decodable, Equatable, Sendable {
        var input_modalities: [String]?
        var output_modalities: [String]?
    }
    let id: String
    var name: String?
    var type: String?
    var context_length: Int?
    var supported_parameters: [String]?
    var architecture: Architecture?

    var supportsTextGeneration: Bool {
        if type == "embeddings" || type == "embedding" { return false }
        if let inputs = architecture?.input_modalities, !inputs.contains("text") { return false }
        if let outputs = architecture?.output_modalities { return outputs.contains("text") }
        return true // Capacité inconnue : sélection manuelle et test restent possibles.
    }
}

private struct AICompletion: Decodable {
    struct APIError: Decodable { let message: String? }
    struct Content: Decodable {
        var content: String?
        var reasoning: String?
        var reasoning_content: String?
        var refusal: String?
        var tool_calls: [ToolCall]?
    }
    struct Choice: Decodable {
        var delta: Content?
        var message: Content?
        var finish_reason: String?
    }
    var choices: [Choice]?
    var error: APIError?
}

private func decode(_ data: Data) throws -> AICompletion {
    guard let result = try? JSONDecoder().decode(AICompletion.self, from: data) else {
        throw AIEndpointError.invalidResponse
    }
    return result
}

private func validateFinish(_ reason: String?) throws {
    switch reason {
    // tool_calls/function_call est la fin NORMALE d'un tour qui demande un
    // outil (pas une erreur) : `message.tool_calls` porte l'information,
    // géré par `OpenAICompatibleClient.extractResult`.
    case "stop", "tool_calls", "function_call": return
    case "length", "max_tokens": throw AIEndpointError.truncatedResponse
    case "content_filter": throw AIEndpointError.refused
    case "error": throw AIEndpointError.serverError
    default: throw AIEndpointError.incompleteResponse
    }
}

/// Décode les événements SSE, et non les seules lignes JSON. Les deltas de
/// raisonnement et d'usage ne sont jamais concaténés au texte métier.
struct AICompletionStream {
    private(set) var activity: AIClient.Activity = .waiting
    private var reasoningCharacters = 0
    private var fields: [String] = []
    private var lineBytes: [UInt8] = []
    private var previousWasCR = false
    private var isFirstLine = true
    private(set) var text = ""
    private var finishReason: String?
    private(set) var isDone = false

    mutating func consume(byte: UInt8) throws -> String? {
        if byte == 10 && previousWasCR { previousWasCR = false; return nil }
        previousWasCR = byte == 13
        if byte == 10 || byte == 13 {
            guard var line = String(bytes: lineBytes, encoding: .utf8) else { throw AIEndpointError.invalidResponse }
            lineBytes.removeAll(keepingCapacity: true)
            if isFirstLine && line.hasPrefix("\u{feff}") { line.removeFirst() }
            isFirstLine = false
            return try consume(line: line)
        }
        // Borne de protection d'une ligne malformée sans séparateur.
        guard lineBytes.count < 1_048_576 else { throw AIEndpointError.invalidResponse }
        lineBytes.append(byte)
        return nil
    }

    mutating func consume(line: String) throws -> String? {
        if line.isEmpty { return try dispatch() }
        if line.hasPrefix("data:") {
            let value = line.dropFirst(5)
            fields.append(String(value.first == " " ? value.dropFirst() : value))
        }
        return nil
    }

    private mutating func dispatch() throws -> String? {
        guard !fields.isEmpty else { return nil }
        let payload = fields.joined(separator: "\n")
        fields.removeAll(keepingCapacity: true)
        if payload == "[DONE]" { isDone = true; return nil }
        let event = try decode(Data(payload.utf8))
        guard event.error == nil else { throw AIEndpointError.serverError }
        guard let choice = event.choices?.first else { return nil } // événement d'usage
        if let reason = choice.finish_reason {
            try validateFinish(reason)
            finishReason = reason
        }
        if choice.delta?.refusal != nil || choice.delta?.tool_calls?.isEmpty == false {
            throw AIEndpointError.refused
        }
        // Ne conserver ni afficher le raisonnement : seul son volume signale
        // que le serveur travaille, même sans texte de rapport encore reçu.
        if let reasoning = choice.delta?.reasoning_content ?? choice.delta?.reasoning, !reasoning.isEmpty {
            reasoningCharacters += reasoning.count
            activity = .reasoning(reasoningCharacters)
        }
        guard let content = choice.delta?.content, !content.isEmpty else { return nil }
        text += content
        activity = .writing(text.count)
        return text
    }

    func result() throws -> String {
        guard isDone else { throw AIEndpointError.incompleteResponse }
        try validateFinish(finishReason)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIEndpointError.emptyResponse }
        return text
    }
}
