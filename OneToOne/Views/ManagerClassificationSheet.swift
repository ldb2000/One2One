import SwiftUI

/// Modal sheet shown when an item is being added to the manager report.
/// Displays the snippet, an async-updated category picker (suggestion comes
/// from `ManagerCategoryClassifier`), and a free-form tag field. The sheet
/// opens immediately with `category = "Information"` while the suggestion is
/// fetched in the background.
struct ManagerClassificationSheet: View {
    let snippet: String
    let projectName: String?
    let categories: [String]
    @State var suggestedCategory: String?      // bubbles up from the AI call
    @State var category: String
    @State var tag: String = ""

    let isLoadingSuggestion: Bool
    let onCancel: () -> Void
    let onConfirm: (_ category: String, _ tag: String, _ aiSuggested: String?) -> Void

    init(
        snippet: String,
        projectName: String?,
        categories: [String],
        suggestedCategory: String?,
        isLoadingSuggestion: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String, String, String?) -> Void
    ) {
        self.snippet = snippet
        self.projectName = projectName
        self.categories = categories
        self._suggestedCategory = State(initialValue: suggestedCategory)
        self._category = State(initialValue: suggestedCategory ?? "Information")
        self.isLoadingSuggestion = isLoadingSuggestion
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Classer ce point")
                .font(.headline)

            GroupBox("Aperçu") {
                Text(snippet.count > 280 ? String(snippet.prefix(280)) + "…" : snippet)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Catégorie :")
                Picker("", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                    if !categories.contains(category) {
                        Text("\(category) (libre)").tag(category)
                    }
                }
                .frame(maxWidth: 240)
                if isLoadingSuggestion {
                    ProgressView().controlSize(.small)
                }
            }

            HStack {
                Text("Tag (optionnel) :")
                TextField("ex. infra, budget", text: $tag)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }

            HStack {
                Spacer()
                Button("Annuler", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Ajouter") {
                    onConfirm(category, tag.trimmingCharacters(in: .whitespaces), suggestedCategory)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
    }
}
