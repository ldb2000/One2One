import SwiftUI

/// Modal sheet shown when an item is being added to the manager report.
/// Displays:
/// - the original snippet (read-only preview)
/// - an editable elaboration text (pre-filled with deterministic context+snippet
///   fallback, then replaced by AI elaboration when it arrives — unless user has
///   already typed something)
/// - an async-updated category picker (suggestion from `ManagerCategoryClassifier`)
/// - a free-form tag field
struct ManagerClassificationSheet: View {
    let snippet: String
    let projectName: String?
    let categories: [String]
    let suggestedCategory: String?      // updated externally by parent
    let suggestedElaboration: String?   // updated externally by parent (AI text)
    let isLoadingSuggestion: Bool
    let isLoadingElaboration: Bool
    let elaborationFromAI: Bool         // true when elaboration came from AI; false = fallback
    let elaborationFallbackReason: String  // non-empty when fallback used
    let onCancel: () -> Void
    let onConfirm: (_ category: String, _ tag: String, _ elaboratedText: String, _ aiSuggested: String?) -> Void

    @State private var category: String
    @State private var tag: String = ""
    @State private var elaboratedText: String
    @State private var userTouchedCategory: Bool = false
    @State private var userTouchedElaboration: Bool = false

    private static let snippetPreviewLimit = 280

    init(
        snippet: String,
        projectName: String?,
        categories: [String],
        suggestedCategory: String?,
        suggestedElaboration: String?,
        initialElaboration: String,
        isLoadingSuggestion: Bool,
        isLoadingElaboration: Bool,
        elaborationFromAI: Bool = false,
        elaborationFallbackReason: String = "",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String, String, String, String?) -> Void
    ) {
        self.snippet = snippet
        self.projectName = projectName
        self.categories = categories
        self.suggestedCategory = suggestedCategory
        self.suggestedElaboration = suggestedElaboration
        self.isLoadingSuggestion = isLoadingSuggestion
        self.isLoadingElaboration = isLoadingElaboration
        self.elaborationFromAI = elaborationFromAI
        self.elaborationFallbackReason = elaborationFallbackReason
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self._category = State(initialValue: suggestedCategory ?? "Information")
        self._elaboratedText = State(initialValue: initialElaboration)
    }

    private var truncatedSnippet: String {
        snippet.count > Self.snippetPreviewLimit
            ? String(snippet.prefix(Self.snippetPreviewLimit)) + "…"
            : snippet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ajouter au rapport manager")
                    .font(.headline)
                if let p = projectName, !p.isEmpty {
                    Text("Projet : \(p)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GroupBox("Extrait sélectionné") {
                Text(truncatedSnippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(snippet)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Texte du point (modifiable)")
                        .font(.caption.bold())
                    Spacer()
                    if isLoadingElaboration {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Élaboration IA…").font(.caption2).foregroundColor(.secondary)
                        }
                    } else if elaborationFromAI {
                        Label("IA ✓", systemImage: "sparkles")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                            .help("Texte rédigé par l'IA — modifiable")
                    } else if !elaborationFallbackReason.isEmpty {
                        Label("Fallback (IA indisponible)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                            .help("L'IA n'a pas répondu : \(elaborationFallbackReason). Texte = contexte+extrait brut concaténé. Vérifie ton modèle dans Paramètres.")
                    }
                }
                TextEditor(text: $elaboratedText)
                    .font(.callout)
                    .frame(minHeight: 110, maxHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: elaboratedText) { _, _ in
                        userTouchedElaboration = true
                    }
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
                    onConfirm(
                        category,
                        tag.trimmingCharacters(in: .whitespaces),
                        elaboratedText.trimmingCharacters(in: .whitespacesAndNewlines),
                        suggestedCategory
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(elaboratedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
        .onChange(of: suggestedCategory) { _, newValue in
            // Adopt late-arriving AI category suggestion only if the user hasn't picked manually.
            if let v = newValue, !userTouchedCategory {
                category = v
            }
        }
        .onChange(of: suggestedElaboration) { _, newValue in
            // Adopt late-arriving AI elaboration only if user hasn't typed.
            if let v = newValue, !userTouchedElaboration, !v.isEmpty {
                elaboratedText = v
            }
        }
    }
}
