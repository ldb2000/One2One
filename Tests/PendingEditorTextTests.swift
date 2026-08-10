import Testing
import AppKit
@testable import OneToOne

/// L'éditeur markdown ne pousse le texte tapé dans son binding qu'après un
/// débounce (0,3 s), et son démontage ne vide pas l'écriture en attente. Juger
/// une note « vide » sur le modèle, juste après une frappe, la juge donc sur
/// un état périmé — et la supprime avec le texte qu'on vient d'y écrire.
@MainActor
@Suite("PendingEditorText — le texte à l'écran plutôt que le modèle périmé")
struct PendingEditorTextTests {

    @Test("Rend le markdown porté par l'éditeur enregistré sous cet identifiant")
    func returnsOnScreenMarkdown() {
        let editorID = "test-pending-editor"
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.string = "Rappeler Paul sur le budget"
        MarkdownEditorRegistry.shared.register(textView, id: editorID)
        defer { MarkdownEditorRegistry.shared.unregister(id: editorID) }

        #expect(PendingEditorText.onScreen(editorID: editorID) == "Rappeler Paul sur le budget")
    }

    @Test("Sans éditeur monté sous cet identifiant, rien à reprendre")
    func nilWhenNoEditorIsMounted() {
        #expect(PendingEditorText.onScreen(editorID: "aucun-editeur-monte") == nil)
    }

    @Test("Un identifiant vide ne va rien chercher")
    func emptyIDFindsNothing() {
        #expect(PendingEditorText.onScreen(editorID: "") == nil)
    }
}
