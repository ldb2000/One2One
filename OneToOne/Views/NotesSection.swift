import SwiftUI
import SwiftData

/// Section "Notes" embarquable dans `ProjectDetailView` ou
/// `CollaboratorDetailView`. Liste chronologique (récent → ancien) +
/// bouton "+" qui ouvre `NoteEditorSheet`.
struct NotesSection: View {
    enum Target {
        case project(Project)
        case collaborator(Collaborator)
    }

    let target: Target

    @Environment(\.modelContext) private var context
    @State private var editingNote: Note?
    @State private var creatingNew = false

    private var notes: [Note] {
        let raw: [Note] = {
            switch target {
            case .project(let p): return p.notes
            case .collaborator(let c): return c.notes
            }
        }()
        return raw.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Notes", systemImage: "note.text")
                        .font(.headline)
                    Spacer()
                    Button {
                        creatingNew = true
                    } label: {
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
                            Button { editingNote = note } label: {
                                NoteRow(note: note)
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
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $editingNote) { n in
            NoteEditorSheet(note: n)
        }
        .sheet(isPresented: $creatingNew) {
            NoteEditorSheet(note: makeNewNote(), isNew: true)
        }
    }

    private func makeNewNote() -> Note {
        let note: Note
        switch target {
        case .project(let p):
            note = Note(project: p)
        case .collaborator(let c):
            note = Note(collaborator: c)
        }
        context.insert(note)
        return note
    }
}

// MARK: - Row

private struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text")
                .foregroundColor(.accentColor)
                .frame(width: 18)
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
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var displayTitle: String {
        let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let firstLine = note.body.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces).prefix(60).description.isEmpty
            ? "Sans titre"
            : String(firstLine.trimmingCharacters(in: .whitespaces).prefix(60))
    }

    private var preview: String {
        let lines = note.body.split(separator: "\n").map(String.init)
        let skipFirst = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let body = skipFirst ? lines.dropFirst() : ArraySlice(lines)
        return body.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Editor sheet

struct NoteEditorSheet: View {
    @Bindable var note: Note
    var isNew: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text").foregroundColor(.accentColor)
                Text(isNew ? "Nouvelle note" : "Modifier la note").font(.title3.weight(.semibold))
                Spacer()
                Picker("", selection: $showPreview) {
                    Text("Édition").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            TextField("Titre", text: $note.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            if showPreview {
                ScrollView {
                    MarkdownText(markdown: note.body)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
                .frame(minHeight: 280)
            } else {
                TextEditor(text: $note.body)
                    .font(.body)
                    .padding(6)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                    .frame(minHeight: 280)
            }

            HStack {
                if !isNew {
                    Button(role: .destructive) {
                        context.delete(note)
                        try? context.save()
                        dismiss()
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
                Spacer()
                Button("Annuler") {
                    if isNew {
                        context.delete(note)
                        try? context.save()
                    }
                    dismiss()
                }
                Button(isNew ? "Créer" : "Enregistrer") {
                    note.updatedAt = Date()
                    try? context.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
    }
}
