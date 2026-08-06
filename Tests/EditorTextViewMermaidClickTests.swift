import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `EditorTextView.mermaidBlockRange(at:)`, appelée depuis
/// `mouseDown` — le hit-test qui détermine si un clic tombe sur un
/// diagramme mermaid actuellement affiché (couvrant son texte source), sur
/// le modèle de `EditorTextViewTaskToggleTests.toggleTaskMarker`.
///
/// `mouseDown(with:)` lui-même n'est pas exercé, pour la même raison que
/// `toggleTaskMarker` : construire un `NSEvent` dont `locationInWindow`
/// traverse `convert(_:from:nil)` sans fenêtre réelle est fragile.
/// `mermaidBlockRange(at:)` est donc `internal`, testée directement avec un
/// point déjà en coordonnées de la vue.
final class EditorTextViewMermaidClickTests: XCTestCase {

    override func tearDown() {
        MainActor.assumeIsolated {
            MermaidAttachmentFactory.invalidateLiveCache()
        }
        super.tearDown()
    }

    func test_clickingInsideACollapsedMermaidBlock_returnsItsRange() throws {
        // « intro » avant le bloc : le curseur par défaut (position 0) est
        // ainsi hors du bloc mermaid, qui est donc affiché en diagramme
        // (couvert) — voir `MarkdownLayoutManager.drawMermaidDiagrams`.
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")

        let point = try pointForCharacter(blockRange.location, in: editor)
        let hit = editor.mermaidBlockRange(at: point)

        XCTAssertEqual(hit, blockRange)
    }

    func test_clickingOutsideAnyMermaidBlock_returnsNil() throws {
        let (editor, _) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")

        let point = try pointForCharacter(0, in: editor) // dans « intro »
        XCTAssertNil(editor.mermaidBlockRange(at: point))
    }

    /// Un bloc déjà « ouvert » (curseur dedans, texte source affiché — voir
    /// `MarkdownLayoutManager.drawMermaidDiagrams`) n'a pas de diagramme
    /// peint dessus : cliquer dedans doit laisser `super.mouseDown` faire son
    /// travail habituel (positionnement précis), pas ramener le curseur à son
    /// début.
    func test_clickingInsideABlockAlreadyBeingEdited_returnsNil() throws {
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")
        editor.setSelectedRange(NSRange(location: blockRange.location + 1, length: 0))

        let point = try pointForCharacter(blockRange.location, in: editor)
        XCTAssertNil(editor.mermaidBlockRange(at: point))
    }

    func test_nonMermaidCodeBlock_neverHitTests() throws {
        let (editor, _) = makeWiredEditor(markdown: "```swift\nprint(1)\n```")
        let point = try pointForCharacter(0, in: editor)
        XCTAssertNil(editor.mermaidBlockRange(at: point))
    }

    // MARK: - mermaidDoneButtonRange (état 3 — bouton « Terminé »)

    /// Ouvrir le bloc (curseur dedans) déclenche
    /// `EditorRepresentable.Coordinator.updateMermaidBlockGeometryIfNeeded`
    /// (délégué de sélection, câblé par `makeWiredEditor`), qui bascule sa
    /// géométrie et fait apparaître le bouton — cliquer dessus doit renvoyer
    /// la plage du bloc.
    func test_clickingTheDoneButton_onAnOpenBlock_returnsItsRange() throws {
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))

        let point = try pointInDoneButton(forBlockRange: blockRange, in: editor)
        XCTAssertEqual(editor.mermaidDoneButtonRange(at: point), blockRange)
    }

    func test_clickingTheSourceText_onAnOpenBlock_isNotMistakenForTheDoneButton() throws {
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))

        let point = try pointForCharacter(blockRange.location, in: editor)
        XCTAssertNil(editor.mermaidDoneButtonRange(at: point))
    }

    /// Un bloc fermé (curseur ailleurs) ne peint aucun bouton — le hit-test
    /// doit renvoyer `nil`, jamais l'ancienne géométrie ouverte figée.
    func test_doneButtonRange_onAClosedBlock_returnsNil() throws {
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")

        let point = try pointInDoneButton(forBlockRange: blockRange, in: editor)
        XCTAssertNil(editor.mermaidDoneButtonRange(at: point))
    }

    // MARK: - Fixtures

    /// Bâtit un éditeur dont le storage contient `prefix` puis un bloc
    /// ```` ```mermaid ```` — renvoie la vue et la plage exacte du bloc (lue
    /// sur `.mdMermaidAttachment`, jamais recalculée à la main).
    ///
    /// Repositionne explicitement la sélection à `{0, 0}` : `NSTextView`
    /// place le curseur en **fin de document** dès que `textStorage` reçoit
    /// tout son contenu via `setAttributedString` (mesuré — pas `{0, 0}`
    /// comme on pourrait le supposer). Avec `prefix` non vide, la fin du
    /// document tombe *dans* le bloc mermaid (dernier contenu du fixture),
    /// ce qui fausserait la prémisse « curseur hors du bloc » que ces tests
    /// veulent isoler.
    private func makeWiredEditorWithMermaidBlock(prefix: String) throws -> (EditorTextView, NSRange) {
        let markdown = prefix + "```mermaid\ngraph TD\nA-->B\n```"
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        var blockRange = NSRange(location: 0, length: 0)
        var found = false
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value is NSTextAttachment, range.length > 0 {
                blockRange = range
                found = true
                stop.pointee = true
            }
        }
        guard found else { throw XCTSkip("aucun bloc mermaid détecté — prémisse de fixture non remplie") }
        return (editor, blockRange)
    }

    /// Reproduit le câblage TextKit + coordinateur de
    /// `EditorRepresentable.makeNSView` (repris de
    /// `EditorTextViewTaskToggleTests`), puis y charge `markdown` via le
    /// pipeline réel (`MarkdownParser` + `StyleRenderer`).
    private func makeWiredEditor(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator) {
        var text = markdown
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let representable = EditorRepresentable(
            markdown: binding,
            placeholder: "",
            features: Set<MarkdownFeature>.prep,
            debounce: 0,
            readOnly: false
        )
        let coordinator = representable.makeCoordinator()

        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
        editor.delegate = coordinator
        coordinator.textView = editor

        let parsed = MarkdownParser.parse(markdown)
        textStorage.setAttributedString(parsed)
        StyleRenderer.applyVisualStyle(to: textStorage)
        layoutManager.ensureLayout(for: container)

        return (editor, coordinator)
    }

    /// Point (coordonnées de la vue) tombant sur le glyphe du caractère
    /// `index` — dérivé de la mise en page réelle, comme `markerPoint` dans
    /// `EditorTextViewTaskToggleTests`.
    private func pointForCharacter(_ index: Int, in editor: EditorTextView) throws -> NSPoint {
        let storage = try XCTUnwrap(editor.textStorage)
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let safeIndex = min(index, max(0, storage.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeIndex)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyphIndex)
        return NSPoint(
            x: lineRect.minX + location.x + editor.textContainerInset.width,
            y: lineRect.midY + editor.textContainerInset.height
        )
    }

    /// Point (coordonnées de la vue) au centre du bouton « Terminé » du bloc
    /// `blockRange` — même calcul de géométrie que `EditorTextView.
    /// mermaidDoneButtonRange(at:)` (`MermaidSourceLayout.doneButtonRect`),
    /// pour ne jamais dupliquer une géométrie qui pourrait diverger.
    private func pointInDoneButton(forBlockRange blockRange: NSRange, in editor: EditorTextView) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let buttonRect = MermaidSourceLayout.doneButtonRect(above: firstLineRect, containerWidth: container.size.width)
        return NSPoint(
            x: buttonRect.midX + editor.textContainerInset.width,
            y: buttonRect.midY + editor.textContainerInset.height
        )
    }
}
