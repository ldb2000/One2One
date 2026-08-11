import XCTest
import AppKit
@testable import OneToOne

/// Couvre `EditorTextView.replaceBlockCharactersRegisteringUndo` et les
/// commandes de bloc qui s'appuient dessus (`deleteBlock`) : une mutation
/// directe de `NSTextStorage` n'enregistre rien auprès d'`undoManager` (piège
/// documenté par `BlockMoveCommands.swapAdjacentBlocks`) — la primitive doit
/// enregistrer elle-même l'inverse pour que ⌘Z restaure un bloc supprimé,
/// dupliqué ou déplacé.
///
/// Montage fenêtre + `groupsByEvent = false` repris de
/// `EditorTextViewTaskToggleTests` : `NSResponder.undoManager` renvoie `nil`
/// sans fenêtre, et `groupsByEvent` suppose une boucle d'événements absente
/// en test headless.
@MainActor
final class EditorTextViewBlockMutationUndoTests: XCTestCase {

    func test_replaceBlockCharacters_replacesAndRestyles() {
        let (editor, window) = makeEditorInWindow(markdown: "A\n\nB\n\nC")
        defer { _ = window }

        editor.undoManager?.beginUndoGrouping()
        editor.replaceBlockCharactersRegisteringUndo(
            in: NSRange(location: 2, length: 1),
            with: NSAttributedString(string: "X")
        )
        editor.undoManager?.endUndoGrouping()

        XCTAssertEqual(editor.textStorage!.string, "A\nX\nC")
    }

    func test_replaceBlockCharacters_thenUndo_restoresTheDocument() {
        let (editor, window) = makeEditorInWindow(markdown: "A\n\nB\n\nC")
        defer { _ = window }

        editor.undoManager?.beginUndoGrouping()
        editor.replaceBlockCharactersRegisteringUndo(
            in: NSRange(location: 2, length: 1),
            with: NSAttributedString(string: "X")
        )
        editor.undoManager?.endUndoGrouping()
        editor.undoManager?.undo()

        XCTAssertEqual(editor.textStorage!.string, "A\nB\nC")
    }

    func test_replaceBlockCharacters_undoThenRedo_areSymmetric() {
        let (editor, window) = makeEditorInWindow(markdown: "A\n\nB\n\nC")
        defer { _ = window }

        editor.undoManager?.beginUndoGrouping()
        editor.replaceBlockCharactersRegisteringUndo(
            in: NSRange(location: 2, length: 1),
            with: NSAttributedString(string: "X")
        )
        editor.undoManager?.endUndoGrouping()
        editor.undoManager?.undo()
        editor.undoManager?.redo()

        XCTAssertEqual(editor.textStorage!.string, "A\nX\nC")
    }

    func test_deleteBlock_removesTheBlockAndItsSeparator() {
        let (editor, window) = makeEditorInWindow(markdown: "A\n\nB\n\nC")
        defer { _ = window }

        editor.undoManager?.beginUndoGrouping()
        editor.deleteBlock(range: NSRange(location: 2, length: 1))
        editor.undoManager?.endUndoGrouping()

        XCTAssertEqual(editor.textStorage!.string, "A\nC")
    }

    func test_deleteBlock_thenUndo_restoresTheBlock() {
        let (editor, window) = makeEditorInWindow(markdown: "A\n\nB\n\nC")
        defer { _ = window }

        editor.undoManager?.beginUndoGrouping()
        editor.deleteBlock(range: NSRange(location: 2, length: 1))
        editor.undoManager?.endUndoGrouping()
        editor.undoManager?.undo()

        XCTAssertEqual(editor.textStorage!.string, "A\nB\nC")
    }

    /// L'inverse enregistré doit restaurer le texte **attribué** : les
    /// attributs `md*` portent la sémantique des blocs (type, langue,
    /// cellules de tableau) et la sérialisation les lit — un undo qui ne
    /// rendrait que le texte brut corromprait le Markdown produit.
    func test_deleteBlock_thenUndo_restoresTheBlockAttributes() {
        let (editor, window) = makeEditorInWindow(markdown: "A\n\nB\n\nC")
        defer { _ = window }
        editor.textStorage!.addAttribute(
            .mdCodeLanguage, value: "mermaid", range: NSRange(location: 2, length: 1)
        )

        editor.undoManager?.beginUndoGrouping()
        editor.deleteBlock(range: NSRange(location: 2, length: 1))
        editor.undoManager?.endUndoGrouping()
        editor.undoManager?.undo()

        XCTAssertEqual(editor.textStorage!.string, "A\nB\nC")
        XCTAssertEqual(
            editor.textStorage!.attribute(.mdCodeLanguage, at: 2, effectiveRange: nil) as? String,
            "mermaid",
            "les attributs md* du bloc supprimé doivent revenir avec ⌘Z"
        )
    }

    // MARK: - Fixtures

    private func makeEditorInWindow(markdown: String) -> (EditorTextView, NSWindow) {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)

        let parsed = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(parsed)
        if let storage = editor.textStorage {
            StyleRenderer.applyVisualStyle(to: storage)
        }
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = editor
        editor.undoManager?.groupsByEvent = false
        return (editor, window)
    }
}
