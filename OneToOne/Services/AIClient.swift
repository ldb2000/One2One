import Foundation

/// Centralized AI client that routes to the correct provider.
/// Used by AIIngestionService, AIReformulationService, etc.
enum AIClient {

    /// Callback de progression en streaming. Appelé hors main avec le texte
    /// accumulé jusqu'ici. Le caller est responsable de re-dispatcher sur le
    /// main actor s'il met à jour de l'UI.
    typealias ProgressCallback = @Sendable (String) async -> Void

    /// Send a prompt and get a text response, routing based on provider settings.
    /// `onProgress` reçoit le texte au fur et à mesure pour les providers qui
    /// supportent le streaming (OpenAI-compat, Anthropic). Les autres
    /// (Claude CLI, Gemini OAuth) appellent `onProgress` une seule fois à la
    /// fin avec le texte complet.
    static func send(
        prompt: String,
        settings: AppSettings,
        onProgress: ProgressCallback? = nil
    ) async throws -> String {
        do {
            switch settings.provider {
            case .claudeOAuth:
                let model = settings.modelName.isEmpty ? "claude-sonnet-4-5" : settings.modelName
                let out = try await callClaudeCLI(prompt: prompt, model: model)
                if let onProgress { await onProgress(out) }
                return out
            case .geminiOAuth:
                let out = try await GeminiOAuthClient.shared.sendMessage(
                    prompt: prompt,
                    model: settings.modelName.isEmpty ? "gemini-2.5-pro" : settings.modelName
                )
                if let onProgress { await onProgress(out) }
                return out
            case .anthropic:
                if let onProgress {
                    return try await callAnthropicStream(prompt: prompt, settings: settings, onProgress: onProgress)
                } else {
                    return try await callAnthropic(prompt: prompt, settings: settings)
                }
            default:
                if let onProgress {
                    return try await callOpenAICompatibleStream(prompt: prompt, settings: settings, onProgress: onProgress)
                } else {
                    return try await callOpenAICompatible(prompt: prompt, settings: settings)
                }
            }
        } catch {
            throw normalizeError(error, settings: settings)
        }
    }

    // MARK: - Claude CLI (setup-token / OAuth)

    private static func callClaudeCLI(prompt: String, model: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let pipe = Pipe()
                    let errorPipe = Pipe()

                    // Find claude in PATH
                    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                    process.executableURL = URL(fileURLWithPath: shell)
                    process.arguments = ["-l", "-c", "claude -p \(quoteShellArg(prompt)) --model \(quoteShellArg(model)) --output-format text 2>&1"]
                    process.standardOutput = pipe
                    process.standardError = errorPipe

                    // Inherit user environment for PATH, HOME, etc.
                    var env = ProcessInfo.processInfo.environment
                    env["TERM"] = "dumb"
                    process.environment = env

                    try process.run()
                    process.waitUntilExit()

                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus != 0 {
                        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errOutput = String(data: errData, encoding: .utf8) ?? ""
                        let combined = output.isEmpty ? errOutput : output
                        continuation.resume(throwing: IngestionError.networkError("claude CLI erreur (code \(process.terminationStatus)): \(combined.prefix(300))"))
                    } else if output.isEmpty {
                        continuation.resume(throwing: IngestionError.parseError("claude CLI: reponse vide"))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: IngestionError.networkError("Impossible de lancer claude CLI: \(error.localizedDescription). Verifiez que Claude Code est installe (npm i -g @anthropic-ai/claude-code)."))
                }
            }
        }
    }

    private static func quoteShellArg(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Anthropic (API Key)

    private static func callAnthropic(prompt: String, settings: AppSettings) async throws -> String {
        guard !settings.cloudToken.isEmpty else { throw IngestionError.noAPIKey }

        guard let url = URL(string: settings.apiEndpoint + "/messages") else {
            throw IngestionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.cloudToken, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": settings.modelName,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw IngestionError.apiError(code, body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let contentArray = json?["content"] as? [[String: Any]],
              let textBlock = contentArray.first(where: { $0["type"] as? String == "text" }),
              let content = textBlock["text"] as? String else {
            throw IngestionError.parseError("Cannot extract content from Anthropic response")
        }
        return content
    }

    // MARK: - OpenAI-compatible (OpenAI, Ollama, Gemini)

    private static func callOpenAICompatible(prompt: String, settings: AppSettings) async throws -> String {
        // Ollama doesn't need an API key
        if settings.provider != .ollama {
            guard !settings.cloudToken.isEmpty else { throw IngestionError.noAPIKey }
        }

        let endpoint = settings.apiEndpoint.hasSuffix("/") ? settings.apiEndpoint : settings.apiEndpoint + "/"
        guard let url = URL(string: endpoint + "chat/completions") else {
            throw IngestionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.cloudToken.isEmpty {
            request.setValue("Bearer \(settings.cloudToken)", forHTTPHeaderField: "Authorization")
        }
        // Les modèles locaux (Ollama, mlx-server) peuvent mettre plusieurs
        // minutes à charger leurs poids sur le premier appel après démarrage.
        // 600 s couvre un cold-load de modèle 30-70B Q4 sur Apple Silicon.
        request.timeoutInterval = settings.provider == .ollama ? 600 : 180

        let body: [String: Any] = [
            "model": settings.modelName,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw IngestionError.apiError(code, body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw IngestionError.parseError("Cannot extract content from response")
        }
        return content
    }

    // MARK: - Streaming (OpenAI-compat SSE)

    private static func callOpenAICompatibleStream(
        prompt: String,
        settings: AppSettings,
        onProgress: ProgressCallback
    ) async throws -> String {
        if settings.provider != .ollama {
            guard !settings.cloudToken.isEmpty else { throw IngestionError.noAPIKey }
        }

        let endpoint = settings.apiEndpoint.hasSuffix("/") ? settings.apiEndpoint : settings.apiEndpoint + "/"
        guard let url = URL(string: endpoint + "chat/completions") else {
            throw IngestionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !settings.cloudToken.isEmpty {
            request.setValue("Bearer \(settings.cloudToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = settings.provider == .ollama ? 600 : 180

        let body: [String: Any] = [
            "model": settings.modelName,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var body = Data()
            for try await b in bytes { body.append(b) }
            throw IngestionError.apiError(code, String(data: body, encoding: .utf8) ?? "")
        }

        var accumulated = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" {
                if payload == "[DONE]" { break }
                continue
            }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String,
                  !content.isEmpty
            else { continue }
            accumulated += content
            await onProgress(accumulated)
        }
        return accumulated
    }

    // MARK: - Streaming (Anthropic SSE)

    private static func callAnthropicStream(
        prompt: String,
        settings: AppSettings,
        onProgress: ProgressCallback
    ) async throws -> String {
        guard !settings.cloudToken.isEmpty else { throw IngestionError.noAPIKey }

        guard let url = URL(string: settings.apiEndpoint + "/messages") else {
            throw IngestionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(settings.cloudToken, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 300

        let body: [String: Any] = [
            "model": settings.modelName,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var body = Data()
            for try await b in bytes { body.append(b) }
            throw IngestionError.apiError(code, String(data: body, encoding: .utf8) ?? "")
        }

        var accumulated = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }
            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String,
               !text.isEmpty
            {
                accumulated += text
                await onProgress(accumulated)
            } else if type == "message_stop" {
                break
            }
        }
        return accumulated
    }

    private static func normalizeError(_ error: Error, settings: AppSettings) -> Error {
        if let ingestionError = error as? IngestionError {
            return ingestionError
        }

        if let urlError = error as? URLError {
            if settings.provider == .ollama {
                switch urlError.code {
                case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
                    return IngestionError.networkError(
                        "Ollama ne répond pas sur \(settings.apiEndpoint). Vérifiez qu'Ollama est lancé, qu'un modèle est installé, et que l'endpoint est correct dans Paramètres."
                    )
                default:
                    return IngestionError.networkError("Erreur réseau Ollama: \(urlError.localizedDescription)")
                }
            }

            return IngestionError.networkError(urlError.localizedDescription)
        }

        return error
    }
}
