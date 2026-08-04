import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `EditorTextView.toggleTaskMarker(at:)`, appelée depuis
/// `mouseDown` — la bascule d'une case à cocher lit désormais `.mdListInfo`
/// à la position cliquée plutôt que de comparer des caractères littéraux
/// (`"- [ ] "`/`"- [x] "`) qui n'ont jamais existé dans le storage.
///
/// `mouseDown(with:)` lui-même n'est pas exercé : construire un `NSEvent`
/// dont `locationInWindow` traverse correctement `convert(_:from:nil)` sans
/// fenêtre réelle attachée est fragile. `toggleTaskMarker(at:)` est donc
/// `internal` (comme `insertImagePlaceholder`) et testée directement avec un
/// point déjà dans les coordonnées de la vue — `mouseDown` ne fait rien
/// d'autre que lui déléguer après `convert`.
final class EditorTextViewTaskToggleTests: XCTestCase {

    func test_clickingMarkerZone_ofUncheckedTask_checksItAndNotifiesCallback() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire")
        var notified: (range: NSRange, checked: Bool)?
        editor.onTaskToggle = { range, checked in notified = (range, checked) }

        let didToggle = editor.toggleTaskMarker(at: try markerPoint(in: editor))

        XCTAssertTrue(didToggle)
        let info = try XCTUnwrap(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        XCTAssertEqual(info.checked, true)
        XCTAssertEqual(notified?.checked, true)
    }

    func test_clickingMarkerZone_ofCheckedTask_unchecksIt() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [x] fait")

        let didToggle = editor.toggleTaskMarker(at: try markerPoint(in: editor))

        XCTAssertTrue(didToggle)
        let info = try XCTUnwrap(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        XCTAssertEqual(info.checked, false)
    }

    /// Round-trip complet : la bascule doit se répercuter sur le markdown
    /// sérialisé, pas seulement sur l'attribut en mémoire.
    func test_togglingTask_changesSerializedMarkdown() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire")

        XCTAssertTrue(editor.toggleTaskMarker(at: try markerPoint(in: editor)))

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "- [x] à faire")
    }

    /// Cliquer sur le *texte* de l'item (pas sur le marqueur) ne bascule
    /// rien : la zone cliquable est restreinte à la marge du marqueur.
    func test_clickingOnTaskText_doesNotToggle() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire")

        let point = try markerPoint(in: editor)
        let farRight = NSPoint(x: point.x + 200, y: point.y)
        let didToggle = editor.toggleTaskMarker(at: farRight)

        XCTAssertFalse(didToggle)
        let info = try XCTUnwrap(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        XCTAssertEqual(info.checked, false, "ne doit pas avoir basculé")
    }

    /// Le conteneur de l'éditeur réel est démesurément haut (`huge` dans
    /// `EditorRepresentable.makeNSView`, pour laisser le texte grandir sans
    /// borne) : un clic loin sous la seule ligne du document tombe donc,
    /// pour `characterIndexForInsertion`, sur la ligne la plus proche — la
    /// même ligne, faute d'alternative — malgré une ordonnée hors du
    /// fragment de ligne réel. Sans la restriction verticale, la colonne du
    /// marqueur resterait « cliquable » sur toute la hauteur du conteneur.
    func test_clickingFarBelowTheLine_evenInMarkerColumn_doesNotToggle() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire")

        let markerX = try markerPoint(in: editor).x
        let farBelow = NSPoint(x: markerX, y: 5_000)
        let didToggle = editor.toggleTaskMarker(at: farBelow)

        XCTAssertFalse(didToggle)
        let info = try XCTUnwrap(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        XCTAssertEqual(info.checked, false, "ne doit pas avoir basculé")
    }

    /// Une puce n'est pas une tâche : cliquer sur son marqueur ne doit rien
    /// basculer (il n'y a rien à basculer).
    func test_clickingBulletMarker_doesNotToggle() throws {
        let (editor, _) = makeWiredEditor(markdown: "- puce")

        let didToggle = editor.toggleTaskMarker(at: try markerPoint(in: editor))

        XCTAssertFalse(didToggle)
    }

    // MARK: - Fixtures

    /// Reproduit le câblage TextKit + coordinateur fait par
    /// `EditorRepresentable.makeNSView`, à la main (repris de
    /// `Tests/EditorTextViewPasteTests.swift`), puis y charge `markdown` en
    /// passant par le pipeline réel (`MarkdownParser` + `StyleRenderer`) pour
    /// que `.mdListInfo` et `paragraphStyle` soient posés comme en
    /// production.
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

    /// Point (coordonnées de la vue) tombant sur le marqueur de la première
    /// ligne : au milieu verticalement de son fragment de ligne, à
    /// `firstLineHeadIndent - 2` horizontalement — dans la marge, pas dans le
    /// texte. Dérivé de la mise en page réelle plutôt que de constantes
    /// devinées, pour ne pas dépendre d'une métrique de police précise.
    private func markerPoint(in editor: EditorTextView) throws -> NSPoint {
        let storage = try XCTUnwrap(editor.textStorage)
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let paragraphStyle = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: 0)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        let containerX = max(0, paragraphStyle.firstLineHeadIndent - 2)
        let containerY = lineRect.midY
        return NSPoint(
            x: containerX + editor.textContainerInset.width,
            y: containerY + editor.textContainerInset.height
        )
    }
}
