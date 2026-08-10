import SwiftUI
import SwiftData

/// Section « Notes » embarquée dans `ProjectDetailView` ou
/// `CollaboratorDetailView`. Une note est un `Meeting` de kind `.note` : la
/// section liste celles de la cible, du plus récent au plus ancien, et ouvre
/// `MeetingView` — il n'y a plus d'éditeur en feuille.
struct NotesSection: View {

    /// Entité propriétaire des notes affichées.
    enum Target {
        case project(Project)
        case collaborator(Collaborator)
    }

    let target: Target

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Meeting> { $0.kindRaw == "note" },
           sort: \Meeting.date, order: .reverse)
    private var allNotes: [Meeting]
    @State private var openedNote: Meeting?

    /// Notes de la cible, triées du plus récent au plus ancien. Statique et
    /// pure : testable sans monter la vue.
    static func notes(for target: Target, in all: [Meeting]) -> [Meeting] {
        let scoped = all.filter { note in
            guard note.kind == .note else { return false }
            switch target {
            case .project(let p):
                return note.project?.persistentModelID == p.persistentModelID
            case .collaborator(let c):
                return note.participants.contains { $0.persistentModelID == c.persistentModelID }
            }
        }
        return scoped.sorted { $0.date > $1.date }
    }

    private var notes: [Meeting] { Self.notes(for: target, in: allNotes) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Notes", systemImage: "note.text")
                        .font(.headline)
                    Spacer()
                    Button { createNote() } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if notes.isEmpty {
                    Text("Aucune note. Clique « Ajouter » pour en créer une.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(notes) { note in
                            NavigationLink {
                                MeetingView(meeting: note)
                            } label: {
                                NoteRow(note: note)
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
                }
            }
            .padding(.vertical, 4)
        }
        .navigationDestination(item: $openedNote) { note in
            MeetingView(meeting: note)
        }
    }

    // ⚠️ `navigationDestination(item:)` doit se trouver dans la pile de
    // navigation qui porte les `NavigationLink` ci-dessus. Si SwiftUI se plaint
    // (« A navigationDestination for … was declared earlier on the stack »), ou
    // si l'ouverture pousse deux fois, retirer ce modificateur et laisser la
    // note nouvellement créée apparaître en tête de liste : l'utilisateur la
    // clique. Vérifier à l'écran avant de conclure.

    private func createNote() {
        let note: Meeting
        switch target {
        case .project(let p):      note = NoteFactory.make(project: p)
        case .collaborator(let c): note = NoteFactory.make(collaborator: c)
        }
        context.insert(note)
        try? context.save()
        SpotlightIndexService.shared.index(meeting: note)
        openedNote = note
    }
}

// MARK: - Row

/// Ligne d'une note : titre (ou première ligne du corps en repli), aperçu et date.
private struct NoteRow: View {
    let note: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
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
