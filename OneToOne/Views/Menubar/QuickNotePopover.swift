import SwiftUI
import SwiftData

/// Compact note-capture popover.
struct QuickNotePopover: View {
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]

    enum LinkTarget: Hashable {
        case none
        case project(PersistentIdentifier)
        case collaborator(PersistentIdentifier)
    }

    @State private var text: String = ""
    @State private var linkTarget: LinkTarget = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note rapide").font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Picker("Lié à", selection: $linkTarget) {
                    Text("Aucun").tag(LinkTarget.none)
                    Divider()
                    Section("Projets") {
                        ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in
                            Text("📁 \(p.name)").tag(LinkTarget.project(p.persistentModelID))
                        }
                    }
                    Section("Collaborateurs") {
                        ForEach(collaborators.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { c in
                            Text("👤 \(c.name)").tag(LinkTarget.collaborator(c.persistentModelID))
                        }
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("Annuler") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sauver") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(body: trimmed)
        context.insert(note)
        switch linkTarget {
        case .none: break
        case .project(let pid):
            if let p = projects.first(where: { $0.persistentModelID == pid }) {
                note.project = p
            }
        case .collaborator(let cid):
            if let c = collaborators.first(where: { $0.persistentModelID == cid }) {
                note.collaborator = c
            }
        }
        try? context.save()
        onDismiss()
    }
}
