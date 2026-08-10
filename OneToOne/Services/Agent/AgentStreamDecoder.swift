import Foundation

/// Un événement du flux `--output-format stream-json`, réduit à ce dont
/// l'application a besoin : de quoi reprendre la session, de quoi afficher une
/// progression, de quoi clore le tour.
enum AgentStreamEvent: Equatable, Sendable {
    /// `system`/`init` — l'identifiant sert à `--resume` au tour suivant.
    case sessionStarted(id: String, model: String?)
    /// Texte de l'assistant, affiché comme libellé de progression.
    case progress(String)
    /// L'assistant appelle un outil sans avoir rien dit : on nomme l'outil.
    case toolStarted(name: String)
    /// `system`/`api_retry` — surcharge, limite de débit, erreur réseau.
    case retry(attempt: Int, maxAttempts: Int, reason: String)
    /// `result` — fin du tour, avec le coût estimé côté client.
    case finished(text: String?, costUSD: Double, isError: Bool)
}

/// Décode une ligne du flux du CLI `claude`.
///
/// Contrat : **aucune ligne n'est fatale**. Une ligne tronquée par un tampon, un
/// type d'événement introduit par une version ultérieure du CLI, un avertissement
/// écrit sur stdout — tout ce qui n'est pas reconnu renvoie `nil` et le tour
/// continue. Le seul événement dont l'absence porte à conséquence est `result`,
/// et c'est au `AgentRunner` de la constater, pas au décodeur.
enum AgentStreamDecoder {

    static func decode(line: String) -> AgentStreamEvent? {
        guard let root = object(from: line), let type = root["type"] as? String else { return nil }

        switch type {
        case "system":    return system(root)
        case "assistant": return assistant(root)
        case "result":    return result(root)
        default:          return nil
        }
    }

    // MARK: - Par type

    private static func system(_ root: [String: Any]) -> AgentStreamEvent? {
        switch root["subtype"] as? String {
        case "init":
            // Sans identifiant on ne saurait pas reprendre la session : la ligne
            // ne nous apprend rien d'exploitable.
            guard let id = root["session_id"] as? String else { return nil }
            return .sessionStarted(id: id, model: root["model"] as? String)

        case "api_retry":
            return .retry(
                attempt: root["attempt"] as? Int ?? 1,
                maxAttempts: root["max_retries"] as? Int ?? 0,
                reason: root["error"] as? String ?? "unknown"
            )

        default:
            return nil
        }
    }

    private static func assistant(_ root: [String: Any]) -> AgentStreamEvent? {
        guard let message = root["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return nil }

        let spoken = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Ce que l'agent dit prime sur ce qu'il fait : le texte est plus parlant
        // qu'un nom d'outil dans un libellé de progression.
        if !spoken.isEmpty { return .progress(spoken.joined(separator: " ")) }

        if let tool = content.first(where: { $0["type"] as? String == "tool_use" }),
           let name = tool["name"] as? String {
            return .toolStarted(name: name)
        }

        return nil
    }

    private static func result(_ root: [String: Any]) -> AgentStreamEvent? {
        .finished(
            text: root["result"] as? String,
            costUSD: root["total_cost_usd"] as? Double ?? 0,
            isError: root["is_error"] as? Bool ?? false
        )
    }

    // MARK: - Détail

    private static func object(from line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any]
    }
}
