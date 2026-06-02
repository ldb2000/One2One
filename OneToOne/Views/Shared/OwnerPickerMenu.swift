import SwiftUI
import SwiftData

/// Menu déroulant pour choisir un Collaborator (chef de projet, architecte
/// technique, ou tout autre rôle d'ownership). Réutilise le pattern :
///   Aucun → Favoris (pinLevel ≥ 1) → Autres collaborateurs → + Ajouter…
///
/// Le bouton « + Ajouter… » présente `AddCollaboratorSheet` qui permet
/// de rechercher ou créer un nouveau collab. Le collab créé est passé
/// au binding via le closure `onCreate` interne.
struct OwnerPickerMenu: View {

    /// Libellé affiché quand aucune sélection n'est faite (ex: "Aucun").
    let label: String                    // ex: "Aucun"
    @Binding var selection: Collaborator?
    let allCollaborators: [Collaborator]
    /// Appelé après chaque changement de sélection (sélection, création ou
    /// remise à zéro), pour permettre à l'appelant de persister la valeur.
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var showingAddSheet: Bool = false

    /// Collaborateurs épinglés (pinLevel ≥ 1) non archivés, triés par nom.
    private var favorites: [Collaborator] {
        allCollaborators
            .filter { $0.pinLevel >= 1 && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Collaborateurs non épinglés (pinLevel == 0) non archivés, triés par nom.
    private var others: [Collaborator] {
        allCollaborators
            .filter { $0.pinLevel == 0 && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            Button {
                selection = nil
                onSaved()
            } label: { Text("Aucun") }

            if !favorites.isEmpty {
                Divider()
                Section("⭐ Favoris") {
                    ForEach(favorites) { c in
                        Button(c.name) {
                            selection = c
                            onSaved()
                        }
                    }
                }
            }

            if !others.isEmpty {
                Divider()
                Section("Autres collaborateurs") {
                    ForEach(others) { c in
                        Button(c.name) {
                            selection = c
                            onSaved()
                        }
                    }
                }
            }

            Divider()
            Button {
                showingAddSheet = true
            } label: {
                Label("Ajouter un collaborateur…", systemImage: "plus")
            }
        } label: {
            Label(
                selection?.name ?? label,
                systemImage: selection != nil
                    ? "person.crop.circle.fill"
                    : "person.crop.circle"
            )
            .font(.callout)
            .foregroundColor(selection != nil ? .primary : .secondary)
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showingAddSheet) {
            AddCollaboratorSheet(
                allCollaborators: allCollaborators,
                onPick: { c in
                    selection = c
                    showingAddSheet = false
                    onSaved()
                },
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let c = Collaborator(name: trimmed)
                    context.insert(c)
                    try? context.save()
                    selection = c
                    showingAddSheet = false
                    onSaved()
                }
            )
        }
    }
}
