import SwiftUI
import SwiftData

/// Widget de chat inline affiché dans l'onglet « Chat » de `MeetingView`. Conversation
/// éphémère (en RAM, non persistée) : pose des questions sur la réunion en cours en
/// s'appuyant sur un pré-fetch RAG de l'historique (réunion courante exclue du scope,
/// sinon le LLM se nourrirait de lui-même) et, selon le toggle global `chatbotToolCallingEnabled`
/// (B2, cf. `ChatbotView`), sur le tool calling `search_knowledge`.
struct MeetingChatView: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, content: "Pose des questions sur cette réunion, ses documents et l'historique.")
    ]
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Renvoie l'enregistrement `AppSettings` canonique, en crée un si aucun n'existe
    /// encore (même filet de sécurité que `ChatbotView.settings`).
    private var settings: AppSettings {
        if let current = settingsList.canonicalSettings {
            return current
        } else {
            let newSettings = AppSettings()
            context.insert(newSettings)
            try? context.save()
            return newSettings
        }
    }

    /// B2 : quand actif, délègue la recherche au LLM via `AIClient.sendWithToolLoop`
    /// au lieu du pré-fetch RAG. Extrait en fonction statique pure pour rester
    /// testable sans environnement SwiftUI complet — voir `Tests/MeetingChatViewTests.swift`.
    private var useToolCalling: Bool {
        Self.shouldUseToolCalling(settingsList: settingsList)
    }

    static func shouldUseToolCalling(settingsList: [AppSettings]) -> Bool {
        settingsList.canonicalSettings?.chatbotToolCallingEnabled ?? false
    }

    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            chatBubble(message).id(message.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .padding(12)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.25))
                if input.isEmpty {
                    Text("Poser une question…")
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $input)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(minHeight: 36, maxHeight: 90)
            }

            Button(action: sendMessage) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Bubble

    @ViewBuilder
    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assistant").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                    MarkdownText(markdown: message.content)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 30)
            } else {
                Spacer(minLength: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vous").font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.85))
                    Text(message.content).foregroundColor(.white)
                }
                .padding(10)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Send

    private func sendMessage() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: question))
        input = ""
        isLoading = true
        errorMessage = nil

        Task {
            let historicalContext = await fetchHistoricalContext()
            let history = await MainActor.run { serializedConversationHistory(excludingLast: 1) }
            let prompt = makePrompt(question: question, historicalContext: historicalContext, history: history)

            do {
                let answer: String
                if useToolCalling {
                    answer = try await AIClient.sendWithToolLoop(
                        prompt: prompt,
                        settings: settings,
                        tools: ToolCatalog.all,
                        modelContext: context,
                        maxTurns: 5
                    )
                } else {
                    answer = try await AIClient.send(prompt: prompt, settings: settings)
                }
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: answer.trimmingCharacters(in: .whitespacesAndNewlines)))
                    errorMessage = nil
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    /// Construit le prompt monolithique : contexte historique RAG (optionnel), historique de
    /// conversation (limité, cf. `serializedConversationHistory`), puis la question.
    func makePrompt(question: String, historicalContext: String, history: String) -> String {
        """
        Tu es l'assistant d'analyse de l'application OneToOne, sollicité pendant la réunion « \(meeting.title) ».
        Réponds à partir du contexte ci-dessous. Si l'information manque, dis-le clairement.
        Sois concret et concis.
        \(historicalContext.isEmpty ? "" : "\nContexte historique (réunions passées pertinentes):\n\(historicalContext)\n")\(history.isEmpty ? "" : "\nConversation antérieure:\n\(history)\n")
        Question actuelle:
        \(question)
        """
    }

    /// Sérialise la conversation antérieure en blocs `Utilisateur:` / `Assistant:`, en ignorant
    /// le message de bienvenue et en coupant à `maxTurns` paires user/assistant.
    func serializedConversationHistory(excludingLast: Int = 0, maxTurns: Int = 5) -> String {
        let real = messages.dropFirst()
        let trimmed = excludingLast > 0 ? Array(real.dropLast(excludingLast)) : Array(real)
        let tail = trimmed.suffix(maxTurns * 2)
        return tail.map { msg in
            let role = msg.role == .user ? "Utilisateur" : "Assistant"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - RAG pre-fetch

    /// Réutilise le pattern de `MeetingView.fetchHistoricalContext` (privée, non modifiée) :
    /// scope selon le kind de la réunion, réunion courante exclue pour ne pas se nourrir
    /// d'elle-même. Fail-soft : erreur ou base vide → chaîne vide.
    private func fetchHistoricalContext() async -> String {
        var scope = RAGQuery.Scope()
        scope.excludeMeetingPID = meeting.persistentModelID

        switch meeting.kind {
        case .project:
            scope.projectPID = meeting.project?.persistentModelID
            guard scope.projectPID != nil else { return "" }
        case .oneToOne, .manager:
            scope.collaboratorPID = meeting.participants.first?.persistentModelID
            guard scope.collaboratorPID != nil else { return "" }
        case .global, .work, .note:
            return ""
        }

        let query = String(meeting.mergedTranscript.prefix(2000))
        guard !query.isEmpty else { return "" }

        do {
            let results = try await RAGQuery.search(query: query, topK: 5, scope: scope, context: context)
            guard !results.isEmpty else { return "" }
            let lines = results.enumerated().map { idx, r -> String in
                let date = r.chunk.meeting?.date.formatted(date: .abbreviated, time: .omitted) ?? "?"
                let title = r.chunk.meeting?.title ?? "réunion sans titre"
                return "[\(idx + 1)] \(date) — \(title): \(r.chunk.text)"
            }
            return lines.joined(separator: "\n\n")
        } catch {
            return ""
        }
    }
}
