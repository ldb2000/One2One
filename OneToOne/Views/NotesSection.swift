import SwiftUI
import SwiftData

/// Section "Notes" embarquable dans `ProjectDetailView` ou
/// `CollaboratorDetailView`. Liste chronologique (récent → ancien) +
/// bouton "+" qui ouvre `NoteEditorSheet`.
struct NotesSection: View {
    /// Entité propriétaire des notes affichées : soit un projet, soit un
    /// collaborateur. Détermine la source de la liste et le rattachement des
    /// nouvelles notes.
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

/// Feuille d'édition d'une `Note` : titre, corps Markdown (avec bascule
/// Édition/Preview) et pièces jointes. En mode `isNew`, « Annuler » supprime
/// la note pré-insérée ; sinon les modifications sont persistées à
/// l'enregistrement.
struct NoteEditorSheet: View {
    @Bindable var note: Note
    var isNew: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showPreview = false
    @State private var showAttachmentImporter = false
    @State private var attachmentError: String?

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
                .frame(minHeight: 240)
            } else {
                TextEditor(text: $note.body)
                    .font(.body)
                    .padding(6)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                    .frame(minHeight: 240)
            }

            attachmentsSection

            HStack {
                if !isNew {
                    Button(role: .destructive) {
                        // Wipe attached files from disk before deleting the note.
                        for att in note.attachments {
                            AttachmentImporter.deleteFromDisk(att.url)
                        }
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
        .frame(minWidth: 600, minHeight: 540)
        .fileImporter(
            isPresented: $showAttachmentImporter,
            allowedContentTypes: [.pdf, .presentation, .item],
            allowsMultipleSelection: true
        ) { result in
            handleAttachmentImport(result)
        }
    }

    @ViewBuilder
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Pièces jointes", systemImage: "paperclip")
                    .font(.caption.bold())
                Spacer()
                Button {
                    showAttachmentImporter = true
                } label: {
                    Label("Ajouter", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if let err = attachmentError {
                Text(err).font(.caption2).foregroundColor(.red)
            }

            if note.attachments.isEmpty {
                Text("Glissez-déposez un fichier (PDF, PPTX, …) ici ou cliquez Ajouter.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3),
                                           style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
            } else {
                ForEach(note.attachments.sorted(by: { $0.importedAt > $1.importedAt })) { att in
                    HStack(spacing: 8) {
                        Image(systemName: iconForFile(att.fileName))
                            .foregroundColor(.accentColor)
                        Text(att.fileName)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(att.importedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundColor(.secondary)
                        Button {
                            AttachmentImporter.openWithDefaultApp(att.url)
                        } label: {
                            Label("Aperçu", systemImage: "eye")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Ouvrir dans Aperçu (ou app par défaut)")
                        Button(role: .destructive) {
                            AttachmentImporter.deleteFromDisk(att.url)
                            context.delete(att)
                            try? context.save()
                        } label: {
                            Image(systemName: "trash").foregroundColor(.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(6)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            var anyFile = false
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        attachNoteFile(url)
                    }
                }
                anyFile = true
            }
            return anyFile
        }
    }

    private func handleAttachmentImport(_ result: Result<[URL], Error>) {
        attachmentError = nil
        switch result {
        case .success(let urls):
            for url in urls { attachNoteFile(url) }
        case .failure(let err):
            attachmentError = "Échec de l'import : \(err.localizedDescription)"
        }
    }

    private func attachNoteFile(_ source: URL) {
        guard let stableID = note.stableID else {
            attachmentError = "Note sans identifiant stable, impossible d'attacher."
            return
        }
        do {
            let copied = try AttachmentImporter.copyIntoAppSupport(
                source: source,
                bucket: .note(stableID: stableID)
            )
            let att = NoteAttachment(fileName: copied.lastPathComponent, filePath: copied.path)
            att.note = note
            context.insert(att)
            try context.save()
        } catch {
            attachmentError = "Échec de la copie : \(error.localizedDescription)"
        }
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":                return "doc.richtext"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle.angled"
        case "doc", "docx":        return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo"
        default:                   return "paperclip"
        }
    }
}
