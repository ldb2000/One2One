import SwiftUI
import SwiftData

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role {
        case user
        case assistant
    }
}

struct SlashCommandDef: Identifiable {
    let id = UUID()
    let name: String
    let args: [String]
    let help: String

    var displayName: String { name }
    var argsHint: String { args.joined(separator: " | ") }
    var fullTemplate: String {
        ([name] + args).joined(separator: " ")
    }
}

struct ChatbotView: View {
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query private var collaborators: [Collaborator]
    @Query private var interviews: [Interview]
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query private var settingsList: [AppSettings]

    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, content: "Je peux repondre a partir des projets, collaborateurs, entretiens, actions et alertes presents dans l'application.\n\nTapez / pour voir les commandes disponibles.")
    ]
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isOllamaReachable: Bool?
    @State private var selectedCommandIndex: Int = 0
    @State private var showSlashMenu = false
    @State private var pickedTemplate: PromptTemplate?
    @State private var showSavePromptSheet = false

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    private let slashCommands: [SlashCommandDef] = [
        SlashCommandDef(
            name: "/ajout-projet",
            args: ["<Nom du projet>", "| <votre information>"],
            help: "Ajouter une information datee a un projet"
        ),
        SlashCommandDef(
            name: "/ajout-info-collab-projet",
            args: ["<Nom du projet>", "| <Nom collaborateur>", "| <information>"],
            help: "Ajouter une information collaborateur sur un projet"
        ),
        SlashCommandDef(
            name: "/ajout-action-collab-projet",
            args: ["<Nom du projet>", "| <Nom collaborateur>", "| <action>"],
            help: "Ajouter une action collaborateur sur un projet"
        )
    ]

    /// True quand seul le message de bienvenue est présent (pas encore d'interaction).
    private var isInitialState: Bool {
        messages.count <= 1 && messages.first?.role == .assistant
    }

    private var filteredSlashCommands: [SlashCommandDef] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }

        // Only show menu when user is typing just the command prefix (no args yet)
        let firstSpace = trimmed.firstIndex(of: " ")
        let typedCommand = firstSpace != nil ? String(trimmed[..<firstSpace!]) : trimmed

        // If user already has a full command name + space, don't show menu
        if firstSpace != nil && slashCommands.contains(where: { $0.name.lowercased() == typedCommand.lowercased() }) {
            return []
        }

        if trimmed == "/" {
            return slashCommands
        }
        return slashCommands.filter { $0.name.localizedCaseInsensitiveContains(typedCommand) }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.95, blue: 0.93),
                    Color(red: 0.90, green: 0.92, blue: 0.90),
                    Color(red: 0.96, green: 0.93, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assistant IA")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                        Text("Interrogez la base de donnees de l'application en langage naturel.")
                            .foregroundColor(.black.opacity(0.65))
                        Text("Fournisseur actif: \(settings.provider.displayName)")
                            .font(.caption)
                            .foregroundColor(.black.opacity(0.55))
                    }
                    Spacer()
                    statusBadge
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(Color(red: 0.55, green: 0.08, blue: 0.08))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(red: 0.98, green: 0.90, blue: 0.89))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Group {
                    if isInitialState {
                        ChatbotTemplateGallery(
                            history: [],
                            onSelect: { tpl in pickedTemplate = tpl },
                            onPickHistory: { q in input = q }
                        )
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(messages) { message in
                                        chatBubble(message)
                                            .id(message.id)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .onChange(of: messages.count) { _, _ in
                                if let last = messages.last {
                                    withAnimation {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

                // Input area with overlay slash menu
                inputArea
            }
            .padding(24)
        }
        .navigationTitle("Assistant IA")
        .sheet(item: $pickedTemplate) { tpl in
            TemplateConfigSheet(template: tpl) { rendered in
                input = rendered
                sendMessage()
            }
        }
        .sheet(isPresented: $showSavePromptSheet) {
            SavePromptSheet(initialPrompt: input) { _ in }
        }
        .onChange(of: input) { _, _ in
            let shouldShow = !filteredSlashCommands.isEmpty
            if shouldShow != showSlashMenu {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSlashMenu = shouldShow
                }
            }
            if shouldShow {
                // Clamp selection
                let count = filteredSlashCommands.count
                if selectedCommandIndex >= count {
                    selectedCommandIndex = max(0, count - 1)
                }
            }
        }
    }

    // MARK: - Input Area with Slash Menu

    @ViewBuilder
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Slash command popup (above the input)
            if showSlashMenu {
                slashCommandMenu
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Current command hint
            if let hint = currentCommandHint {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue.opacity(0.7))
                    Text(hint)
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 8)
            }

            // Text input + send button
            HStack(alignment: .bottom, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(showSlashMenu ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.08), lineWidth: showSlashMenu ? 2 : 1)
                        )

                    if input.isEmpty {
                        Text("Posez une question ou tapez / pour les commandes...")
                            .foregroundColor(.black.opacity(0.35))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $input)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.black)
                        .font(.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 76, maxHeight: 120)
                        .background(Color.clear)
                }

                Button {
                    showSavePromptSheet = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .frame(width: 46, height: 46)
                .background(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                .help("Enregistrer ce prompt")
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: handleSendOrSelect) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(isLoading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.black)
                )
                .disabled(isLoading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .onKeyPress(.upArrow) {
            guard showSlashMenu else { return .ignored }
            withAnimation(.easeOut(duration: 0.1)) {
                selectedCommandIndex = max(0, selectedCommandIndex - 1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard showSlashMenu else { return .ignored }
            let count = filteredSlashCommands.count
            withAnimation(.easeOut(duration: 0.1)) {
                selectedCommandIndex = min(count - 1, selectedCommandIndex + 1)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if showSlashMenu {
                selectCommand(at: selectedCommandIndex)
                return .handled
            }
            // Shift+Return = newline (handled by TextEditor), plain Return = send
            return .ignored
        }
        .onKeyPress(.tab) {
            if showSlashMenu {
                selectCommand(at: selectedCommandIndex)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if showSlashMenu {
                showSlashMenu = false
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Slash Command Menu

    @ViewBuilder
    private var slashCommandMenu: some View {
        let commands = filteredSlashCommands

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Commandes")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.black.opacity(0.45))
                    .textCase(.uppercase)
                Spacer()
                Text("\u{2191}\u{2193} naviguer  \u{21A9} selectionner  esc fermer")
                    .font(.caption2)
                    .foregroundColor(.black.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                Button(action: {
                    selectCommand(at: index)
                }) {
                    HStack(spacing: 10) {
                        Text(cmd.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(index == selectedCommandIndex ? .white : .accentColor)

                        Text(cmd.argsHint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(index == selectedCommandIndex ? .white.opacity(0.7) : .black.opacity(0.4))

                        Spacer()

                        Text(cmd.help)
                            .font(.caption)
                            .foregroundColor(index == selectedCommandIndex ? .white.opacity(0.8) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(index == selectedCommandIndex ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        selectedCommandIndex = index
                    }
                }
            }
        }
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .padding(.bottom, 8)
    }

    // MARK: - Command Hint (shows expected args after selecting a command)

    private var currentCommandHint: String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Find matching command
        guard let cmd = slashCommands.first(where: { trimmed.lowercased().hasPrefix($0.name.lowercased()) }) else {
            return nil
        }

        let afterCommand = trimmed.dropFirst(cmd.name.count).trimmingCharacters(in: .whitespaces)

        // Don't show hint if menu is visible
        guard !showSlashMenu else { return nil }

        let pipeParts = afterCommand.components(separatedBy: "|")
        let filledArgs = pipeParts.count

        // Show which arg is expected next
        let argNames = cmd.args.map { $0.replacingOccurrences(of: "| ", with: "").trimmingCharacters(in: .whitespaces) }

        if afterCommand.isEmpty {
            return "Arguments attendus: \(argNames.joined(separator: " | "))"
        }

        if filledArgs < argNames.count {
            let remaining = argNames[filledArgs...]
            return "Prochain: \(remaining.joined(separator: " | "))"
        }

        return nil
    }

    private func selectCommand(at index: Int) {
        let commands = filteredSlashCommands
        guard index >= 0, index < commands.count else { return }

        let cmd = commands[index]
        input = cmd.name + " "
        showSlashMenu = false
        selectedCommandIndex = 0
    }

    private func handleSendOrSelect() {
        if showSlashMenu {
            selectCommand(at: selectedCommandIndex)
        } else {
            sendMessage()
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLoading ? Color.orange : Color.green)
                .frame(width: 10, height: 10)
            Text(isLoading ? "Analyse..." : "Pret")
                .font(.caption.weight(.semibold))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.88))
        .clipShape(Capsule())
    }

    // MARK: - Chat Bubble

    @ViewBuilder
    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assistant")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.black.opacity(0.55))
                    MarkdownText(markdown: message.content)
                        .foregroundColor(.black)
                }
                .padding(14)
                .background(Color(red: 0.985, green: 0.985, blue: 0.975))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                Spacer(minLength: 50)
            } else {
                Spacer(minLength: 50)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vous")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(message.content)
                        .foregroundColor(.white)
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: question))
        input = ""
        isLoading = true
        errorMessage = nil

        if let localResponse = handleLocalCommand(question) {
            messages.append(ChatMessage(role: .assistant, content: localResponse))
            isLoading = false
            return
        }

        if let localResponse = localSearchResponse(for: question) {
            messages.append(ChatMessage(role: .assistant, content: localResponse))
            isLoading = false
            return
        }

        if settings.provider == .ollama, isOllamaReachable == false {
            messages.append(ChatMessage(role: .assistant, content: offlineFallbackResponse(for: question)))
            errorMessage = "Ollama n'est pas disponible. Reponse locale affichee a la place."
            isLoading = false
            return
        }

        let databaseContext = buildDatabaseContext()
        let history = serializedConversationHistory(excludingLast: 1)
        let prompt = """
        Tu es l'assistant d'analyse de l'application OneToOne.
        Reponds uniquement a partir des donnees ci-dessous (incluant les rapports de réunion déjà générés). Si l'information manque, dis-le clairement.
        Sois concret, structure et oriente pilotage. Tiens compte de la conversation antérieure.

        Base de donnees:
        \(databaseContext)
        \(history.isEmpty ? "" : "\nConversation antérieure:\n\(history)\n")
        Question actuelle:
        \(question)
        """

        Task {
            do {
                if settings.provider == .ollama {
                    let reachable = await checkOllamaReachability()
                    await MainActor.run {
                        isOllamaReachable = reachable
                    }
                    if !reachable {
                        await MainActor.run {
                            messages.append(ChatMessage(role: .assistant, content: offlineFallbackResponse(for: question)))
                            errorMessage = "Ollama n'est pas joignable sur \(settings.apiEndpoint). Reponse locale affichee."
                            isLoading = false
                        }
                        return
                    }
                }

                let answer = try await AIClient.send(prompt: prompt, settings: settings)
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

    // MARK: - Database Context

    private func buildDatabaseContext() -> String {
        let projectLines = projects.sorted(by: { $0.name < $1.name }).map { project in
            let pendingTasks = project.tasks.filter { !$0.isCompleted }.count
            let pendingAlerts = project.alerts.filter { !$0.isResolved }.count
            return "- Projet \(project.code): \(project.name), type \(project.projectType), sponsor \(project.sponsor.isEmpty ? "Non renseigne" : project.sponsor), statut \(project.status), phase \(project.phase), jours \(project.plannedDays?.formatted() ?? "n/a"), deadline design \(project.designEndDeadline?.formatted(date: .abbreviated, time: .omitted) ?? "n/a"), actions \(pendingTasks), alertes \(pendingAlerts)"
        }

        let collaboratorLines = collaborators.sorted(by: { $0.name < $1.name }).map { collaborator in
            let interviewCount = collaborator.interviews.count
            return "- Collaborateur: \(collaborator.name), role \(collaborator.role), entretiens \(interviewCount)"
        }

        let interviewLines = interviews.sorted(by: { $0.date > $1.date }).prefix(25).map { interview in
            let linkedProject = interview.selectedProject?.name ?? "Aucun"
            return "- Entretien \(interview.type.label) du \(interview.date.formatted(date: .abbreviated, time: .omitted)) avec \(interview.collaborator?.name ?? "Inconnu"), projet \(linkedProject), actions \(interview.tasks.filter { !$0.isCompleted }.count), alertes \(interview.alerts.filter { !$0.isResolved }.count)"
        }

        // Rapports de réunion AI (last 15 with non-empty summary)
        let reported = meetings.filter { !$0.summary.isEmpty }.prefix(15)
        let meetingReportLines: [String] = reported.map { m in
            let participants = m.participants.map(\.name).joined(separator: ", ")
            var block = """
            - Réunion "\(m.title)" du \(m.date.formatted(date: .abbreviated, time: .shortened)) [\(m.kind.label)] · participants: \(participants.isEmpty ? "—" : participants)
              Résumé: \(m.summary)
            """
            if !m.keyPoints.isEmpty {
                block += "\n  Points clés: " + m.keyPoints.joined(separator: " | ")
            }
            if !m.decisions.isEmpty {
                block += "\n  Décisions: " + m.decisions.joined(separator: " | ")
            }
            if !m.openQuestions.isEmpty {
                block += "\n  Questions ouvertes: " + m.openQuestions.joined(separator: " | ")
            }
            return block
        }

        return """
        Projets:
        \(projectLines.joined(separator: "\n"))

        Collaborateurs:
        \(collaboratorLines.joined(separator: "\n"))

        Entretiens recents:
        \(interviewLines.joined(separator: "\n"))

        Rapports de réunion (générés par IA):
        \(meetingReportLines.isEmpty ? "(aucun rapport disponible)" : meetingReportLines.joined(separator: "\n"))
        """
    }

    /// Sérialise la conversation antérieure en blocs `Utilisateur:` / `Assistant:`
    /// pour la passer dans le prompt monolithique. Ignore le message de bienvenue.
    /// Coupe à `maxTurns` paires user/assistant pour limiter la taille.
    private func serializedConversationHistory(excludingLast: Int = 0, maxTurns: Int = 6) -> String {
        let real = messages.dropFirst()  // skip welcome message
        let trimmed = excludingLast > 0 ? Array(real.dropLast(excludingLast)) : Array(real)
        let tail = trimmed.suffix(maxTurns * 2)
        return tail.map { msg in
            let role = msg.role == .user ? "Utilisateur" : "Assistant"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Offline Fallback

    private func offlineFallbackResponse(for question: String) -> String {
        if let localResponse = localSearchResponse(for: question) {
            return localResponse
        }

        return """
        Le fournisseur IA configure ne repond pas actuellement. Je peux quand meme traiter localement:
        - `liste des projets`
        - `liste des collaborateurs`
        - `/ajout-projet Nom du projet | information`
        - `/ajout-info-collab-projet Nom du projet | Nom collaborateur | information`
        - `/ajout-action-collab-projet Nom du projet | Nom collaborateur | action`
        """
    }

    // MARK: - Ollama Check

    private func checkOllamaReachability() async -> Bool {
        var baseURL = settings.apiEndpoint
        if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
            baseURL = String(baseURL.dropLast(baseURL.hasSuffix("/") ? 4 : 3))
        }

        guard let url = URL(string: baseURL + "/api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Local Command Handling

    private func handleLocalCommand(_ question: String) -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        if let response = handleProjectInfoCommand(trimmed) {
            return response
        }
        if let response = handleCollaboratorProjectCommand(trimmed, commandPrefix: "/ajout-info-collab-projet", kind: "Information collaborateur") {
            return response
        }
        if let response = handleCollaboratorProjectCommand(trimmed, commandPrefix: "/ajout-action-collab-projet", kind: "Action collaborateur") {
            return response
        }

        // Unknown slash command
        if trimmed.hasPrefix("/") && !trimmed.contains(" ") {
            return "Commande inconnue: \(trimmed)\n\nCommandes disponibles:\n- /ajout-projet <Nom du projet> | <information>\n- /ajout-info-collab-projet <Nom du projet> | <Nom collaborateur> | <information>\n- /ajout-action-collab-projet <Nom du projet> | <Nom collaborateur> | <action>"
        }

        return nil
    }

    private func handleProjectInfoCommand(_ question: String) -> String? {
        let lowered = question.lowercased()
        guard lowered.hasPrefix("/ajout-projet") else { return nil }

        // Extract payload after command name
        let commandName = "/ajout-projet"
        guard question.count > commandName.count else {
            return "Usage: /ajout-projet <Nom du projet> | <votre information>"
        }

        let payload = String(question.dropFirst(commandName.count)).trimmingCharacters(in: .whitespaces)
        let parts = payload.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return "Usage: /ajout-projet <Nom du projet> | <votre information>"
        }

        let projectName = parts[0]
        let content = parts[1]
        guard let project = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(projectName) == .orderedSame }) else {
            let suggestions = projects.filter { $0.name.lowercased().contains(projectName.lowercased()) }.prefix(3)
            let hint = suggestions.isEmpty ? "" : "\nProjets similaires: " + suggestions.map(\.name).joined(separator: ", ")
            return "Projet introuvable: \(projectName)\(hint)"
        }

        let category = project.phase == "Build" ? "REX" : "Information"
        let entry = ProjectInfoEntry(date: Date(), content: content, category: category)
        entry.project = project
        context.insert(entry)

        do {
            try context.save()
            SpotlightIndexService.shared.index(project: project)
            return "Information ajoutee au projet \(project.name) [\(category)] avec la date du jour."
        } catch {
            return "Impossible d'ajouter l'information: \(error.localizedDescription)"
        }
    }

    private func handleCollaboratorProjectCommand(_ question: String, commandPrefix: String, kind: String) -> String? {
        let lowered = question.lowercased()
        guard lowered.hasPrefix(commandPrefix.lowercased()) else { return nil }

        guard question.count > commandPrefix.count else {
            return "Usage: \(commandPrefix) <Nom du projet> | <Nom collaborateur> | <contenu>"
        }

        let payload = String(question.dropFirst(commandPrefix.count)).trimmingCharacters(in: .whitespaces)
        let parts = payload.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 3, !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else {
            return "Usage: \(commandPrefix) <Nom du projet> | <Nom collaborateur> | <contenu>"
        }

        let projectName = parts[0]
        let collaboratorName = parts[1]
        let content = parts[2]

        guard let project = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(projectName) == .orderedSame }) else {
            let suggestions = projects.filter { $0.name.lowercased().contains(projectName.lowercased()) }.prefix(3)
            let hint = suggestions.isEmpty ? "" : "\nProjets similaires: " + suggestions.map(\.name).joined(separator: ", ")
            return "Projet introuvable: \(projectName)\(hint)"
        }
        guard let collaborator = collaborators.first(where: { $0.name.localizedCaseInsensitiveCompare(collaboratorName) == .orderedSame }) else {
            let suggestions = collaborators.filter { $0.name.lowercased().contains(collaboratorName.lowercased()) }.prefix(3)
            let hint = suggestions.isEmpty ? "" : "\nCollaborateurs similaires: " + suggestions.map(\.name).joined(separator: ", ")
            return "Collaborateur introuvable: \(collaboratorName)\(hint)"
        }

        let entry = ProjectCollaboratorEntry(date: Date(), content: content, kind: kind, isCompleted: false)
        entry.project = project
        entry.collaborator = collaborator
        context.insert(entry)

        do {
            try context.save()
            SpotlightIndexService.shared.index(project: project)
            return "\(kind) ajoutee pour \(collaborator.name) sur le projet \(project.name)."
        } catch {
            return "Impossible d'ajouter l'entree: \(error.localizedDescription)"
        }
    }

    // MARK: - Local Search

    private func localSearchResponse(for question: String) -> String? {
        let normalizedQuestion = question.lowercased()

        if normalizedQuestion.contains("actions en cours") || normalizedQuestion.contains("liste des actions") || normalizedQuestion == "actions" {
            let pendingTasks = projects
                .flatMap { project in project.tasks.filter { !$0.isCompleted }.map { (project, $0) } }
                .sorted { $0.0.name < $1.0.name }

            guard !pendingTasks.isEmpty else {
                return "Aucune action en cours."
            }

            let lines = pendingTasks.map { project, task in
                "- \(project.name): \(task.title)"
            }
            return "Actions en cours:\n" + lines.joined(separator: "\n")
        }

        if normalizedQuestion.contains("alertes") {
            let activeAlerts = projects
                .flatMap { project in project.alerts.filter { !$0.isResolved }.map { (project, $0) } }
                .sorted { $0.0.name < $1.0.name }

            guard !activeAlerts.isEmpty else {
                return "Aucune alerte active."
            }

            let lines = activeAlerts.map { project, alert in
                "- \(project.name): [\(alert.severity)] \(alert.title)"
            }
            return "Alertes actives:\n" + lines.joined(separator: "\n")
        }

        if normalizedQuestion.contains("liste des projets") || normalizedQuestion.contains("liste projets") || normalizedQuestion == "projets" || normalizedQuestion == "liste projet" {
            let activeProjects = projects
                .filter { !$0.isArchived }
                .sorted(by: { $0.name < $1.name })

            guard !activeProjects.isEmpty else {
                return "Aucun projet actif dans la base."
            }

            let lines = activeProjects.map { project in
                let entity = project.entity?.name ?? "Sans entite"
                return "- \(project.name) (\(project.code)) | \(entity) | \(project.phase) | \(project.status)"
            }
            return "Projets actifs:\n" + lines.joined(separator: "\n")
        }

        if normalizedQuestion.contains("liste des collaborateurs") || normalizedQuestion.contains("collaborateurs") {
            let activeCollaborators = collaborators
                .filter { !$0.isArchived }
                .sorted(by: { $0.name < $1.name })

            guard !activeCollaborators.isEmpty else {
                return "Aucun collaborateur actif dans la base."
            }

            let lines = activeCollaborators.map { collaborator in
                "- \(collaborator.name) | \(collaborator.role)"
            }
            return "Collaborateurs actifs:\n" + lines.joined(separator: "\n")
        }

        if let entityResponse = responseForEntityQuery(normalizedQuestion) {
            return entityResponse
        }

        if let phaseResponse = responseForPhaseQuery(normalizedQuestion) {
            return phaseResponse
        }

        if let sponsorResponse = responseForSponsorQuery(normalizedQuestion) {
            return sponsorResponse
        }

        if let rexResponse = responseForRexQuery(normalizedQuestion) {
            return rexResponse
        }

        if let collaboratorProjectResponse = responseForCollaboratorProjectQuery(normalizedQuestion) {
            return collaboratorProjectResponse
        }

        guard normalizedQuestion.contains("projet") || normalizedQuestion.contains("information") || normalizedQuestion.contains("rex") else {
            return nil
        }

        let matchingProjects = projects.filter { project in
            normalizedQuestion.contains(project.name.lowercased()) || normalizedQuestion.contains(project.code.lowercased())
        }

        guard !matchingProjects.isEmpty else { return nil }

        let lines = matchingProjects.map { project in
            let entries = project.infoEntries.sorted(by: { $0.date > $1.date }).prefix(5)
            let details = entries.isEmpty
                ? "Aucune information datee."
                : entries.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)) [\($0.category)] \($0.content)" }.joined(separator: "\n")
            return "Projet \(project.name):\n\(details)"
        }

        return lines.joined(separator: "\n\n")
    }

    private func responseForEntityQuery(_ normalizedQuestion: String) -> String? {
        let entitiesByName = projects.compactMap(\.entity).reduce(into: [String: Entity]()) { result, entity in
            result[entity.name.lowercased()] = entity
        }
        for projectEntity in entitiesByName.values {
            if normalizedQuestion.contains(projectEntity.name.lowercased()) {
                let entityProjects = projectEntity.projects.filter { !$0.isArchived }.sorted(by: { $0.name < $1.name })
                let lines = entityProjects.map { "- \($0.name) (\($0.phase), \($0.status))" }
                return lines.isEmpty ? "Aucun projet actif pour l'entite \(projectEntity.name)." : "Projets de l'entite \(projectEntity.name):\n" + lines.joined(separator: "\n")
            }
        }
        return nil
    }

    private func responseForPhaseQuery(_ normalizedQuestion: String) -> String? {
        let phases = ["cadrage": "Cadrage", "design": "Design", "build": "Build", "run": "Run"]
        for (needle, phase) in phases where normalizedQuestion.contains(needle) {
            let phaseProjects = projects.filter { !$0.isArchived && $0.phase == phase }.sorted(by: { $0.name < $1.name })
            let lines = phaseProjects.map { "- \($0.name) (\($0.status))" }
            return lines.isEmpty ? "Aucun projet en phase \(phase)." : "Projets en phase \(phase):\n" + lines.joined(separator: "\n")
        }
        return nil
    }

    private func responseForSponsorQuery(_ normalizedQuestion: String) -> String? {
        let matchingProjects = projects.filter { !$0.sponsor.isEmpty && normalizedQuestion.contains($0.sponsor.lowercased()) }
        guard !matchingProjects.isEmpty else { return nil }
        let lines = matchingProjects.sorted(by: { $0.name < $1.name }).map {
            "- \($0.name) (\($0.code)) | \($0.phase) | \($0.status)"
        }
        return "Projets pour ce sponsor:\n" + lines.joined(separator: "\n")
    }

    private func responseForRexQuery(_ normalizedQuestion: String) -> String? {
        guard normalizedQuestion.contains("rex") || normalizedQuestion.contains("retour d'experience") else { return nil }
        let matchingProjects = projects.filter { project in
            normalizedQuestion.contains(project.name.lowercased()) || normalizedQuestion.contains(project.code.lowercased()) || normalizedQuestion == "rex"
        }
        let sourceProjects = matchingProjects.isEmpty ? projects.filter { !$0.infoEntries.filter { $0.category == "REX" }.isEmpty } : matchingProjects
        guard !sourceProjects.isEmpty else { return "Aucun REX projet trouve." }

        let sections = sourceProjects.sorted(by: { $0.name < $1.name }).map { project in
            let entries = project.infoEntries.filter { $0.category == "REX" }.sorted(by: { $0.date > $1.date }).prefix(5)
            let lines = entries.map { "- \($0.date.formatted(date: .abbreviated, time: .omitted)): \($0.content)" }
            return "Projet \(project.name):\n" + (lines.isEmpty ? "- Aucun REX date" : lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private func responseForCollaboratorProjectQuery(_ normalizedQuestion: String) -> String? {
        let matchingProjects = projects.filter { project in
            normalizedQuestion.contains(project.name.lowercased()) || normalizedQuestion.contains(project.code.lowercased())
        }
        let matchingCollaborators = collaborators.filter { collaborator in
            normalizedQuestion.contains(collaborator.name.lowercased())
        }

        let entries = projects.flatMap { project in
            project.collaboratorEntries.filter { entry in
                let projectMatch = matchingProjects.isEmpty || matchingProjects.contains(where: { $0.persistentModelID == project.persistentModelID })
                let collaboratorMatch = matchingCollaborators.isEmpty || matchingCollaborators.contains(where: { $0.persistentModelID == entry.collaborator?.persistentModelID })
                return projectMatch && collaboratorMatch
            }.map { (project, $0) }
        }

        guard !entries.isEmpty else { return nil }

        let lines = entries.sorted { lhs, rhs in
            if lhs.0.name == rhs.0.name {
                return lhs.1.date > rhs.1.date
            }
            return lhs.0.name < rhs.0.name
        }.map { project, entry in
            let collaboratorName = entry.collaborator?.name ?? "Collaborateur"
            let statusSuffix = entry.kind.contains("Action") ? (entry.isCompleted ? " [terminee]" : " [en cours]") : ""
            return "- \(project.name) | \(collaboratorName) | \(entry.kind)\(statusSuffix) | \(entry.content)"
        }

        return "Entrees collaborateurs par projet:\n" + lines.joined(separator: "\n")
    }
}
