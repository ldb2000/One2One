import SwiftUI
import SwiftData

/// Compact note-capture popover.
struct QuickNotePopover: View {
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]

    /// Cible de rattachement optionnelle de la note : aucune, un projet ou
    /// un collaborateur, identifié par son `PersistentIdentifier`.
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

    /// Crée une note (`Meeting` de kind `.note`) à partir du texte saisi
    /// (ignorée si vide après trim), la rattache au projet ou au collaborateur
    /// sélectionné le cas échéant, persiste, indexe, puis ferme le popover.
    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var project: Project?
        var collaborator: Collaborator?
        switch linkTarget {
        case .none: break
        case .project(let pid):
            project = projects.first(where: { $0.persistentModelID == pid })
        case .collaborator(let cid):
            collaborator = collaborators.first(where: { $0.persistentModelID == cid })
        }

        let note = NoteFactory.make(body: trimmed, project: project, collaborator: collaborator)
        context.insert(note)
        try? context.save()
        SpotlightIndexService.shared.index(meeting: note)
        onDismiss()
    }
}
