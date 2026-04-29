import SwiftUI
import SwiftData

/// "Demander à l'IA sur…" — RAG scopé par projet / collaborateur / type.
/// Retrieve top-K chunks → prompt LLM avec citations → réponse + références.
struct RAGChatView: View {
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    // Scope
    @State private var scopeKind: ScopeKind = .global
    @State private var selectedProject: Project?
    @State private var selectedCollaborator: Collaborator?
    @State private var selectedMeetingKind: MeetingKind? = nil

    // Query
    @State private var question: String = ""
    @State private var isSearching = false
    @State private var answer: String = ""
    @State private var sources: [RAGQuery.Result] = []
    @State private var errorMessage: String?

    enum ScopeKind: String, CaseIterable, Identifiable {
        case global       = "Global"
        case project      = "Projet"
        case collaborator = "Collaborateur"
        case kind         = "Type de réunion"
        var id: String { rawValue }
    }

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !answer.isEmpty {
                        answerBlock
                    }
                    if !sources.isEmpty {
                        sourcesBlock
                    }
                    if answer.isEmpty && sources.isEmpty && !isSearching {
                        ContentUnavailableView(
                            "Interroge ton historique",
                            systemImage: "sparkles.rectangle.stack",
                            description: Text("Pose une question scopée à un projet, un collaborateur ou un type de réunion. Les transcriptions indexées seront utilisées.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    }
                    if let err = errorMessage {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
                .padding()
            }
            Divider()
            queryBar
        }
        .navigationTitle("Assistant RAG")
    }

    // MARK: - Header (scope)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scope :").font(.caption.bold())
                Picker("", selection: $scopeKind) {
                    ForEach(ScopeKind.allCases) { k in Text(k.rawValue).tag(k) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                Spacer()
            }

            switch scopeKind {
            case .global:
                EmptyView()
            case .project:
                Picker("Projet", selection: $selectedProject) {
                    Text("— sélectionne un projet —").tag(nil as Project?)
                    ForEach(projects.sorted(by: { $0.name < $1.name })) { p in
                        Text(p.name).tag(p as Project?)
                    }
                }
                .frame(maxWidth: 380)
            case .collaborator:
                Picker("Collaborateur", selection: $selectedCollaborator) {
                    Text("— sélectionne un collaborateur —").tag(nil as Collaborator?)
                    ForEach(collaborators.sorted(by: { $0.name < $1.name })) { c in
                        Text(c.name).tag(c as Collaborator?)
                    }
                }
                .frame(maxWidth: 380)
            case .kind:
                Picker("Type", selection: $selectedMeetingKind) {
                    Text("— tous —").tag(nil as MeetingKind?)
                    ForEach(MeetingKind.allCases) { k in
                        Text(k.label).tag(k as MeetingKind?)
                    }
                }
                .frame(maxWidth: 260)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Answer + sources

    private var answerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Réponse", systemImage: "sparkles").font(.headline)
            Text(answer).textSelection(.enabled).font(.body)
        }
        .padding()
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(10)
    }

    private var sourcesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sources (\(sources.count))", systemImage: "quote.bubble")
                .font(.headline)
            ForEach(Array(sources.enumerated()), id: \.offset) { idx, r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("[\(idx + 1)]").font(.caption.bold())
                        if let m = r.chunk.meeting {
                            Text(m.title.isEmpty ? "Réunion sans titre" : m.title).font(.caption.bold())
                            Text("·").foregroundColor(.secondary)
                            Text(m.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("sim \(String(format: "%.2f", r.similarity))")
                            .font(.caption2.monospaced()).foregroundColor(.secondary)
                    }
                    Text(r.chunk.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Query bar

    private var queryBar: some View {
        HStack(spacing: 8) {
            TextField("Pose ta question…", text: $question)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            Button(action: { Task { await search() } }) {
                if isSearching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Recherche…")
                    }
                } else {
                    Label("Interroger", systemImage: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSearching || question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Search

    @MainActor
    private func search() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }
        errorMessage = nil
        answer = ""
        sources = []

        var scope = RAGQuery.Scope()
        switch scopeKind {
        case .global:
            break
        case .project:
            guard let p = selectedProject else {
                errorMessage = "Sélectionne un projet."
                return
            }
            scope.projectPID = p.persistentModelID
        case .collaborator:
            guard let c = selectedCollaborator else {
                errorMessage = "Sélectionne un collaborateur."
                return
            }
            scope.collaboratorPID = c.persistentModelID
        case .kind:
            scope.meetingKind = selectedMeetingKind
        }

        do {
            let results = try await RAGQuery.search(
                query: q,
                topK: 6,
                scope: scope,
                context: context
            )
            sources = results

            guard !results.isEmpty else {
                answer = "Aucun extrait pertinent trouvé dans les transcriptions indexées."
                return
            }

            let ctxBlock = results.enumerated().map { idx, r -> String in
                let date = r.chunk.meeting?.date.formatted(date: .abbreviated, time: .omitted) ?? "?"
                let title = r.chunk.meeting?.title ?? "?"
                return "[\(idx + 1)] \(date) — \(title) :\n\(r.chunk.text)"
            }.joined(separator: "\n\n")

            let prompt = """
            Tu es l'assistant de OneToOne. Réponds à la question ci-dessous en
            t'appuyant uniquement sur les extraits fournis. Cite les sources
            entre crochets [1], [2], etc. Si l'information manque, dis-le
            clairement. Pas d'invention.

            Extraits pertinents :
            \(ctxBlock)

            Question :
            \(q)
            """

            let response = try await AIClient.send(prompt: prompt, settings: settings)
            answer = response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
