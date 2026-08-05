import SwiftUI

/// Éditeur de notes markdown basé sur le module natif `OneToOne/Markdown/`
/// (`MarkdownTextEditor` → `EditorRepresentable`, `NSTextView`/TextKit 1) :
/// stylage live en frappe (titres, gras, listes), marqueurs de liste dessinés,
/// cases à cocher cliquables, menu `/` pour les conversions de bloc, images
/// inline collées. Deux modes commutables :
/// - **Aperçu** (défaut) : `.markdownReadOnly(true)` — lecture seule, rendu stylé.
/// - **Édition** : `.markdownReadOnly(false)` — saisie avec stylage live.
///
/// Défaut = Aperçu, sauf note vide → démarre en Édition (évite l'écran blanc).
///
/// Remplace l'éditeur tiers **MarkdownEngine** (nodes-app/swift-markdown-engine,
/// `NativeTextViewWrapper`) précédemment utilisé ici. Les deux moteurs lisent
/// et écrivent du markdown : les notes existantes s'ouvrent telles quelles et
/// se normalisent note par note à la première édition — aucune conversion en
/// masse n'a été faite.
///
/// Perdu dans la bascule, volontairement **non réimplémenté** :
/// - rendu des tableaux (le module les conserve tels quels, en texte brut monospace) ;
/// - LaTeX ;
/// - coloration syntaxique des blocs de code (le module les affiche en
///   monospace uni, sans coloration par langage) ;
/// - Writing Tools (macOS) ;
/// - recherche intégrée au document ;
/// - undo scoping par document ;
/// - mémorisation de la position de défilement ;
/// - `==surlignage==` ;
/// - conversion automatique d'une table HTML collée en tableau markdown.
struct MarkdownNoteEditor: View {
    @Binding var text: String
    /// Identifiant d'enregistrement dans `MarkdownEditorRegistry` (équivalent
    /// du `documentId` de l'ancien moteur).
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

            MarkdownTextEditor(text: $text)
                .markdownFeatures(.prep)
                .markdownReadOnly(!isEditing)
                .markdownEditorID(editorID)
        }
    }
}
