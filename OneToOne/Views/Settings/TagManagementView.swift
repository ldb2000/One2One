import SwiftUI
import SwiftData

/// Gestion centralisée des thèmes de réunion (`MeetingTag`) : renommer,
/// recolorer, archiver, fusionner, supprimer. Calquée sur
/// `ReportTemplateListView` (liste inline dans les Réglages).
///
/// Supprimer un thème ne supprime jamais les réunions : la relation est
/// `.nullify` des deux côtés.
struct TagManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTag.name) private var tags: [MeetingTag]

    @State private var search: String = ""
    @State private var newName: String = ""
    @State private var showArchived = false
    @State private var pendingDeletion: MeetingTag?

    private var filtered: [MeetingTag] {
        tags
            .filter { showArchived || !$0.isArchived }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Le nom saisi est créable s'il est non vide et n'existe pas déjà.
    private var canCreate: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return MeetingTag.find(name: trimmed, in: context) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Rechercher…", text: $search)
                    .textFieldStyle(.roundedBorder)
                TextField("Nouveau thème…", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { create() }
                Button {
                    create()
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }

            Toggle("Afficher les thèmes archivés", isOn: $showArchived)
                .font(.caption)
                .toggleStyle(.checkbox)

            if filtered.isEmpty {
                Text("Aucun thème")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(filtered) { tag in
                    row(tag)
                    Divider()
                }
            }
        }
        .confirmationDialog(
            "Supprimer le thème « \(pendingDeletion?.name ?? "") » ?",
            isPresented: Binding(get: { pendingDeletion != nil },
                                 set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Supprimer", role: .destructive) {
                if let tag = pendingDeletion { delete(tag) }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Le thème est retiré des réunions concernées. Les réunions elles-mêmes sont conservées.")
        }
    }

    // MARK: - Ligne

    @ViewBuilder
    private func row(_ tag: MeetingTag) -> some View {
        HStack(spacing: 8) {
            colorMenu(tag)

            // Nom stocké tel quel pendant la frappe (trimmer à chaque caractère
            // empêcherait de taper un espace), normalisé à la validation.
            TextField("Nom du thème", text: Binding(
                get: { tag.name },
                set: { tag.name = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            .onSubmit {
                tag.name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
                try? context.save()
            }

            Text("\(tag.meetings.count) réunion(s)")
                .font(.caption)
                .foregroundColor(.secondary)

            if tag.isArchived {
                Text("archivé")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }

            Spacer()

            mergeMenu(tag)

            Button(tag.isArchived ? "Désarchiver" : "Archiver") {
                tag.isArchived.toggle()
                try? context.save()
            }
            .buttonStyle(.bordered).controlSize(.small)

            Button(role: .destructive) {
                pendingDeletion = tag
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Supprimer le thème (les réunions sont conservées)")
        }
    }

    /// Pastille de couleur cliquable → palette.
    private func colorMenu(_ tag: MeetingTag) -> some View {
        Menu {
            ForEach(TagColorPalette.hexes, id: \.self) { hex in
                Button {
                    tag.colorHex = hex
                    try? context.save()
                } label: {
                    Label(hex, systemImage: tag.colorHex == hex ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .secondary)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Changer la couleur")
    }

    /// Fusion : réaffecte les réunions de `tag` vers la cible choisie, puis
    /// supprime `tag`.
    @ViewBuilder
    private func mergeMenu(_ tag: MeetingTag) -> some View {
        let targets = tags.filter { $0.persistentModelID != tag.persistentModelID }
        if !targets.isEmpty {
            Menu("Fusionner dans…") {
                ForEach(targets) { target in
                    Button("\(target.name) (\(target.meetings.count))") {
                        MeetingTag.merge(source: tag, into: target, in: context)
                        try? context.save()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Réaffecte les réunions de ce thème vers un autre, puis le supprime")
        }
    }

    // MARK: - Actions

    private func create() {
        guard canCreate else { return }
        MeetingTag.findOrCreate(name: newName, in: context)
        try? context.save()
        newName = ""
    }

    private func delete(_ tag: MeetingTag) {
        context.delete(tag)
        try? context.save()
    }
}
