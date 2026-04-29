import SwiftUI
import SwiftData

/// Liste complète des collaborateurs (suivis + ad-hoc + archivés).
/// Permet de gérer le niveau d'épinglage :
///   - pinLevel 2 → visible dans le sidebar principal
///   - pinLevel 1 → favori (non affiché sidebar, mais marqué)
///   - pinLevel 0 → uniquement accessible depuis cet écran
struct AllCollaboratorsView: View {
    @Query private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var searchText: String = ""
    @State private var filter: Filter = .all
    @State private var newName: String = ""
    @State private var newRole: String = "Architecte"

    enum Filter: String, CaseIterable, Identifiable {
        case all       = "Tous"
        case pinned    = "Épinglés"
        case favorites = "Favoris"
        case adhoc     = "Ad-hoc"
        case archived  = "Archivés"
        var id: String { rawValue }
    }

    private var filtered: [Collaborator] {
        let base: [Collaborator] = {
            switch filter {
            case .all:       return collaborators.filter { !$0.isArchived }
            case .pinned:    return collaborators.filter { !$0.isArchived && $0.pinLevel >= 2 }
            case .favorites: return collaborators.filter { !$0.isArchived && $0.pinLevel >= 1 }
            case .adhoc:     return collaborators.filter { !$0.isArchived && $0.isAdhoc }
            case .archived:  return collaborators.filter { $0.isArchived }
            }
        }()

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let results: [Collaborator]
        if trimmed.isEmpty {
            results = base
        } else {
            results = base.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.role.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(filtered) { collab in
                    row(collab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            addForm
        }
        .navigationTitle("Tous les collaborateurs")
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Rechercher un collaborateur…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            HStack(spacing: 16) {
                statCell("Total", collaborators.filter { !$0.isArchived }.count)
                statCell("Sidebar", collaborators.filter { !$0.isArchived && $0.pinLevel >= 2 }.count)
                statCell("Favoris", collaborators.filter { !$0.isArchived && $0.pinLevel == 1 }.count)
                statCell("Ad-hoc", collaborators.filter { !$0.isArchived && $0.isAdhoc }.count)
                statCell("Archivés", collaborators.filter { $0.isArchived }.count)
                Spacer()
            }
            .font(.caption)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statCell(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).foregroundColor(.secondary)
        }
    }

    private func row(_ c: Collaborator) -> some View {
        HStack(spacing: 10) {
            SidebarCollaboratorAvatar(collaborator: c)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name).font(.body.weight(.medium))
                    if c.isAdhoc {
                        Text("ad-hoc")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .cornerRadius(6)
                    }
                    if c.isArchived {
                        Text("archivé")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.18))
                            .cornerRadius(6)
                    }
                }
                Text(c.role).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            pinControls(c)

            NavigationLink {
                CollaboratorDetailView(collaborator: c)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(c.isArchived ? "Désarchiver" : "Archiver") {
                c.isArchived.toggle(); save()
            }
            Button(c.isAdhoc ? "Marquer comme suivi" : "Marquer ad-hoc") {
                c.isAdhoc.toggle(); save()
            }
            Divider()
            Button("Supprimer", role: .destructive) {
                context.delete(c); save()
            }
        }
    }

    private func pinControls(_ c: Collaborator) -> some View {
        HStack(spacing: 4) {
            Button(action: { setPin(c, level: c.pinLevel == 1 ? 0 : 1) }) {
                Image(systemName: c.pinLevel >= 1 ? "star.fill" : "star")
                    .foregroundColor(c.pinLevel >= 1 ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Favori")

            Button(action: { setPin(c, level: c.pinLevel == 2 ? 0 : 2) }) {
                Image(systemName: c.pinLevel >= 2 ? "pin.fill" : "pin")
                    .foregroundColor(c.pinLevel >= 2 ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Épingler dans le sidebar")
        }
    }

    private var addForm: some View {
        HStack(spacing: 8) {
            TextField("Nom", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("Rôle", text: $newRole)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
            Button(action: addCollaborator) {
                Label("Ajouter", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    private func setPin(_ c: Collaborator, level: Int) {
        c.pinLevel = level
        save()
    }

    private func addCollaborator() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let c = Collaborator(name: trimmed, role: newRole.isEmpty ? "Architecte" : newRole)
        c.pinLevel = 0
        context.insert(c)
        newName = ""
        save()
    }

    private func save() {
        do { try context.save() } catch { print("[AllCollabs] save FAILED: \(error)") }
    }
}
