import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

@MainActor
final class EditorRepresentableMermaidEditingTests: XCTestCase {
    func test_typingInsideOpenMermaidBlock_preservesEveryCharacter() throws {
        let markdown = """
        ```mermaid
        flowchart TD
            A[Début] --> B[Fin]
        ```
        """
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let storage = try XCTUnwrap(editor.textStorage)
        let insertion = (storage.string as NSString).range(of: "Début").location + 2

        editor.setSelectedRange(NSRange(location: insertion, length: 0))
        type("partie ", into: editor)

        XCTAssertEqual(storage.string, "flowchart TD\n    A[Départie but] --> B[Fin]")
        XCTAssertEqual(
            MarkdownSerializer.serialize(storage),
            "```mermaid\nflowchart TD\n    A[Départie but] --> B[Fin]\n```"
        )
    }

    /// La borne de fin d'un bloc ouvert est incluse : un curseur placé juste
    /// après le dernier caractère du source (flèche droite, Fin) doit rester
    /// en édition et une frappe doit **ajouter au source**, dans la plage
    /// `.mdCodeLanguage` — pas atterrir hors du bloc.
    func test_typingAtTheEndBoundaryOfAnOpenMermaidBlock_appendsToTheSource() throws {
        let markdown = """
        ```mermaid
        flowchart TD
            A[Début] --> B[Fin]
        ```
        """
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let storage = try XCTUnwrap(editor.textStorage)
        let block = try XCTUnwrap(MermaidBlockLayout.blockRange(in: storage, at: 0))

        editor.setSelectedRange(NSRange(location: NSMaxRange(block), length: 0))
        type("X", into: editor)

        XCTAssertTrue(storage.string.hasSuffix("B[Fin]X"), "la frappe doit s'ajouter à la fin du source")
        XCTAssertEqual(
            MarkdownSerializer.serialize(storage),
            "```mermaid\nflowchart TD\n    A[Début] --> B[Fin]X\n```",
            "le caractère ajouté doit rester dans le bloc mermaid sérialisé"
        )
    }

    func test_replacingASelectionInsideMermaid_changesOnlyThatSelection() throws {
        let markdown = """
        ```mermaid
        flowchart TD
            A[Début] --> B[Fin]
        ```
        """
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let storage = try XCTUnwrap(editor.textStorage)
        let label = (storage.string as NSString).range(of: "Début")

        editor.setSelectedRange(label)
        editor.insertText("Départ", replacementRange: editor.selectedRange())

        XCTAssertEqual(storage.string, "flowchart TD\n    A[Départ] --> B[Fin]")
        XCTAssertEqual(
            MarkdownSerializer.serialize(storage),
            "```mermaid\nflowchart TD\n    A[Départ] --> B[Fin]\n```"
        )
    }

    private func makeWiredEditor(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator) {
        var bound = markdown
        let representable = EditorRepresentable(
            markdown: Binding(get: { bound }, set: { bound = $0 }),
            placeholder: "",
            features: .full,
            debounce: 0,
            readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        let storage = NSTextStorage()
        let manager = MarkdownLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(containerSize: NSSize(width: 600, height: 1_000_000))
        manager.addTextContainer(container)
        let editor = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: 720, height: 500),
            textContainer: container
        )
        editor.delegate = coordinator
        coordinator.textView = editor
        storage.setAttributedString(MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)
        coordinator.lastKnownMarkdown = markdown
        return (editor, coordinator)
    }

    private func type(_ text: String, into editor: EditorTextView) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }
}
