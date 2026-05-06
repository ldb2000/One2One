import SwiftUI

/// Modal sheet shown when an item is being added to the manager report.
/// Displays the snippet, an async-updated category picker (suggestion comes
/// from `ManagerCategoryClassifier`), and a free-form tag field. The sheet
/// opens immediately with `category = suggestedCategory ?? "Information"`
/// and updates the pre-selection if the AI suggestion arrives later, unless
/// the user has already changed the category manually.
struct ManagerClassificationSheet: View {
    let snippet: String
    let projectName: String?
    let categories: [String]
    let suggestedCategory: String?      // updated externally by parent
    let isLoadingSuggestion: Bool
    let onCancel: () -> Void
    let onConfirm: (_ category: String, _ tag: String, _ aiSuggested: String?) -> Void

    @State private var category: String
    @State private var tag: String = ""
    @State private var userTouchedCategory: Bool = false

    private static let snippetPreviewLimit = 280

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
        self.suggestedCategory = suggestedCategory
        self.isLoadingSuggestion = isLoadingSuggestion
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self._category = State(initialValue: suggestedCategory ?? "Information")
    }

    private var truncatedSnippet: String {
        snippet.count > Self.snippetPreviewLimit
            ? String(snippet.prefix(Self.snippetPreviewLimit)) + "…"
            : snippet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Classer ce point")
                    .font(.headline)
                if let p = projectName, !p.isEmpty {
                    Text("Projet : \(p)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GroupBox("Aperçu") {
                Text(truncatedSnippet)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(snippet)
            }

            HStack {
                Text("Catégorie :")
                Picker("Catégorie", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                    if !categories.contains(category) {
                        Text("\(category) (libre)").tag(category)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                .onChange(of: category) { _, _ in
                    userTouchedCategory = true
                }
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
        .onChange(of: suggestedCategory) { _, newValue in
            // Adopt late-arriving AI suggestion only if the user hasn't picked manually.
            if let v = newValue, !userTouchedCategory {
                category = v
            }
        }
    }
}
