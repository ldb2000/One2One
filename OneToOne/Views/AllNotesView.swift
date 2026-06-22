import SwiftUI
import SwiftData

/// Vue plein écran listant toutes les notes (projet + collaborateur),
/// triées par date de mise à jour décroissante. Recherche full-text sur
/// titre + corps + nom de la cible. Le menu contextuel d'une note permet de
/// l'ajouter au rapport manager via un sheet de classification (cf.
/// `startAddToManagerReport` / `confirmAddNote`).
struct AllNotesView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Collaborator.name) private var collaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @State private var searchText: String = ""
    @State private var editingNote: Note?
    @State private var newNote: Note?
    @State private var scopeFilter: ScopeFilter = .all

    // Manager report add-from-note flow (mirrors MeetingView)
    struct PendingNoteAdd: Identifiable {
        let id = UUID()
        let note: Note
    }
    @State private var pendingNoteAdd: PendingNoteAdd?
    @State private var noteSuggestedCategory: String?
    @State private var noteIsClassifying = false
    @State private var noteSuggestedElaboration: String?
    @State private var noteIsElaborating = false
    @State private var noteInitialElaboration: String = ""
    @State private var noteElaborationFromAI = false
    @State private var noteElaborationFallbackReason = ""

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    /// Portée de filtrage des notes. `.all` (défaut) n'écarte rien ; `.project`
    /// ne garde que les notes rattachées à un projet, `.collaborator` à un
    /// collaborateur.
    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "Toutes"
        case project = "Projet"
        case collaborator = "Collaborateur"
        var id: String { rawValue }
    }

    /// Notes affichées : d'abord restreintes par `scopeFilter`, puis (si la
    /// recherche n'est pas vide) filtrées en insensible à la casse sur le
    /// titre, le corps et le nom de la cible (projet/collaborateur).
    private var filtered: [Note] {
        let scoped = notes.filter { n in
            switch scopeFilter {
            case .all: return true
            case .project: return n.project != nil
            case .collaborator: return n.collaborator != nil
            }
        }
        guard !searchText.isEmpty else { return scoped }
        let q = searchText
        return scoped.filter { n in
            n.title.localizedCaseInsensitiveContains(q)
                || n.body.localizedCaseInsensitiveContains(q)
                || (n.project?.name.localizedCaseInsensitiveContains(q) ?? false)
                || (n.collaborator?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text").foregroundColor(.accentColor)
                Text("Notes").font(.title2.weight(.semibold))
                Spacer()
                Text("\(filtered.count) note\(filtered.count > 1 ? "s" : "")")
                    .font(.caption).foregroundColor(.secondary)
                Menu {
                    Button("Note libre") { startNewNote() }
                    Menu("Pour un projet") {
                        ForEach(projects) { p in
                            Button(p.name) { startNewNote(project: p) }
                        }
                    }
                    Menu("Pour un collaborateur") {
                        ForEach(collaborators) { c in
                            Button(c.name) { startNewNote(collaborator: c) }
                        }
                    }
                } label: {
                    Label("Nouvelle note", systemImage: "plus")
                }
                .fixedSize()
            }

            HStack {
                TextField("Rechercher dans les notes…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $scopeFilter) {
                    ForEach(ScopeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            if filtered.isEmpty {
                ContentUnavailableView(
                    notes.isEmpty ? "Aucune note" : "Aucun résultat",
                    systemImage: "note.text",
                    description: Text(notes.isEmpty
                        ? "Clique « Nouvelle note », ou crée une note depuis la fiche d'un projet ou d'un collaborateur."
                        : "Aucune note ne correspond à cette recherche.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filtered) { note in
                            Button { editingNote = note } label: {
                                AllNotesRow(note: note)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    startAddToManagerReport(note: note)
                                } label: { Label("Ajouter au rapport manager", systemImage: "plus.bubble") }
                                Divider()
                                Button(role: .destructive) {
                                    context.delete(note)
                                    try? context.save()
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .warmBackground()
        .navigationTitle("Notes")
        .sheet(item: $editingNote) { n in
            NoteEditorSheet(note: n)
        }
        .sheet(item: $newNote) { n in
            NoteEditorSheet(note: n, isNew: true)
        }
        .sheet(item: $pendingNoteAdd) { pending in
            ManagerClassificationSheet(
                snippet: noteSnippetFor(pending.note),
                projectName: pending.note.project?.name,
                categories: settings.managerCategories,
                suggestedCategory: noteSuggestedCategory,
                suggestedElaboration: noteSuggestedElaboration,
                initialElaboration: noteInitialElaboration,
                isLoadingSuggestion: noteIsClassifying,
                isLoadingElaboration: noteIsElaborating,
                elaborationFromAI: noteElaborationFromAI,
                elaborationFallbackReason: noteElaborationFallbackReason,
                onCancel: { pendingNoteAdd = nil },
                onConfirm: { category, tag, elaboratedText, aiSuggested in
                    confirmAddNote(note: pending.note,
                                   category: category,
                                   tag: tag,
                                   elaboratedText: elaboratedText,
                                   aiSuggested: aiSuggested)
                }
            )
        }
    }

    /// Crée une note (libre, projet ou collaborateur) et ouvre l'éditeur en
    /// mode création — « Annuler » supprimera la note pré-insérée.
    private func startNewNote(project: Project? = nil, collaborator: Collaborator? = nil) {
        let note = Note(project: project, collaborator: collaborator)
        context.insert(note)
        newNote = note
    }

    // MARK: - Add note to manager report

    /// Stringify a note for snippet/elaboration purposes: title + body.
    private func noteSnippetFor(_ note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        if body.isEmpty { return title }
        return "\(title)\n\n\(body)"
    }

    /// Démarre le flux « ajouter au rapport manager » pour une note : réinitialise
    /// l'état de classification/élaboration, présente le sheet, puis lance en
    /// parallèle deux tâches (classification de catégorie et élaboration de texte)
    /// qui peupleront cet état de façon asynchrone.
    private func startAddToManagerReport(note: Note) {
        let snippet = noteSnippetFor(note)
        noteSuggestedCategory = nil
        noteSuggestedElaboration = nil
        noteIsClassifying = true
        noteIsElaborating = true
        noteElaborationFromAI = false
        noteElaborationFallbackReason = ""
        // Notes have no surrounding meeting transcription, so context is empty.
        noteInitialElaboration = ManagerSnippetElaborator.fallback(
            contextBefore: "", snippet: snippet, contextAfter: ""
        )
        pendingNoteAdd = PendingNoteAdd(note: note)

        let projectName = note.project?.name
        let collaboratorName = note.collaborator?.name
        let sourceTitle: String? = {
            if let p = note.project { return "Note projet · \(p.name)" }
            if let c = note.collaborator { return "Note collaborateur · \(c.name)" }
            return "Note libre"
        }()

        Task { @MainActor in
            let suggested = await ManagerCategoryClassifier.classify(
                snippet: snippet,
                projectName: projectName ?? collaboratorName,
                settings: settings
            )
            noteSuggestedCategory = suggested
            noteIsClassifying = false
        }

        Task { @MainActor in
            let outcome = await ManagerSnippetElaborator.elaborate(
                snippet: snippet,
                contextBefore: "",
                contextAfter: "",
                projectName: projectName,
                sourceMeetingTitle: sourceTitle,
                sourceMeetingDate: note.updatedAt,
                settings: settings
            )
            switch outcome {
            case .ai(let text):
                noteSuggestedElaboration = text
                noteElaborationFromAI = true
                noteElaborationFallbackReason = ""
            case .fallback(let text, let reason):
                noteSuggestedElaboration = text
                noteElaborationFromAI = false
                noteElaborationFallbackReason = reason
            }
            noteIsElaborating = false
        }
    }

    /// Confirme l'ajout d'une note au rapport manager via `ManagerReportService`
    /// (sans réunion source, `sourceField` = "note"), sauvegarde le contexte puis
    /// ferme le sheet. Les erreurs sont journalisées sans interrompre la fermeture.
    private func confirmAddNote(note: Note,
                                category: String,
                                tag: String,
                                elaboratedText: String,
                                aiSuggested: String?) {
        let snippet = noteSnippetFor(note)
        do {
            // Notes are sourceMeeting=nil; sourceField "note" gives a typed
            // marker in case future code wants to filter highlights by source.
            _ = try ManagerReportService.add(
                snippet: snippet,
                sourceField: "note",
                range: NSRange(location: 0, length: 0),
                sourceMeeting: nil,
                contextBefore: "",
                contextAfter: "",
                elaboratedText: elaboratedText,
                category: category,
                tag: tag,
                aiSuggestedCategory: aiSuggested,
                in: context
            )
            try context.save()
        } catch {
            print("[Notes] add failed: \(error)")
        }
        pendingNoteAdd = nil
    }
}

/// Ligne d'une note : symbole et badge selon la cible (projet, collaborateur
/// ou orpheline), titre (titre de la note ou première ligne du corps en repli),
/// aperçu du corps et date de mise à jour.
private struct AllNotesRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: targetSymbol)
                .foregroundColor(.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(targetLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(4)
                }
                if !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var targetSymbol: String {
        if note.project != nil { return "folder.fill" }
        if note.collaborator != nil { return "person.fill" }
        return "note.text"
    }

    private var targetLabel: String {
        if let p = note.project { return "Projet · \(p.name)" }
        if let c = note.collaborator { return "Collab · \(c.name)" }
        return "Orpheline"
    }

    private var displayTitle: String {
        let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let firstLine = note.body.split(separator: "\n").first.map(String.init) ?? ""
        let stripped = firstLine.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Sans titre" : String(stripped.prefix(60))
    }

    private var preview: String {
        let lines = note.body.split(separator: "\n").map(String.init)
        let skipFirst = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let body = skipFirst ? lines.dropFirst() : ArraySlice(lines)
        return body.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
