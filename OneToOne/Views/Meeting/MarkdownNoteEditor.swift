import SwiftUI
import MarkdownEngine

/// Éditeur de notes markdown basé sur **MarkdownEngine** (nodes-app,
/// `NativeTextViewWrapper`, TextKit 2) : stylage live en frappe (titres, gras,
/// listes, code, checkboxes, images…). Deux modes commutables :
/// - **Aperçu** (défaut) : `isEditable: false` — lecture seule, rendu stylé.
/// - **Édition** : `isEditable: true` — saisie avec stylage live.
///
/// Défaut = Aperçu, sauf note vide → démarre en Édition (évite l'écran blanc).
struct MarkdownNoteEditor: View {
    @Binding var text: String
    /// Identifiant de document (undo/scroll scoping du moteur).
    let editorID: String

    @State private var isEditing: Bool

    init(text: Binding<String>, editorID: String) {
        self._text = text
        self.editorID = editorID
        self._isEditing = State(initialValue: text.wrappedValue.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $isEditing) {
                    Text("Aperçu").tag(false)
                    Text("Édition").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            NativeTextViewWrapper(
                text: $text,
                fontSize: 15,
                documentId: editorID,
                isEditable: isEditing
            )
        }
    }
}
