import Foundation
import SwiftData
import Testing
@testable import OneToOne

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema(CurrentSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

@Suite("ToolSpec — forme JSON envoyée au LLM (B2)")
struct ToolSpecEncodingTests {

    @Test("search_knowledge s'encode en tool OpenAI avec query requis, scope/top_k optionnels")
    func searchKnowledgeShape() throws {
        let data = try JSONEncoder().encode(ToolCatalog.searchKnowledge)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["type"] as? String == "function")
        let function = try #require(json["function"] as? [String: Any])
        #expect(function["name"] as? String == "search_knowledge")
        let description = try #require(function["description"] as? String)
        #expect(description.contains("Recherche sémantique"))
        #expect(description.contains("Semantic search"))

        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["required"] as? [String] == ["query"])

        let properties = try #require(parameters["properties"] as? [String: Any])
        let query = try #require(properties["query"] as? [String: Any])
        #expect(query["type"] as? String == "string")
        let scope = try #require(properties["scope"] as? [String: Any])
        #expect(scope["type"] as? String == "string")
        let topK = try #require(properties["top_k"] as? [String: Any])
        #expect(topK["type"] as? String == "integer")
    }

    @Test("Le catalogue expose exactement search_knowledge pour cette PR")
    func catalogContents() {
        #expect(ToolCatalog.all.count == 1)
    }
}

@Suite("ToolRouter — parsing des arguments (B2)")
struct ToolRouterArgumentParsingTests {

    @Test("query minimale : scope et top_k retombent sur leurs défauts")
    func minimalArguments() throws {
        let request = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"budget Q3"}"#))
        #expect(request.query == "budget Q3")
        #expect(request.scope.sourceType == nil)
        #expect(request.topK == 6)
    }

    @Test("top_k hors bornes est ramené à [1, 20]")
    func topKClamped() throws {
        let tooHigh = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","top_k":999}"#))
        #expect(tooHigh.topK == 20)
        let tooLow = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","top_k":0}"#))
        #expect(tooLow.topK == 1)
        let negative = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","top_k":-5}"#))
        #expect(negative.topK == 1)
    }

    @Test("scope valide est retenu, scope inconnu est ignoré (recherche non filtrée)")
    func scopeValidation() throws {
        let meeting = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","scope":"meeting"}"#))
        #expect(meeting.scope.sourceType == "meeting")
        let mail = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","scope":"mail"}"#))
        #expect(mail.scope.sourceType == "mail")
        let attachment = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","scope":"attachment"}"#))
        #expect(attachment.scope.sourceType == "attachment")
        let bogus = try #require(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"x","scope":"carrier-pigeon"}"#))
        #expect(bogus.scope.sourceType == nil)
    }

    @Test("query vide ou absente, ou JSON illisible, échoue le parsing")
    func invalidArguments() {
        #expect(ToolRouter.parseSearchKnowledgeArguments(#"{"query":""}"#) == nil)
        #expect(ToolRouter.parseSearchKnowledgeArguments(#"{"query":"   "}"#) == nil)
        #expect(ToolRouter.parseSearchKnowledgeArguments(#"{"scope":"mail"}"#) == nil)
        #expect(ToolRouter.parseSearchKnowledgeArguments("not json") == nil)
        #expect(ToolRouter.parseSearchKnowledgeArguments("") == nil)
    }
}

@Suite("ToolRouter — dispatch et sérialisation (B2)")
@MainActor
struct ToolRouterDispatchTests {

    @Test("un nom d'outil inconnu retourne un JSON d'erreur unknown_tool, sans jeter")
    func unknownToolIsReportedAsJSON() async throws {
        let context = try makeContext()
        let call = ToolCall(id: "call_1", type: "function", function: .init(name: "delete_everything", arguments: "{}"))
        let result = await ToolRouter.execute(call, context: context)
        #expect(result == #"{"error":"unknown_tool"}"#)
    }

    @Test("des arguments illisibles pour search_knowledge retournent invalid_arguments")
    func invalidArgumentsAreReportedAsJSON() async throws {
        let context = try makeContext()
        let call = ToolCall(id: "call_2", type: "function", function: .init(name: "search_knowledge", arguments: "not json"))
        let result = await ToolRouter.execute(call, context: context)
        #expect(result == #"{"error":"invalid_arguments"}"#)
    }

    @Test("un résultat de recherche se sérialise avec les champs attendus, y compris via un attachment")
    func serializeIncludesExpectedFields() throws {
        let context = try makeContext()

        let meeting = Meeting(title: "Comité de pilotage", date: Date(timeIntervalSince1970: 1_700_000_000), notes: "")
        context.insert(meeting)

        let meetingChunk = TranscriptChunk(text: "Le socle technique a tenu la charge.", orderIndex: 0, sourceType: "meeting")
        meetingChunk.meeting = meeting
        context.insert(meetingChunk)

        let attachment = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/rapport-comex.pdf"))
        attachment.meeting = meeting
        context.insert(attachment)
        let attachmentChunk = TranscriptChunk(text: "Extrait du rapport COMEX.", orderIndex: 0, sourceType: "attachment")
        attachmentChunk.attachment = attachment
        context.insert(attachmentChunk)

        let mail = ProjectMail(messageId: "m1", accountName: "acc", mailbox: "INBOX", subject: "Point budget", sender: "a@b.test")
        context.insert(mail)
        let mailChunk = TranscriptChunk(text: "Le budget dérive de 5%.", orderIndex: 0, sourceType: "mail")
        mailChunk.mail = mail
        context.insert(mailChunk)

        try context.save()

        let hits = [
            RAGQuery.Result(chunk: meetingChunk, similarity: 0.91),
            RAGQuery.Result(chunk: attachmentChunk, similarity: 0.77),
            RAGQuery.Result(chunk: mailChunk, similarity: 0.5)
        ]

        let json = ToolRouter.serialize(hits)
        let items = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(items.count == 3)

        let meetingItem = try #require(items.first { $0["sourceType"] as? String == "meeting" })
        #expect(meetingItem["text"] as? String == "Le socle technique a tenu la charge.")
        #expect(meetingItem["meetingTitle"] as? String == "Comité de pilotage")
        #expect(meetingItem["meetingDate"] != nil)
        #expect((meetingItem["similarity"] as? Double).map { Float($0) } == 0.91)

        let attachmentItem = try #require(items.first { $0["sourceType"] as? String == "attachment" })
        #expect(attachmentItem["attachmentFileName"] as? String == "rapport-comex.pdf")
        // Le meeting est retrouvé via l'attachment quand le chunk n'a pas de lien direct.
        #expect(attachmentItem["meetingTitle"] as? String == "Comité de pilotage")

        let mailItem = try #require(items.first { $0["sourceType"] as? String == "mail" })
        #expect(mailItem["mailSubject"] as? String == "Point budget")
        #expect(mailItem["meetingTitle"] == nil || (mailItem["meetingTitle"] as? NSNull) != nil)
    }

    @Test("une liste de résultats vide se sérialise en tableau JSON vide")
    func serializeEmpty() {
        #expect(ToolRouter.serialize([]) == "[]")
    }
}

@Suite("AIClient.runToolLoop — orchestration de la boucle d'outils (B2)")
@MainActor
struct ToolLoopOrchestrationTests {

    private actor CallRecorder {
        var messagesPerTurn: [[ConversationMessage]] = []
        func record(_ messages: [ConversationMessage]) { messagesPerTurn.append(messages) }
    }

    @Test("un tour texte direct retourne le texte sans exécuter d'outil")
    func directTextAnswer() async throws {
        let context = try makeContext()
        let result = try await AIClient.runToolLoop(
            prompt: "Bonjour",
            maxTurns: 5,
            onProgress: nil,
            modelContext: context,
            send: { _ in .text("Réponse directe") }
        )
        #expect(result == "Réponse directe")
    }

    @Test("un tool_call puis un texte final : le résultat d'outil est ajouté aux messages du tour suivant")
    func toolCallThenFinalText() async throws {
        let context = try makeContext()
        let recorder = CallRecorder()
        // Nom volontairement hors catalogue : on vérifie ici la mécanique de la
        // boucle (pas ToolRouter, couvert séparément), donc pas de vrai calcul
        // d'embedding — `probe_tool` retombe simplement sur `unknown_tool`.
        let call = ToolCall(id: "call_1", type: "function", function: .init(name: "probe_tool", arguments: "{}"))
        var turn = 0

        let result = try await AIClient.runToolLoop(
            prompt: "Que dit le dernier comité ?",
            maxTurns: 5,
            onProgress: nil,
            modelContext: context,
            send: { messages in
                turn += 1
                await recorder.record(messages)
                if turn == 1 { return .toolCalls([call]) }
                return .text("Voici la synthèse.")
            }
        )

        #expect(result == "Voici la synthèse.")
        let seen = await recorder.messagesPerTurn
        #expect(seen.count == 2)
        // Second tour : le prompt initial, le tool_call assistant, puis le résultat tool.
        #expect(seen[1].count == 3)
        #expect(seen[1][1].role == "assistant")
        #expect(seen[1][1].tool_calls?.first?.id == "call_1")
        #expect(seen[1][2].role == "tool")
        #expect(seen[1][2].tool_call_id == "call_1")
        #expect(seen[1][2].content == #"{"error":"unknown_tool"}"#)
    }

    @Test("un nom d'outil inconnu ne bloque pas la boucle : le tour suivant reçoit unknown_tool")
    func unknownToolContinuesLoop() async throws {
        let context = try makeContext()
        let call = ToolCall(id: "call_1", type: "function", function: .init(name: "does_not_exist", arguments: "{}"))
        var turn = 0

        let result = try await AIClient.runToolLoop(
            prompt: "Question",
            maxTurns: 5,
            onProgress: nil,
            modelContext: context,
            send: { _ in
                turn += 1
                if turn == 1 { return .toolCalls([call]) }
                return .text("OK")
            }
        )
        #expect(result == "OK")
        #expect(turn == 2)
    }

    @Test("dépasser maxTurns jette turnLimitExceeded plutôt que boucler indéfiniment")
    func turnLimitIsEnforced() async throws {
        let context = try makeContext()
        let call = ToolCall(id: "call_1", type: "function", function: .init(name: "probe_tool", arguments: "{}"))

        await #expect(throws: AIToolLoopError.turnLimitExceeded(2)) {
            _ = try await AIClient.runToolLoop(
                prompt: "Question",
                maxTurns: 2,
                onProgress: nil,
                modelContext: context,
                send: { _ in .toolCalls([call]) }
            )
        }
    }

    @Test("onProgress n'est appelé qu'une fois, avec le texte final")
    func onProgressCalledOnceWithFinalText() async throws {
        let context = try makeContext()
        actor ProgressRecorder {
            var values: [String] = []
            func append(_ value: String) { values.append(value) }
        }
        let recorder = ProgressRecorder()
        let call = ToolCall(id: "call_1", type: "function", function: .init(name: "probe_tool", arguments: "{}"))
        var turn = 0

        _ = try await AIClient.runToolLoop(
            prompt: "Question",
            maxTurns: 5,
            onProgress: { text in await recorder.append(text) },
            modelContext: context,
            send: { _ in
                turn += 1
                if turn == 1 { return .toolCalls([call]) }
                return .text("Réponse finale")
            }
        )
        let values = await recorder.values
        #expect(values == ["Réponse finale"])
    }
}

@Suite("AIClient.sendWithToolLoop — providers incompatibles (B2)")
@MainActor
struct ToolLoopProviderCompatibilityTests {

    @Test("Anthropic et Gemini OAuth ne supportent pas ce tool calling : erreur claire avant tout réseau",
          arguments: [AIProvider.anthropic, .geminiOAuth])
    func unsupportedProviderThrowsImmediately(provider: AIProvider) async throws {
        let context = try makeContext()
        let settings = AppSettings(provider: provider)

        await #expect(throws: AIToolLoopError.self) {
            _ = try await AIClient.sendWithToolLoop(
                prompt: "Question",
                settings: settings,
                tools: ToolCatalog.all,
                modelContext: context
            )
        }
    }

    @Test("les providers compatibles OpenAI (LM Studio, OpenRouter, Ollama) passent le garde-fou de compatibilité")
    func compatibleProviderIsAccepted() {
        for provider: AIProvider in [.lmStudio, .openRouter, .ollama] {
            #expect(provider.usesCompatibleEndpoint)
        }
    }
}
