import SwiftUI
import SwiftData

/// Le formulaire travaille sur des valeurs : ni le catalogue ni le test ne
/// changent l'endpoint actif avant « Enregistrer ».
struct AISettingsView: View {
    let settings: AppSettings
    var automaticallyLoadsModels = true
    @State private var selected: AIProvider = .lmStudio
    @State private var drafts: [AIProvider: AIEndpointProfile] = [:]
    @State private var keys: [AIProvider: String] = [:]
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var status = ""
    @State private var catalogStatus = ""
    @State private var search = ""
    @State private var models: [AIModelDescriptor] = []
    @State private var catalogCache: [String: [AIModelDescriptor]] = [:]
    @State private var work: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var busy = false

    private var draft: AIEndpointProfile { drafts[selected] ?? .defaults(for: selected) }
    private var isEndpoint: Bool { selected.usesCompatibleEndpoint }
    private var filteredModels: [AIModelDescriptor] {
        models.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) || ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }
    private var cacheKey: String { selected.rawValue + ":" + draft.baseURL }
    /// Un niveau enregistré mais devenu non proposé (autre modèle) reste visible.
    private var reasoningLevels: [AIReasoningLevel] {
        let levels = AIReasoningLevel.available(for: draft)
        return levels.contains(draft.reasoning) ? levels : levels + [draft.reasoning]
    }
    private var reasoningCaption: String {
        switch selected {
        case .lmStudio:
            return "LM Studio ignore les paramètres de raisonnement de l’API : les niveaux ajoutent une consigne système reprise du template Qwen. « Désactivé » préremplit un bloc de réflexion vide et n’est proposé que pour les modèles Qwen. La limite de sortie couvre réflexion et réponse."
        case .ollama:
            return "Transmis via reasoning_effort. « Désactivé » supprime la réflexion des modèles qui le permettent. La limite de sortie couvre réflexion et réponse."
        case .openRouter:
            return "Transmis via reasoning.effort. Les modèles à raisonnement obligatoire refusent « Désactivé ». La limite de sortie couvre réflexion et réponse, facturées."
        default:
            return "Le niveau de raisonnement n’est réglable que pour LM Studio, Ollama et OpenRouter."
        }
    }

    var body: some View {
        GroupBox("Configuration IA") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configuration active : \(settings.provider.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Type d’endpoint", selection: Binding(get: { selected }, set: select)) {
                    Text("LM Studio").tag(AIProvider.lmStudio)
                    Text("OpenRouter").tag(AIProvider.openRouter)
                    Text("Ollama").tag(AIProvider.ollama)
                    Divider()
                    ForEach(AIProvider.selectableProviders.filter { !$0.usesCompatibleEndpoint }, id: \.self) { provider in
                        Text("Historique — \(provider.displayName)").tag(provider)
                    }
                }
                .disabled(loadFailed)

                if selected == .geminiOAuth {
                    Button("Importer la connexion Gemini CLI") {
                        if let credentials = GeminiOAuthClient.shared.storage.importFromGeminiCLI() {
                            GeminiOAuthClient.shared.storage.save(credentials)
                            status = "Connexion Gemini importée."
                        } else { status = "Connexion Gemini CLI introuvable." }
                    }
                } else {
                    LabeledContent("Adresse") {
                        EditableTextField(placeholder: "URL de base", text: profileBinding(\.baseURL))
                            .frame(height: 24)
                            .disabled(selected == .openRouter)
                    }
                    LabeledContent(draft.requiresAPIKey ? "Clé API" : "Jeton (facultatif)") {
                        EditableTextField(placeholder: "Stocké dans le Trousseau", text: Binding(
                            get: { keys[selected] ?? "" },
                            set: { keys[selected] = $0; invalidate(); catalogCache.removeValue(forKey: cacheKey); models = []; catalogStatus = "" }
                        ), isSecure: true).frame(height: 24)
                    }
                }

                LabeledContent("Identifiant du modèle") {
                    EditableTextField(placeholder: "Choisir ci-dessous ou saisir un identifiant", text: profileBinding(\.model))
                        .frame(height: 24)
                }

                if isEndpoint {
                    HStack {
                        Button("Actualiser les modèles", action: refreshModels).disabled(busy || loadFailed)
                        EditableTextField(placeholder: "Rechercher un modèle", text: $search).frame(height: 24)
                    }
                    if busy { Text("Chargement / requête en cours…").font(.caption).foregroundStyle(.secondary) }
                    if !catalogStatus.isEmpty {
                        Text(catalogStatus).font(.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !models.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredModels) { model in
                                    Button {
                                        var value = draft
                                        value.model = model.id
                                        drafts[selected] = value
                                        invalidate()
                                    } label: {
                                        HStack {
                                            Image(systemName: draft.model == model.id ? "checkmark.circle.fill" : "circle")
                                            VStack(alignment: .leading) {
                                                Text(model.name ?? model.id)
                                                Text(model.id).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if let context = model.context_length {
                                                Text("\(context) tokens").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain).padding(.vertical, 3)
                                }
                            }
                        }.frame(height: 190)
                        if filteredModels.isEmpty { Text("Aucun modèle ne correspond à la recherche.").font(.caption) }
                    } else {
                        Text("Le catalogue liste les modèles du serveur. Vous pouvez aussi saisir leur identifiant.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LabeledContent("Limite de sortie (tokens)") {
                        EditableTextField(placeholder: String(AIEndpointProfile.defaultOutputTokens), text: Binding(
                            get: { String(draft.maxOutputTokens) },
                            set: { if let value = Int($0) { profileBinding(\.maxOutputTokens).wrappedValue = value } }
                        )).frame(width: 100, height: 24)
                    }
                    LabeledContent("Raisonnement") {
                        Picker("Raisonnement", selection: profileBinding(\.reasoning)) {
                            ForEach(reasoningLevels, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }.labelsHidden().frame(width: 180)
                    }
                    Text(reasoningCaption)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if selected == .lmStudio {
                        Text("Lancez le serveur LM Studio. S’il exige une authentification, renseignez le jeton puis actualisez la liste.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if selected == .ollama {
                        Text("Lancez Ollama et installez le modèle souhaité ; le catalogue affiche les modèles disponibles sur ce serveur.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !draft.isOnDevice {
                    Text("Les textes et le contexte de recherche seront transmis à cet endpoint. Le classement distant des mails s’active séparément dans les réglages Mail.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Tester la connexion", action: test).disabled(busy || loadFailed)
                    Button("Enregistrer", action: save).buttonStyle(.borderedProminent).disabled(busy || loadFailed)
                    if busy {
                        ProgressView().controlSize(.small)
                        Button("Annuler") { invalidate(); status = "Opération annulée." }
                    }
                }
                if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
                if loadFailed { Button("Réessayer le chargement", action: load) }
                Divider()
                Text("La transcription, la diarisation et la recherche sémantique conservent leurs moteurs locaux. L’agent de tâches conserve sa connexion Claude CLI.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 5)
        }
        .onAppear { if !loaded { load() } }
        .onChange(of: search) { _, _ in
            if automaticallyLoadsModels && isEndpoint && models.isEmpty && !busy && !loadFailed && catalogStatus.isEmpty { refreshModels() }
        }
        .onDisappear { invalidate() }
    }

    private func profileBinding<T>(_ path: WritableKeyPath<AIEndpointProfile, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: path] }, set: { value in
            var profile = draft
            profile[keyPath: path] = value
            if profile.baseURL != draft.baseURL {
                // Un changement de destination ne doit pas emporter le secret.
                profile.credentialID = nil
                keys[selected] = ""
                models = []
                catalogStatus = ""
            }
            drafts[selected] = profile
            invalidate()
        })
    }

    private func load() {
        do {
            try AIConfigurationStore.migrate(settings)
            let profiles = try AIConfigurationStore.profiles(for: settings)
            drafts = Dictionary(uniqueKeysWithValues: profiles.map { ($0.provider, $0) })
            guard let provider = AIProvider(rawValue: settings.providerRaw) else { throw AIEndpointError.invalidConfiguration }
            selected = provider
            try loadKey()
            loaded = true
            loadFailed = false
            status = ""
            if automaticallyLoadsModels && isEndpoint { refreshModels() }
        } catch { loadFailed = true; status = error.localizedDescription }
    }

    private func loadKey() throws {
        guard keys[selected] == nil else { return }
        if let id = draft.credentialID { keys[selected] = try KeychainAICredentialStore().read(id: id) ?? "" }
        else { keys[selected] = "" }
    }

    private func select(_ provider: AIProvider) {
        invalidate()
        selected = provider
        search = ""
        models = catalogCache[cacheKey] ?? []
        catalogStatus = ""
        do {
            try loadKey()
            if automaticallyLoadsModels && isEndpoint && models.isEmpty { refreshModels() }
        }
        catch { loadFailed = true; status = error.localizedDescription }
    }

    private func invalidate() {
        generation = UUID()
        work?.cancel()
        work = nil
        busy = false
        status = ""
    }

    private func refreshModels() {
        invalidate()
        catalogStatus = ""
        let requestID = generation
        let configuration = AIRequestConfiguration(profile: draft, apiKey: keys[selected] ?? "")
        let cacheID = cacheKey
        busy = true
        work = Task {
            do {
                let values = try await OpenAICompatibleClient().models(configuration: configuration)
                guard requestID == generation else { return }
                models = values
                catalogCache[cacheID] = values
                catalogStatus = values.isEmpty ? "Aucun modèle disponible. Vérifiez le serveur ou saisissez un identifiant." : "\(values.count) modèle(s) disponible(s)."
            } catch {
                guard requestID == generation else { return }
                if case AIEndpointError.http(401) = error, configuration.profile.provider == .lmStudio || configuration.profile.provider == .ollama {
                    catalogStatus = "Le serveur exige un jeton. Renseignez-le ci-dessus, puis cliquez sur Actualiser les modèles."
                } else { catalogStatus = error.localizedDescription }
            }
            busy = false
        }
    }

    private func test() {
        invalidate()
        let requestID = generation
        var profile = draft
        profile.maxOutputTokens = min(profile.maxOutputTokens, 256)
        let configuration = AIRequestConfiguration(profile: profile, apiKey: keys[selected] ?? "")
        let endpoint = isEndpoint
        busy = true
        work = Task {
            do {
                let response: String
                if endpoint {
                    response = try await OpenAICompatibleClient().send(prompt: "Réponds uniquement par : OK", configuration: configuration)
                } else {
                    let temporary = AppSettings(cloudToken: configuration.apiKey, apiEndpoint: profile.baseURL,
                                                modelName: profile.model, provider: profile.provider)
                    temporary.directModelRepo = profile.model
                    response = try await AIClient.send(prompt: "Réponds uniquement par : OK", settings: temporary)
                }
                guard requestID == generation else { return }
                status = "Connexion réussie — \(response.prefix(100)). Les réglages ne sont pas encore enregistrés."
            } catch {
                guard requestID == generation else { return }
                status = error.localizedDescription
            }
            busy = false
        }
    }

    private func save() {
        do {
            if isEndpoint { try AIRequestConfiguration(profile: draft, apiKey: keys[selected] ?? "").validate() }
            try AIConfigurationStore.save(draft, apiKey: keys[selected] ?? "", settings: settings)
            drafts[selected] = try AIConfigurationStore.profile(for: settings)
            status = "Configuration IA enregistrée."
        } catch { status = error.localizedDescription }
    }
}
