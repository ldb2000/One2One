import SwiftUI

/// Éditeur de notes markdown à deux modes commutables :
/// - **Aperçu** (défaut) : markdown rendu via `MarkdownText`.
/// - **Édition** : saisie brute via l'éditeur `NSTextView` existant
///   (`MarkdownTextEditor` + `MarkdownToolbar` au curseur).
///
/// Défaut = Aperçu, sauf note vide → démarre en Édition (évite l'écran blanc).
/// Purement visuel : ne connaît que le `Binding<String>` + un `editorID` (cible
/// de la toolbar) + le jeu de `features` autorisées.
struct MarkdownNoteEditor: View {
    @Binding var text: String
    let editorID: String
    var features: Set<MarkdownFeature>

    @State private var isEditing: Bool

    init(text: Binding<String>, editorID: String, features: Set<MarkdownFeature> = .prep) {
        self._text = text
        self.editorID = editorID
        self.features = features
        self._isEditing = State(initialValue: text.wrappedValue.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $isEditing) {
                    Text("Aperçu").tag(false)
                    Text("Édition").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            if isEditing {
                MarkdownToolbar(textViewID: editorID)
                MarkdownTextEditor(text: $text)
                    .markdownFeatures(features)
                    .markdownEditorID(editorID)
            } else if text.isEmpty {
                Text("Aucune note — passe en Édition pour écrire.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    MarkdownText(markdown: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}
