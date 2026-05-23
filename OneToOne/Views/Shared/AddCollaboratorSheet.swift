import SwiftUI
import SwiftData

/// Sheet de recherche / création de Collaborator.
/// Réutilisée par MeetingActionsSidebar (assignee picker) et
/// OwnerPickerMenu (chef de projet / architecte technique).
struct AddCollaboratorSheet: View {
    let allCollaborators: [Collaborator]
    let onPick: (Collaborator) -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [Collaborator] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allCollaborators.filter { !$0.isArchived }
        guard !trimmed.isEmpty else {
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return base
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var exactMatchExists: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCollaborators.contains { $0.name.lowercased() == trimmed }
    }

    private var canCreate: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !exactMatchExists
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choisir un collaborateur").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher par nom…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let first = filtered.first { onPick(first) }
                        else if canCreate { onCreate(query) }
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            List {
                if canCreate {
                    Button {
                        onCreate(query)
                    } label: {
                        Label("Créer « \(query.trimmingCharacters(in: .whitespacesAndNewlines)) »",
                              systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(filtered) { c in
                    Button {
                        onPick(c)
                    } label: {
                        HStack {
                            Text(c.name)
                            if c.pinLevel >= 1 {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                            Spacer()
                            if !c.role.isEmpty {
                                Text(c.role)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty && !canCreate {
                    Text("Aucun résultat. Tape un nom pour créer un nouveau collaborateur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 360, minHeight: 380)
    }
}
