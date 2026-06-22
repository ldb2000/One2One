import SwiftUI
import SwiftData

/// Écran de configuration global de l'app : fournisseur IA, prompts, identité du
/// rédacteur, calendrier/menubar, reconnaissance vocale, entités, backup et Spotlight.
/// Persiste sur l'unique enregistrement `AppSettings` (cf. `ensureSingleSettingsRecord`).
struct SettingsView: View {
    @Query private var settingsList: [AppSettings]
    @Query private var entities: [Entity]
    @Query private var projects: [Project]
    @Query private var collaborators: [Collaborator]
    @Query private var interviews: [Interview]
    @Query private var meetings: [Meeting]
    @Environment(\.modelContext) private var context

    /// Renvoie l'enregistrement `AppSettings` canonique. En crée et insère un nouveau
    /// (sauvegardé immédiatement) si aucun n'existe encore.
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
    @State private var apiEndpoint: String = ""
    @State private var modelName: String = ""
    @State private var selectedProvider: AIProvider = .direct
    @State private var directModelRepo: String = ""
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

    // Manager section
    @State private var managerName: String = ""
    @State private var managerEmail: String = ""
    @State private var ownerName: String = ""
    @State private var ownerRole: String = ""
    @State private var managerCategories: [String] = []
    @State private var managerReportPrompt: String = ""

    /// Set to true at the END of onAppear's hydration. Prevents `.onChange` handlers
    /// from running during the initial state-from-DB load — otherwise:
    /// - `selectedProvider = settings.provider` → onChange fires → updateDefaults → resets modelName/apiEndpoint
    /// - my auto-save .onChange(of: modelName) sees the reset → persists the WRONG value
    /// → on next reopen, the saved-by-mistake value comes back. Hence "voxtral keeps coming back".
    @State private var didInitialLoad: Bool = false

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
                            // Skip during initial hydration — otherwise updateDefaults
                            // overwrites the user's saved modelName/endpoint at every
                            // settings reopen.
                            guard didInitialLoad else { return }
                            updateDefaults(for: newProvider)
                            if newProvider == .ollama {
                                fetchOllamaModels()
                            }
                        }

                        if selectedProvider == .direct {
                            // LLM MLX exécuté localement, in-process (≠ Ollama
                            // qui passe par un serveur HTTP).
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Exécute un modèle MLX directement dans l'app, sur l'appareil — sans serveur ni clé API. Le modèle est téléchargé au premier usage puis mis en cache.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                LabeledContent("Modèle (repo HF MLX)") {
                                    EditableTextField(placeholder: "mlx-community/gemma-4-26b-a4b-it-8bit", text: $directModelRepo)
                                        .frame(height: 24)
                                }

                                Text("Ex. mlx-community/gemma-4-26b-a4b-it-8bit (défaut, déjà en cache) · gemma-4-e4b-it-8bit (léger) · gemma-4-31b-8bit (téléchargement ~31 Go)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
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

                        Divider()

                        HStack {
                            // Auto-save on Picker / Provider change is wired via
                            // `.onChange` modifiers below — but we keep an explicit
                            // button so users have a clear "save" anchor.
                            Button("Enregistrer la config IA") { saveSettings() }
                                .buttonStyle(.borderedProminent)
                            if !oauthStatus.isEmpty && oauthStatus.contains("sauvegardés") {
                                Label(oauthStatus, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 5)
                    // Auto-save : every change to provider / endpoint / model
                    // persists immediately. Guarded by `didInitialLoad` so
                    // initial-state hydration doesn't fire false saves.
                    .onChange(of: selectedProvider) { _, _ in
                        guard didInitialLoad else { return }
                        saveSettings()
                    }
                    .onChange(of: modelName) { _, _ in
                        guard didInitialLoad else { return }
                        saveSettings()
                    }
                    .onChange(of: directModelRepo) { _, _ in
                        guard didInitialLoad else { return }
                        saveSettings()
                    }
                    .onChange(of: apiEndpoint) { _, _ in
                        guard didInitialLoad else { return }
                        saveSettings()
                    }
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

                GroupBox("Mon identité (rédacteur des comptes-rendus)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nom et rôle utilisés pour te marquer \"(rédacteur)\" dans la ligne PARTICIPANTS du rapport, et pour afficher ton titre.")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Text("Mon nom :")
                            TextField("ex. Laurent DE BERTI", text: $ownerName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveSettings() }
                        }
                        HStack {
                            Text("Mon rôle :")
                            TextField("ex. Responsable de l'architecture technique",
                                      text: $ownerRole)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveSettings() }
                        }
                    }
                    .padding(.vertical, 5)
                }

                GroupBox("Manager (1:1 manager)") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Nom du manager :")
                            TextField("ex. Alice Dupont", text: $managerName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveSettings() }
                        }
                        HStack {
                            Text("Email du manager (optionnel) :")
                            TextField("alice@example.com", text: $managerEmail)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveSettings() }
                        }

                        Divider()

                        Text("Catégories de classification")
                            .font(.caption.bold())
                        ManagerCategoriesEditor(categories: $managerCategories)
                            .onChange(of: managerCategories) { _, _ in saveSettings() }

                        Divider()

                        HStack {
                            Text("Prompt CR manager (instructions personnalisées)")
                                .font(.caption.bold())
                            Spacer()
                            Button("Réinitialiser") {
                                managerReportPrompt = AppSettings.defaultManagerReportPrompt
                                saveSettings()
                            }
                            .font(.caption)
                        }
                        EditableTextEditor(text: $managerReportPrompt)
                            .frame(minHeight: 80)

                        Button("Enregistrer") { saveSettings() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 5)
                }

                GroupBox("Calendrier & menubar") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Votre email (filtrage 'moi' dans participants)", text: Binding(
                            get: { settings.userEmail },
                            set: { settings.userEmail = $0; saveSettings() }
                        ))

                        Divider()

                        Toggle("Afficher la barre des menus", isOn: Binding(
                            get: { settings.menubarEnabled },
                            set: { settings.menubarEnabled = $0; saveSettings() }
                        ))
                        Toggle("Afficher le titre du prochain meeting", isOn: Binding(
                            get: { settings.menubarShowNextTitle },
                            set: { settings.menubarShowNextTitle = $0; saveSettings() }
                        ))
                        .disabled(!settings.menubarEnabled)
                        Stepper(value: Binding(
                            get: { settings.menubarMaxTitleChars },
                            set: { settings.menubarMaxTitleChars = $0; saveSettings() }
                        ), in: 10...60) {
                            Text("Longueur max du titre: \(settings.menubarMaxTitleChars)")
                        }
                        .disabled(!settings.menubarEnabled || !settings.menubarShowNextTitle)

                        Divider()

                        Toggle("Ouvrir le panneau agenda par défaut", isOn: Binding(
                            get: { settings.agendaInspectorOpenByDefault },
                            set: { settings.agendaInspectorOpenByDefault = $0; saveSettings() }
                        ))

                        Divider()

                        Toggle("Notification au démarrage de l'enregistrement", isOn: Binding(
                            get: { settings.notifRecordingStart },
                            set: { settings.notifRecordingStart = $0; saveSettings() }
                        ))
                        Toggle("Pré-rappel avant la réunion (style Outlook)", isOn: Binding(
                            get: { settings.notifMeetingPreStart },
                            set: { settings.notifMeetingPreStart = $0; saveSettings() }
                        ))
                        if settings.notifMeetingPreStart {
                            HStack {
                                Text("Délai du pré-rappel:")
                                Picker("", selection: Binding(
                                    get: { settings.notifMeetingPreStartMinutes },
                                    set: { settings.notifMeetingPreStartMinutes = $0; saveSettings(); resyncNotifs() }
                                )) {
                                    Text("1 min").tag(1)
                                    Text("2 min").tag(2)
                                    Text("5 min").tag(5)
                                    Text("10 min").tag(10)
                                    Text("15 min").tag(15)
                                    Text("30 min").tag(30)
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 120)
                                Spacer()
                            }
                            .font(.caption)
                        }
                        Toggle("Notification au début de réunion", isOn: Binding(
                            get: { settings.notifMeetingStart },
                            set: { settings.notifMeetingStart = $0; saveSettings() }
                        ))
                        Toggle("Notification 5 min avant la fin", isOn: Binding(
                            get: { settings.notifMeetingEndWarning },
                            set: { settings.notifMeetingEndWarning = $0; saveSettings() }
                        ))
                        Toggle("Notification à la fin de réunion", isOn: Binding(
                            get: { settings.notifMeetingEnd },
                            set: { settings.notifMeetingEnd = $0; saveSettings() }
                        ))

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seuil de match automatique: \(Int(settings.autoImportThreshold * 100))%")
                                .font(.caption)
                            Slider(value: Binding(
                                get: { settings.autoImportThreshold },
                                set: { settings.autoImportThreshold = $0; saveSettings() }
                            ), in: 0.5...1.0, step: 0.05)
                        }

                        Divider()

                        AgendaRulesSettingsList()

                        Divider()

                        Toggle("Récupérer photos depuis Contacts (auto)", isOn: Binding(
                            get: { settings.contactPhotoSyncEnabled },
                            set: { newValue in
                                settings.contactPhotoSyncEnabled = newValue
                                saveSettings()
                                if newValue {
                                    Task {
                                        let granted = await ContactPhotoService.shared.requestAccess()
                                        if granted {
                                            _ = ContactPhotoService.shared.syncMissingPhotos(context: context)
                                            ContactPhotoService.shared.reschedulePeriodicSync(context: context, settings: settings)
                                        }
                                    }
                                }
                            }
                        ))
                        Picker("Intervalle", selection: Binding(
                            get: { settings.contactPhotoSyncIntervalMinutes },
                            set: { newValue in
                                settings.contactPhotoSyncIntervalMinutes = newValue
                                saveSettings()
                                ContactPhotoService.shared.reschedulePeriodicSync(context: context, settings: settings)
                            }
                        )) {
                            Text("10 min").tag(10)
                            Text("30 min").tag(30)
                            Text("1 h").tag(60)
                            Text("2 h").tag(120)
                            Text("6 h").tag(360)
                        }
                        .disabled(!settings.contactPhotoSyncEnabled)

                        Button("Synchroniser maintenant") {
                            Task {
                                let granted = await ContactPhotoService.shared.requestAccess()
                                if granted {
                                    let n = ContactPhotoService.shared.syncMissingPhotos(context: context)
                                    print("[Settings] manual sync: \(n) photo(s) applied")
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recherche photo LinkedIn")
                                .font(.caption.bold())
                            Text("Par défaut: DuckDuckGo (gratuit, sans clé, non officiel — peut casser). Optionnel: Google Custom Search (100 req/jour, plus fiable).")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            SecureField("Google API key (optionnel)", text: Binding(
                                get: { settings.googleCseApiKey },
                                set: { settings.googleCseApiKey = $0; saveSettings() }
                            ))
                            .textFieldStyle(.roundedBorder)
                            TextField("Google CSE ID (cx)", text: Binding(
                                get: { settings.googleCseId },
                                set: { settings.googleCseId = $0; saveSettings() }
                            ))
                            .textFieldStyle(.roundedBorder)
                            HStack(spacing: 4) {
                                Text("Setup:")
                                Link("console.cloud.google.com", destination: URL(string: "https://console.cloud.google.com")!)
                                Text("(API key) +")
                                Link("programmablesearchengine.google.com", destination: URL(string: "https://programmablesearchengine.google.com/")!)
                                Text("(CSE ID, activer Image search).")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Reconnaissance vocale") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Mode de transcription", selection: Binding(
                            get: { settings.transcriptionMode },
                            set: { settings.transcriptionMode = $0; saveSettings() }
                        )) {
                            Text("Transcription seule").tag(TranscriptionMode.transcriptionOnly)
                            Text("Diarisation (locuteurs)").tag(TranscriptionMode.diarizeFirst)
                        }

                        if settings.transcriptionMode == .transcriptionOnly {
                            Picker("Moteur STT", selection: Binding(
                                get: { settings.transcriptionEngine },
                                set: { settings.transcriptionEngine = $0; saveSettings() }
                            )) {
                                Text("Cohere Transcribe").tag(STTEngineKind.cohere)
                                Text("Voxtral").tag(STTEngineKind.voxtral)
                            }
                        }

                        Picker("Variante Voxtral", selection: Binding(
                            get: { settings.voxtralVariant },
                            set: { settings.voxtralVariant = $0; saveSettings() }
                        )) {
                            ForEach(VoxtralVariant.allCases, id: \.self) { v in
                                Text(v.label).tag(v)
                            }
                        }

                        if settings.transcriptionMode == .diarizeFirst {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Seuil auto-assign: \(Int(settings.speakerIdAutoThreshold * 100))%")
                                    .font(.caption)
                                Slider(value: Binding(
                                    get: { settings.speakerIdAutoThreshold },
                                    set: { settings.speakerIdAutoThreshold = $0; saveSettings() }
                                ), in: 0.65...0.90, step: 0.01)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Seuil suggestion: \(Int(settings.speakerIdSuggestThreshold * 100))%")
                                    .font(.caption)
                                Slider(value: Binding(
                                    get: { settings.speakerIdSuggestThreshold },
                                    set: { settings.speakerIdSuggestThreshold = $0; saveSettings() }
                                ), in: 0.50...0.70, step: 0.01)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Séparation des voix (pyannote): \(String(format: "%.2f", settings.diarizationClusterThreshold))")
                                    .font(.caption)
                                Text("Plus haut = plus de speakers distincts. Plus bas = fusionne davantage.")
                                    .font(.caption2).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Button("Plus de speakers") {
                                        settings.diarizationClusterThreshold = 0.95
                                        saveSettings()
                                    }
                                    .fontWeight(settings.diarizationClusterThreshold == 0.95 ? .bold : .regular)
                                    Button("Équilibré") {
                                        settings.diarizationClusterThreshold = 0.85
                                        saveSettings()
                                    }
                                    .fontWeight(settings.diarizationClusterThreshold == 0.85 ? .bold : .regular)
                                    Button("Moins de speakers") {
                                        settings.diarizationClusterThreshold = 0.70
                                        saveSettings()
                                    }
                                    .fontWeight(settings.diarizationClusterThreshold == 0.70 ? .bold : .regular)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Slider(value: Binding(
                                    get: { settings.diarizationClusterThreshold },
                                    set: { settings.diarizationClusterThreshold = $0; saveSettings() }
                                ), in: 0.50...1.10, step: 0.01)
                            }
                        }

                        Divider()
                        Text("Collaborateurs enrôlés").font(.caption.bold()).foregroundColor(.secondary)
                        enrolledCollabsList
                    }
                    .padding(8)
                }

                GroupBox("Capture d'écran") {
                    captureBlacklistSection
                        .padding(8)
                }

                GroupBox("Maintenance") {
                    MaintenanceView()
                        .padding(8)
                }

                GroupBox("Templates de rapport") {
                    ReportTemplateListView()
                        .padding(8)
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
            directModelRepo = settings.directModelRepo
            selectedProvider = settings.provider
            importPrompt = settings.importPrompt
            reformulatePrompt = settings.reformulatePrompt
            weeklyExportPrompt = settings.weeklyExportPrompt
            managerName = settings.managerName
            managerEmail = settings.managerEmail
            ownerName = settings.ownerName
            ownerRole = settings.ownerRole
            managerCategories = settings.managerCategories
            managerReportPrompt = settings.managerReportPrompt

            // Initial state hydration done — allow .onChange handlers to fire saves now.
            didInitialLoad = true
        }
        .warmBackground()
        .navigationTitle("Paramètres")
    }

    /// Interroge `/api/tags` du serveur Ollama (dérivé de l'endpoint en retirant le
    /// suffixe `/v1`) pour lister les modèles installés et met à jour `ollamaModels`.
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

    /// Sauvegarde la config courante puis envoie un prompt de test (« Reponds
    /// uniquement par: OK ») au fournisseur sélectionné et reflète le résultat dans `testStatus`.
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

    /// Renseigne `apiEndpoint` et `modelName` avec les valeurs par défaut associées au
    /// fournisseur donné (appelé lors d'un changement de fournisseur par l'utilisateur).
    private func updateDefaults(for provider: AIProvider) {
        switch provider {
        case .direct:
            if directModelRepo.isEmpty { directModelRepo = "mlx-community/gemma-4-26b-a4b-it-8bit" }
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

    /// Re-applique tous les notifs avec les nouveaux paramètres. Utilisé
    /// quand l'utilisateur change le délai du pré-rappel — les pending
    /// existants restent armés sur l'ancien délai jusqu'à un resync.
    private func resyncNotifs() {
        MeetingNotificationService.shared.syncPending(context: context, settings: settings)
    }

    /// Recopie l'état du formulaire (token, endpoint, modèle, prompts, identité,
    /// catégories manager) vers `settings`, sauvegarde le contexte et met à jour `oauthStatus`.
    private func saveSettings() {

        settings.cloudToken = cloudToken
        settings.apiEndpoint = apiEndpoint
        settings.modelName = modelName
        settings.directModelRepo = directModelRepo
        settings.provider = selectedProvider
        settings.importPrompt = importPrompt
        settings.reformulatePrompt = reformulatePrompt
        settings.weeklyExportPrompt = weeklyExportPrompt
        settings.managerName = managerName
        settings.managerEmail = managerEmail
        settings.ownerName = ownerName
        settings.ownerRole = ownerRole
        settings.managerCategories = managerCategories
        settings.managerReportPrompt = managerReportPrompt
        do {
            try context.save()
            backupStatus = ""
            oauthStatus = oauthStatus.isEmpty ? "Paramètres IA sauvegardés — OK" : oauthStatus
        } catch {
            oauthStatus = "Échec de sauvegarde: \(error.localizedDescription)"
        }
    }

    /// Crée et persiste une nouvelle `Entity` avec un nom par défaut.
    private func addEntity() {
        let entity = Entity(name: "Nouvelle Entité")
        context.insert(entity)
        try? context.save()
    }

    /// Supprime l'entité du contexte et sauvegarde.
    private func deleteEntity(_ entity: Entity) {
        context.delete(entity)
        try? context.save()
    }

    /// Crée un projet rattaché à l'entité en générant un code unique `PXX_NNN`
    /// (premier index libre parmi les codes projets existants).
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

    /// Réindexe projets et collaborateurs dans Spotlight, puis affiche le nombre
    /// d'éléments indexés dans `spotlightStatus`.
    private func reindexSpotlight() {
        isReindexing = true
        spotlightStatus = ""
        SpotlightIndexService.shared.indexAll(projects: projects, collaborators: collaborators)
        SpotlightIndexService.shared.fetchIndexedItemCount { count in
            isReindexing = false
            spotlightStatus = "\(count) éléments indexés — OK"
        }
    }

    /// Exporte toutes les données de l'app (réglages, entités, projets, collaborateurs,
    /// entretiens, réunions et données manager) en JSON via un panneau d'enregistrement.
    private func createBackup() {
        let service = BackupService()
        do {
            let mgrItems = (try? context.fetch(FetchDescriptor<ManagerReportItem>())) ?? []
            let mgrReports = (try? context.fetch(FetchDescriptor<ManagerMeetingReport>())) ?? []
            let mgrActions = (try? context.fetch(FetchDescriptor<ActionTask>(
                predicate: #Predicate { $0.fromManager == true }
            ))) ?? []
            let data = try service.backup(
                settings: settings,
                entities: entities,
                projects: projects,
                collaborators: collaborators,
                interviews: interviews,
                meetings: meetings,
                managerReportItems: mgrItems,
                managerMeetingReports: mgrReports,
                managerActions: mgrActions
            )
            guard let url = service.saveBackupPanel() else { return }
            try data.write(to: url)
            backupStatus = "Backup créé — OK"
        } catch {
            backupStatus = "Échec du backup: \(error.localizedDescription)"
        }
    }

    /// Restaure les données depuis un fichier JSON de backup choisi par l'utilisateur.
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

    /// Garantit l'unicité de l'enregistrement `AppSettings` : conserve le canonique
    /// et supprime tous les doublons éventuels.
    private func ensureSingleSettingsRecord() {
        guard !settingsList.isEmpty else { return }
        let canonical = settingsList.canonicalSettings ?? settingsList[0]
        for candidate in settingsList where candidate.persistentModelID != canonical.persistentModelID {
            context.delete(candidate)
        }
        try? context.save()
    }

    /// Éditeur de la liste noire de capture : une app par ligne, stockée comme
    /// `[String]` (`settings.captureBlacklist`). Les lignes vides sont ignorées à la saisie.
    @ViewBuilder
    private var captureBlacklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps masquées du sélecteur de fenêtre (capture)")
                .font(.subheadline.bold())
            Text("Une app par ligne, nom exact (ex. \"1Password\", \"Slack\"). OneToOne est toujours filtré.")
                .font(.caption2).foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { settings.captureBlacklist.joined(separator: "\n") },
                set: { newValue in
                    let lines = newValue
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    settings.captureBlacklist = lines
                    saveSettings()
                }
            ))
            .font(.body.monospaced())
            .frame(minHeight: 100)
            .border(Color.secondary.opacity(0.2))
        }
    }

    /// Liste les collaborateurs disposant d'une empreinte vocale enrôlée, avec un
    /// bouton pour réinitialiser le voiceprint de chacun.
    @ViewBuilder
    private var enrolledCollabsList: some View {
        let enrolled = collaborators.filter { $0.voicePrint != nil && $0.voicePrintSamples > 0 }
        if enrolled.isEmpty {
            Text("Aucun collaborateur enrôlé. Assignez un speaker dans une réunion pour démarrer l'enrôlement.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(enrolled.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { c in
                HStack {
                    Text(c.name)
                    Text("· \(c.voicePrintSamples) réunion(s)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset voiceprint", role: .destructive) {
                        c.voicePrint = nil
                        c.voicePrintSamples = 0
                        c.voicePrintUpdatedAt = nil
                        saveSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Liste des règles d'affectation agenda → projet (créées depuis le panneau
/// agenda), avec suppression par ligne. Une règle s'applique à toutes les
/// occurrences d'un même titre d'événement.
struct AgendaRulesSettingsList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AgendaProjectRule.createdAt, order: .reverse) private var rules: [AgendaProjectRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Règles d'affectation agenda → projet")
                .font(.caption)
            if rules.isEmpty {
                Text("Aucune règle. Affectez un projet à un événement depuis le panneau Agenda.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    HStack(spacing: 8) {
                        Image(systemName: rule.isIgnored ? "eye.slash" : "folder.fill")
                            .foregroundStyle(rule.isIgnored ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                        Text(rule.displayTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(rule.isIgnored ? "Ignoré" : (rule.project?.name ?? "Sans projet"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            context.delete(rule)
                            try? context.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Supprimer la règle")
                    }
                    .font(.caption)
                }
            }
        }
    }
}
