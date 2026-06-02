import SwiftUI

/// Editable list of manager categories with add/remove/rename and drag-reorder.
struct ManagerCategoriesEditor: View {
    @Binding var categories: [String]
    @State private var newCategory: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Nouvelle catégorie", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
                    categories.append(trimmed)
                    newCategory = ""
                } label: { Label("Ajouter", systemImage: "plus.circle") }
                .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if categories.isEmpty {
                Text("Aucune catégorie — utilise « Réinitialiser » pour restaurer les défauts.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                List {
                    ForEach(categories.indices, id: \.self) { idx in
                        HStack {
                            TextField("Catégorie", text: Binding(
                                get: { categories[idx] },
                                set: { categories[idx] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            Spacer()
                            Button {
                                categories.remove(at: idx)
                            } label: {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Réordonnancement par glisser-déposer : applique le
                    // déplacement directement au binding `categories`, ce qui
                    // persiste l'ordre choisi par l'utilisateur.
                    .onMove { from, to in
                        categories.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(minHeight: 160, maxHeight: 240)
            }
            Button("Réinitialiser aux 8 défauts") {
                categories = AppSettings.defaultManagerCategories
            }
            .font(.caption)
        }
    }
}
