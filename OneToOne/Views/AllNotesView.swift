import SwiftUI
import SwiftData

/// Vue plein écran listant toutes les notes (projet + collaborateur),
/// triées par date de mise à jour décroissante. Recherche full-text sur
/// titre + corps + nom de la cible.
struct AllNotesView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Environment(\.modelContext) private var context
    @State private var searchText: String = ""
    @State private var editingNote: Note?
    @State private var scopeFilter: ScopeFilter = .all

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "Toutes"
        case project = "Projet"
        case collaborator = "Collaborateur"
        var id: String { rawValue }
    }

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
                        ? "Crée une note depuis la fiche d'un projet ou d'un collaborateur."
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
    }
}

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
