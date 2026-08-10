import SwiftUI
import SwiftData

/// Filtrage de l'écran « Notes ». Sorti de la vue pour être testable : la vue
/// n'a plus qu'à afficher le résultat.
enum NoteListFilter {

    /// Portée de filtrage. `.all` n'écarte rien ; `.project` ne garde que les
    /// notes rattachées à un projet, `.collaborator` celles qui portent au
    /// moins un participant.
    enum Scope: String, CaseIterable, Identifiable {
        case all = "Toutes"
        case project = "Projet"
        case collaborator = "Collaborateur"
        var id: String { rawValue }
    }

    static func matches(_ note: Meeting, query: String, scope: Scope) -> Bool {
        switch scope {
        case .all: break
        case .project: if note.project == nil { return false }
        case .collaborator: if note.participants.isEmpty { return false }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if note.title.localizedCaseInsensitiveContains(q) { return true }
        if note.liveNotes.localizedCaseInsensitiveContains(q) { return true }
        if note.project?.name.localizedCaseInsensitiveContains(q) == true { return true }
        return note.participants.contains { $0.name.localizedCaseInsensitiveContains(q) }
    }
}

/// Vue plein écran listant toutes les notes (projet + collaborateur),
/// triées par date décroissante. Une note est un `Meeting` de kind `.note` ;
/// recherche full-text sur titre + corps + nom de la cible via `NoteListFilter`.
struct AllNotesView: View {
    /// `kindRaw` et non `kind` : `#Predicate` travaille sur les colonnes
    /// stockées, pas sur le wrapper calculé. Le littéral "note" est la
    /// `rawValue` de `MeetingKind.note`.
    @Query(filter: #Predicate<Meeting> { $0.kindRaw == "note" },
           sort: \Meeting.date, order: .reverse)
    private var notes: [Meeting]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Collaborator.name) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context
    @State private var searchText: String = ""
    @State private var openedNote: Meeting?
    @State private var scopeFilter: NoteListFilter.Scope = .all

    /// Notes affichées : restreintes par `scopeFilter` puis par `searchText`,
    /// via `NoteListFilter.matches`.
    private var filtered: [Meeting] {
        notes.filter { NoteListFilter.matches($0, query: searchText, scope: scopeFilter) }
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
                    ForEach(NoteListFilter.Scope.allCases) { Text($0.rawValue).tag($0) }
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
                            NavigationLink {
                                MeetingView(meeting: note)
                            } label: {
                                AllNotesRow(note: note)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    SpotlightIndexService.shared.remove(meeting: note)
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
        .navigationDestination(item: $openedNote) { note in
            MeetingView(meeting: note)
        }
    }

    /// Crée une note (libre, projet ou collaborateur), l'insère, l'indexe
    /// pour Spotlight puis l'ouvre.
    private func startNewNote(project: Project? = nil, collaborator: Collaborator? = nil) {
        let note = NoteFactory.make(project: project, collaborator: collaborator)
        context.insert(note)
        try? context.save()
        SpotlightIndexService.shared.index(meeting: note)
        openedNote = note
    }
}

/// Ligne d'une note : symbole et badge selon la cible (projet, collaborateur
/// ou orpheline), titre (titre de la note ou première ligne du corps en repli),
/// aperçu du corps et date.
private struct AllNotesRow: View {
    let note: Meeting

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
                Text(note.date.formatted(date: .abbreviated, time: .shortened))
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
        if note.participants.first != nil { return "person.fill" }
        return "note.text"
    }

    private var targetLabel: String {
        if let p = note.project { return "Projet · \(p.name)" }
        if let c = note.participants.first { return "Collab · \(c.name)" }
        return "Orpheline"
    }

    private var displayTitle: String {
        let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let firstLine = note.liveNotes.split(separator: "\n").first.map(String.init) ?? ""
        let stripped = firstLine.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Sans titre" : String(stripped.prefix(60))
    }

    private var preview: String {
        let lines = note.liveNotes.split(separator: "\n").map(String.init)
        let skipFirst = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let body = skipFirst ? lines.dropFirst() : ArraySlice(lines)
        return body.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
