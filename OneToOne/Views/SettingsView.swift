import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settingsList: [AppSettings]
    @Query private var entities: [Entity]
    @Query private var projects: [Project]
    @Query private var collaborators: [Collaborator]
    @Query private var interviews: [Interview]
    @Query private var meetings: [Meeting]
    @Environment(\.modelContext) private var context

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

    @State private var cloudToken: String = ""
    @State private var oauthToken: String = ""
    @State private var apiEndpoint: String = ""
    @State private var modelName: String = ""
    @State private var selectedProvider: AIProvider = .claudeOAuth
    @State private var importPrompt: String = ""
    @State private var reformulatePrompt: String = ""
    @State private var weeklyExportPrompt: String = ""
    @State private var selectedTab = 0
    @State private var oauthStatus: String = ""
    @State private var geminiStatus: String = ""
    @State private var ollamaModels: [String] = []
    @State private var ollamaStatus: String = ""
    @State private var isLoadingOllamaModels = false
    @State private var backupStatus: String = ""
    @State private var testStatus: String = ""
    @State private var isTesting = false
    @State private var spotlightStatus: String = ""
    @State private var isReindexing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    Form {
                        SettingsHotkeysSection()
                    }
                }

                // IA Config
                GroupBox("Configuration IA") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Fournisseur IA", selection: $selectedProvider) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .onChange(of: selectedProvider) { _, newProvider in
                            updateDefaults(for: newProvider)
                            if newProvider == .ollama {
                                fetchOllamaModels()
                            }
                        }

                        if selectedProvider == .claudeOAuth {
                            // Claude CLI with setup-token
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Utilise le CLI `claude` avec votre abonnement Claude Pro/Max (gratuit, pas de cle API).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    Text("1.")
                                    Text("Installez Claude Code :")
                                        .foregroundColor(.secondary)
                                    Text("npm i -g @anthropic-ai/claude-code")
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.7))
                                        .cornerRadius(4)
                                }
                                .font(.caption)

                                HStack {
                                    Text("2.")
                                    Text("Authentifiez-vous :")
                                        .foregroundColor(.secondary)
                                    Text("claude setup-token")
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.7))
                                        .cornerRadius(4)
                                }
                                .font(.caption)

                                if !oauthStatus.isEmpty {
                                    Text(oauthStatus)
                                        .font(.caption)
                                        .foregroundColor(oauthStatus.contains("OK") ? .green : .orange)
                                }

                                LabeledContent("Modele") {
                                    EditableTextField(placeholder: "claude-sonnet-4-5", text: $modelName)
                                        .frame(height: 24)
                                }
                            }
                        } else if selectedProvider == .geminiOAuth {
                            // Gemini OAuth flow
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Utilise les credentials OAuth de Gemini CLI (gratuit avec compte Google).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    Text("1.")
                                    Text("Installez Gemini CLI :")
                                        .foregroundColor(.secondary)
                                    Text("`npm i -g @google/gemini-cli`")
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(4)
                                }
                                .font(.caption)

                                HStack {
                                    Text("2.")
                                    Text("Lancez `gemini` et connectez-vous avec Google.")
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)

                                Button("Importer depuis ~/.gemini/oauth_creds.json") {
                                    if let creds = GeminiOAuthClient.shared.storage.importFromGeminiCLI() {
                                        GeminiOAuthClient.shared.storage.save(creds)
                                        geminiStatus = "Credentials importées — OK"
                                    } else {
                                        geminiStatus = "Fichier non trouvé. Lancez `gemini` d'abord."
                                    }
                                }
                                .buttonStyle(.bordered)

                                if !geminiStatus.isEmpty {
                                    Text(geminiStatus)
                                        .font(.caption)
                                        .foregroundColor(geminiStatus.contains("OK") ? .green : .orange)
                                }

                                LabeledContent("Modèle") {
                                    EditableTextField(placeholder: "gemini-2.5-pro", text: $modelName)
                                        .frame(height: 24)
                                }
                            }
                        } else if selectedProvider == .ollama {
                            // Ollama local flow
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ollama tourne en local. Pas de clé API nécessaire.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                LabeledContent("Endpoint") {
                                    EditableTextField(placeholder: "http://localhost:11434/v1", text: $apiEndpoint)
                                        .frame(height: 24)
                                }

                                HStack {
                                    if !ollamaModels.isEmpty {
                                        Picker("Modèle", selection: $modelName) {
                                            ForEach(ollamaModels, id: \.self) { model in
                                                Text(model).tag(model)
                                            }
                                        }
                                    } else {
                                        LabeledContent("Modèle") {
                                            EditableTextField(placeholder: "llama3", text: $modelName)
                                                .frame(height: 24)
                                        }
                                    }

                                    Button(action: fetchOllamaModels) {
                                        if isLoadingOllamaModels {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Label("Lister", systemImage: "arrow.clockwise")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isLoadingOllamaModels)
                                }

                                if !ollamaStatus.isEmpty {
                                    Text(ollamaStatus)
                                        .font(.caption)
                                        .foregroundColor(ollamaStatus.contains("modèle") ? .green : .orange)
                                }
                            }
                        } else {
                            // Standard API Key flow (OpenAI, Gemini API Key, Anthropic API Key)
                            LabeledContent("Clé API") {
                                EditableTextField(placeholder: "Token / API Key", text: $cloudToken)
                                    .frame(height: 24)
                            }

                            LabeledContent("Endpoint API") {
                                EditableTextField(placeholder: "Endpoint API", text: $apiEndpoint)
                                    .frame(height: 24)
                            }

                            LabeledContent("Modèle") {
                                EditableTextField(placeholder: "Modèle", text: $modelName)
                                    .frame(height: 24)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }

                // Test button
                GroupBox("Test de connexion") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Testez la configuration IA avant de sauvegarder.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button(action: testAIConnection) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Tester la connexion", systemImage: "network")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting)

                            if !testStatus.isEmpty {
                                Image(systemName: testStatus.contains("OK") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(testStatus.contains("OK") ? .green : .red)
                                Text(testStatus)
                                    .font(.caption)
                                    .foregroundColor(testStatus.contains("OK") ? .green : .red)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }

                // AI feature toggles
                GroupBox("Fonctionnalites IA") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choisissez quelles fonctionnalites utilisent l'IA. Les autres restent en traitement local.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle(isOn: Binding(
                            get: { settings.useAIForImport },
                            set: { settings.useAIForImport = $0; try? context.save() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import de fichiers (PPTX, XLS, PDF)")
                                Text("Extraction intelligente des projets, collaborateurs et risques")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { settings.useAIForReformulation },
                            set: { settings.useAIForReformulation = $0; try? context.save() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reformulation des notes / Analyse CV")
                                Text("Reformulation IA, extraction des actions, pre-remplissage entretien")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { settings.useAIForWeeklyExport },
                            set: { settings.useAIForWeeklyExport = $0; try? context.save() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export hebdomadaire")
                                Text("Rapport hebdo genere par IA a partir des entretiens")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }

                // Prompts configurables
                GroupBox("Prompts IA") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Personnalisez les prompts utilisés par l'IA. Variables disponibles : {{fileName}}, {{notes}}, {{interviews}}")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Prompt", selection: $selectedTab) {
                            Text("Import").tag(0)
                            Text("Reformulation").tag(1)
                            Text("Export Hebdo").tag(2)
                        }
                        .pickerStyle(.segmented)

                        Group {
                            switch selectedTab {
                            case 0:
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Prompt d'import").font(.caption.bold())
                                        Spacer()
                                        Button("Réinitialiser") {
                                            importPrompt = AppSettings.defaultImportPrompt
                                        }
                                        .font(.caption)
                                    }
                                    EditableTextEditor(text: $importPrompt)
                                        .frame(minHeight: 150)
                                }
                            case 1:
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Prompt de reformulation").font(.caption.bold())
                                        Spacer()
                                        Button("Réinitialiser") {
                                            reformulatePrompt = AppSettings.defaultReformulatePrompt
                                        }
                                        .font(.caption)
                                    }
                                    EditableTextEditor(text: $reformulatePrompt)
                                        .frame(minHeight: 150)
                                }
                            default:
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Prompt d'export hebdo").font(.caption.bold())
                                        Spacer()
                                        Button("Réinitialiser") {
                                            weeklyExportPrompt = AppSettings.defaultWeeklyExportPrompt
                                        }
                                        .font(.caption)
                                    }
                                    EditableTextEditor(text: $weeklyExportPrompt)
                                        .frame(minHeight: 150)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }

                GroupBox("Entités") {
                    VStack(alignment: .leading, spacing: 10) {
                        if entities.isEmpty {
                            Text("Aucune entité configurée")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(entities.sorted(by: { $0.name < $1.name })) { entity in
                                HStack(alignment: .top) {
                                    NavigationLink {
                                        EntityDetailView(entity: entity)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entity.name)
                                            Text("\(entity.projects.count) projet(s)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button("Ajouter projet") {
                                        addProject(to: entity)
                                    }
                                    .font(.caption)

                                    Button(role: .destructive) {
                                        deleteEntity(entity)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button(action: addEntity) {
                            Label("Ajouter une entité", systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                }

                GroupBox("Backup / Restore") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sauvegardez ou restaurez les données de l'application au format JSON.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Créer un backup") {
                                createBackup()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Restaurer un backup") {
                                restoreBackup()
                            }
                            .buttonStyle(.bordered)
                        }

                        if !backupStatus.isEmpty {
                            Text(backupStatus)
                                .font(.caption)
                                .foregroundColor(backupStatus.contains("OK") ? .green : .orange)
                        }
                    }
                    .padding(.vertical, 5)
                }

                GroupBox("Recherche Spotlight") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Réindexez les projets, entretiens et réunions dans Spotlight pour la recherche macOS.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button(action: reindexSpotlight) {
                                Label("Réindexer Spotlight", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isReindexing)

                            if isReindexing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if !spotlightStatus.isEmpty {
                            Text(spotlightStatus)
                                .font(.caption)
                                .foregroundColor(spotlightStatus.contains("OK") ? .green : .orange)
                        }
                    }
                    .padding(.vertical, 5)
                }

                Button("Sauvegarder les paramètres") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)

                GroupBox("À propos") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Version 1.0.0")
                        Text("Outil de gestion OneToOne & Projets STTi")
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding()
        }
        .onAppear {
            ensureSingleSettingsRecord()
            cloudToken = settings.cloudToken
            apiEndpoint = settings.apiEndpoint
            modelName = settings.modelName
            selectedProvider = settings.provider
            importPrompt = settings.importPrompt
            reformulatePrompt = settings.reformulatePrompt
            weeklyExportPrompt = settings.weeklyExportPrompt

            // Check if claude CLI is available for the setup-token provider
            if selectedProvider == .claudeOAuth {
                checkClaudeCLI()
            }
        }
        .warmBackground()
        .navigationTitle("Paramètres")
    }

    private func fetchOllamaModels() {
        isLoadingOllamaModels = true
        ollamaStatus = ""

        // Derive base URL from the endpoint (strip /v1 suffix)
        var baseURL = apiEndpoint
        if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
            baseURL = String(baseURL.dropLast(baseURL.hasSuffix("/") ? 4 : 3))
        }
        let tagsURL = baseURL + "/api/tags"

        Task {
            do {
                guard let url = URL(string: tagsURL) else {
                    await MainActor.run {
                        ollamaStatus = "URL invalide: \(tagsURL)"
                        isLoadingOllamaModels = false
                    }
                    return
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 5

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        ollamaStatus = "Ollama ne répond pas. Est-il lancé ?"
                        isLoadingOllamaModels = false
                    }
                    return
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let models = json?["models"] as? [[String: Any]] else {
                    await MainActor.run {
                        ollamaStatus = "Réponse inattendue"
                        isLoadingOllamaModels = false
                    }
                    return
                }

                let names = models.compactMap { $0["name"] as? String }.sorted()

                await MainActor.run {
                    ollamaModels = names
                    if !names.isEmpty {
                        ollamaStatus = "\(names.count) modèle(s) trouvé(s)"
                        if !names.contains(modelName) {
                            modelName = names.first ?? "llama3"
                        }
                    } else {
                        ollamaStatus = "Aucun modèle installé. Lancez `ollama pull llama3`"
                    }
                    isLoadingOllamaModels = false
                }
            } catch {
                await MainActor.run {
                    ollamaStatus = "Erreur: \(error.localizedDescription)"
                    isLoadingOllamaModels = false
                }
            }
        }
    }

    private func checkClaudeCLI() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", "which claude"]
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                if process.terminationStatus == 0 && !output.isEmpty {
                    oauthStatus = "CLI claude trouve: \(output) — OK"
                } else {
                    oauthStatus = "CLI claude non trouve. Installez: npm i -g @anthropic-ai/claude-code"
                }
            }
        }
    }

    private func testAIConnection() {
        isTesting = true
        testStatus = ""

        // Save settings first so the test uses the latest values
        saveSettings()

        // Build temporary settings from current form state
        let testSettings = AppSettings()
        testSettings.provider = selectedProvider
        testSettings.cloudToken = cloudToken
        testSettings.apiEndpoint = apiEndpoint
        testSettings.modelName = modelName

        Task {
            do {
                let response = try await AIClient.send(
                    prompt: "Reponds uniquement par: OK",
                    settings: testSettings
                )
                await MainActor.run {
                    testStatus = "OK — Reponse: \(response.prefix(80).trimmingCharacters(in: .whitespacesAndNewlines))"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testStatus = "Echec: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    private func updateDefaults(for provider: AIProvider) {
        switch provider {
        case .claudeOAuth:
            apiEndpoint = "https://api.anthropic.com/v1"
            modelName = "claude-sonnet-4-5"
        case .geminiOAuth:
            apiEndpoint = "https://generativelanguage.googleapis.com/v1beta"
            modelName = "gemini-2.5-pro"
        case .anthropic:
            apiEndpoint = "https://api.anthropic.com/v1"
            modelName = "claude-sonnet-4-5"
        case .openai:
            apiEndpoint = "https://api.openai.com/v1"
            modelName = "gpt-4o"
        case .ollama:
            apiEndpoint = "http://localhost:11434/v1"
            modelName = "llama3"
        case .gemini:
            apiEndpoint = "https://generativelanguage.googleapis.com/v1beta"
            modelName = "gemini-1.5-pro"
        }
    }

    private func saveSettings() {

        settings.cloudToken = cloudToken
        settings.apiEndpoint = apiEndpoint
        settings.modelName = modelName
        settings.provider = selectedProvider
        settings.importPrompt = importPrompt
        settings.reformulatePrompt = reformulatePrompt
        settings.weeklyExportPrompt = weeklyExportPrompt
        do {
            try context.save()
            backupStatus = ""
            oauthStatus = oauthStatus.isEmpty ? "Paramètres IA sauvegardés — OK" : oauthStatus
        } catch {
            oauthStatus = "Échec de sauvegarde: \(error.localizedDescription)"
        }
    }

    private func addEntity() {
        let entity = Entity(name: "Nouvelle Entité")
        context.insert(entity)
        try? context.save()
    }

    private func deleteEntity(_ entity: Entity) {
        context.delete(entity)
        try? context.save()
    }

    private func addProject(to entity: Entity) {
        let existingCodes = Set(projects.map(\.code))
        var index = 1
        var candidate = "PXX_\(String(format: "%03d", index))"
        while existingCodes.contains(candidate) {
            index += 1
            candidate = "PXX_\(String(format: "%03d", index))"
        }

        let project = Project(
            code: candidate,
            name: "Nouveau Projet",
            domain: entity.name,
            sponsor: "",
            projectType: "Métier",
            phase: "Cadrage"
        )
        project.entity = entity
        context.insert(project)
        try? context.save()
    }

    private func reindexSpotlight() {
        isReindexing = true
        spotlightStatus = ""
        SpotlightIndexService.shared.indexAll(projects: projects, collaborators: collaborators)
        SpotlightIndexService.shared.fetchIndexedItemCount { count in
            isReindexing = false
            spotlightStatus = "\(count) éléments indexés — OK"
        }
    }

    private func createBackup() {
        let service = BackupService()
        do {
            let data = try service.backup(
                settings: settings,
                entities: entities,
                projects: projects,
                collaborators: collaborators,
                interviews: interviews,
                meetings: meetings
            )
            guard let url = service.saveBackupPanel() else { return }
            try data.write(to: url)
            backupStatus = "Backup créé — OK"
        } catch {
            backupStatus = "Échec du backup: \(error.localizedDescription)"
        }
    }

    private func restoreBackup() {
        let service = BackupService()
        do {
            guard let url = service.openBackupPanel() else { return }
            let data = try Data(contentsOf: url)
            try service.restore(from: data, into: context)
            backupStatus = "Restauration terminée — OK"
        } catch {
            backupStatus = "Échec de la restauration: \(error.localizedDescription)"
        }
    }

    private func ensureSingleSettingsRecord() {
        guard !settingsList.isEmpty else { return }
        let canonical = settingsList.canonicalSettings ?? settingsList[0]
        for candidate in settingsList where candidate.persistentModelID != canonical.persistentModelID {
            context.delete(candidate)
        }
        try? context.save()
    }
}
