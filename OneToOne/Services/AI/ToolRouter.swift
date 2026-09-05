import Foundation
import SwiftData

/// Déclaration d'un outil exposé au modèle (format `tools[]` OpenAI,
/// `type: "function"`). Encodable uniquement : jamais décodé, seulement
/// envoyé dans la requête `chat/completions`.
struct ToolSpec: Encodable, Sendable {
    let type = "function"
    let function: FunctionDef

    struct FunctionDef: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable, Sendable {
        let type = "object"
        let properties: [String: PropertyDef]
        let required: [String]
    }

    struct PropertyDef: Encodable, Sendable {
        let type: String         // "string" | "integer" | "boolean"
        let description: String
    }
}

/// Catalogue statique des outils proposés au modèle pendant la boucle
/// tool-calling (voir `AIClient.sendWithToolLoop`).
enum ToolCatalog {
    static let searchKnowledge = ToolSpec(
        function: .init(
            name: "search_knowledge",
            description: """
            Recherche sémantique dans les transcriptions de réunions, rapports, mails et \
            notes indexés dans OneToOne. / Semantic search over indexed meeting transcripts, \
            reports, emails and notes in OneToOne.
            """,
            parameters: .init(
                properties: [
                    "query": .init(
                        type: "string",
                        description: "Termes de recherche en langage naturel. / Natural language search terms."
                    ),
                    "scope": .init(
                        type: "string",
                        description: "Filtre optionnel sur le type de source : \"meeting\", \"attachment\" ou \"mail\". "
                            + "Omettre pour chercher partout. / Optional source-type filter: \"meeting\", \"attachment\" "
                            + "or \"mail\". Omit to search everything."
                    ),
                    "top_k": .init(
                        type: "integer",
                        description: "Nombre de résultats souhaités, entre 1 et 20 (défaut 6). / "
                            + "Desired number of results, between 1 and 20 (default 6)."
                    )
                ],
                required: ["query"]
            )
        )
    )

    static let all: [ToolSpec] = [searchKnowledge]
}

/// Exécute localement les outils demandés par le modèle et retourne toujours
/// un JSON exploitable (jamais une erreur Swift) : un nom d'outil inconnu ou
/// des arguments invalides deviennent `{"error": "..."}`, que le modèle peut
/// lire et corriger au tour suivant plutôt que faire échouer toute la requête.
@MainActor
enum ToolRouter {

    /// Requête `search_knowledge` normalisée, issue du parsing des arguments.
    struct SearchKnowledgeRequest: Equatable {
        let query: String
        let scope: RAGQuery.Scope
        let topK: Int

        static func == (lhs: SearchKnowledgeRequest, rhs: SearchKnowledgeRequest) -> Bool {
            lhs.query == rhs.query && lhs.topK == rhs.topK && lhs.scope.sourceType == rhs.scope.sourceType
        }
    }

    private struct SearchKnowledgeArguments: Decodable {
        let query: String
        let scope: String?
        let top_k: Int?
    }

    private struct SearchResultItem: Encodable {
        let id: String
        let text: String
        let meetingTitle: String?
        let meetingDate: Date?
        let attachmentFileName: String?
        let mailSubject: String?
        let similarity: Float
        let sourceType: String
    }

    static func execute(_ call: ToolCall, context: ModelContext) async -> String {
        switch call.function.name {
        case "search_knowledge":
            return await searchKnowledge(argumentsJSON: call.function.arguments, context: context)
        default:
            return errorJSON("unknown_tool")
        }
    }

    private static func searchKnowledge(argumentsJSON: String, context: ModelContext) async -> String {
        guard let request = parseSearchKnowledgeArguments(argumentsJSON) else {
            return errorJSON("invalid_arguments")
        }
        do {
            let hits = try await RAGQuery.search(query: request.query, topK: request.topK, scope: request.scope, context: context)
            return serialize(hits)
        } catch {
            return errorJSON("search_failed")
        }
    }

    // MARK: - Parsing (pur, testable sans I/O)

    /// `nil` si `query` absente ou vide après trim. `top_k` hors `[1, 20]` est
    /// ramené à la borne la plus proche plutôt que rejeté ; un `scope` inconnu
    /// est ignoré (recherche non filtrée) — le modèle peut inventer une valeur
    /// approchante, ce n'est pas une raison de faire échouer l'appel.
    nonisolated static func parseSearchKnowledgeArguments(_ json: String) -> SearchKnowledgeRequest? {
        guard let data = json.data(using: .utf8),
              let args = try? JSONDecoder().decode(SearchKnowledgeArguments.self, from: data)
        else { return nil }
        let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var scope = RAGQuery.Scope()
        if let raw = args.scope, ["meeting", "attachment", "mail"].contains(raw) {
            scope.sourceType = raw
        }
        let topK = min(max(args.top_k ?? 6, 1), 20)
        return SearchKnowledgeRequest(query: query, scope: scope, topK: topK)
    }

    // MARK: - Sérialisation (pure, testable sans I/O)

    /// Sérialise des résultats déjà obtenus (pas d'appel réseau/embedding ici) :
    /// c'est ce que le modèle reçoit comme contenu du message `tool`.
    nonisolated static func serialize(_ hits: [RAGQuery.Result]) -> String {
        let items = hits.map { hit -> SearchResultItem in
            let chunk = hit.chunk
            let linkedMeeting = chunk.meeting ?? chunk.attachment?.meeting
            return SearchResultItem(
                id: chunk.chunkId.uuidString,
                text: chunk.text,
                meetingTitle: linkedMeeting?.title,
                meetingDate: linkedMeeting?.date,
                attachmentFileName: chunk.attachment?.fileName,
                mailSubject: chunk.mail?.subject,
                similarity: hit.similarity,
                sourceType: chunk.sourceType
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return errorJSON("encoding_failed") }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func errorJSON(_ code: String) -> String {
        "{\"error\":\"\(code)\"}"
    }
}
