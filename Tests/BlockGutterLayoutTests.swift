import XCTest
import AppKit
@testable import OneToOne

@MainActor
final class BlockGutterLayoutTests: XCTestCase {
    func test_containerRect_usesTheWholeTextColumnWidth() throws {
        let (storage, manager, container, _) = makeEditor(markdown: "Bloc court\n")
        let range = BlockRange.of(in: storage, at: 0).range

        let rect = try XCTUnwrap(BlockGutterLayout.containerRect(
            for: range,
            layoutManager: manager,
            container: container
        ))

        XCTAssertEqual(rect.minX, 0)
        XCTAssertEqual(rect.width, container.size.width)
        XCTAssertGreaterThan(rect.height, 0)
    }

    func test_iconsFrame_keepsTheGutterOutsideTheBody() {
        let body = NSRect(x: 58, y: 20, width: 500, height: 30)
        let icons = BlockGutterLayout.iconsFrame(forBodyRect: body)

        XCTAssertEqual(icons.handle.maxX, body.minX - BlockGutterLayout.iconRightPadding)
        XCTAssertEqual(icons.plus.maxX + BlockGutterLayout.iconGap, icons.handle.minX)
        XCTAssertLessThan(icons.plus.maxX, body.minX)
        XCTAssertEqual(BlockGutterLayout.hitTest(
            point: NSPoint(x: icons.handle.midX, y: icons.handle.midY),
            bodyRect: body
        ), .handle)
    }

    // MARK: - isCardBlock

    /// Les blocs qui peignent un cadre reçoivent l'écart large ; le texte
    /// courant garde `blockSpacing`. Le prédicat se lit au **début** du bloc :
    /// `BlockRange.tableRange` et `BlockRange.attributedRunRange` démarrent
    /// tous deux, par construction, sur un caractère qui porte l'attribut
    /// (vérifié dans `BlockRange.swift`).
    func test_isCardBlock_isTrueForATableAndACodeBlock() throws {
        let cases: [(markdown: String, needle: String)] = [
            ("```swift\nprint(1)\n```", "print(1)"),
            ("| a | b |\n|---|---|\n| 1 | 2 |", "a")
        ]
        for (markdown, needle) in cases {
            let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
            StyleRenderer.applyVisualStyle(to: storage)
            let location = (storage.string as NSString).range(of: needle).location
            XCTAssertNotEqual(location, NSNotFound, "prémisse : « \(needle) » présent dans le storage stylé")
            let block = BlockRange.of(in: storage, at: location).range
            XCTAssertTrue(
                BlockGutterLayout.isCardBlock(in: storage, at: block.location),
                "« \(markdown) » dessine un cadre"
            )
        }
    }

    /// Image et bloc mermaid : storages construits à la main plutôt que parsés.
    /// Pour l'image, la position exacte du run `.mdImageURL` après stylage n'est
    /// pas garantie d'être le début du bloc ; pour mermaid, passer par
    /// `applyVisualStyle` déclencherait un vrai `WKWebView` en tâche de fond
    /// (voir la doc de tête de `StyleRendererMermaidTests`). Les deux branches
    /// du prédicat sont exercées directement.
    func test_isCardBlock_isTrueForAnImageAndAMermaidBlock() {
        let imageStorage = NSTextStorage(attributedString: NSAttributedString(string: "X"))
        imageStorage.addAttribute(
            .mdImageURL,
            value: URL(string: "https://example.com/x.png")!,
            range: NSRange(location: 0, length: 1)
        )
        XCTAssertTrue(BlockGutterLayout.isCardBlock(in: imageStorage, at: 0))

        let mermaidStorage = NSTextStorage(attributedString: NSAttributedString(string: "X"))
        mermaidStorage.addAttribute(
            .mdMermaidAttachment,
            value: NSTextAttachment(),
            range: NSRange(location: 0, length: 1)
        )
        XCTAssertTrue(BlockGutterLayout.isCardBlock(in: mermaidStorage, at: 0))
    }

    /// Garde-fou : une position hors bornes ne doit jamais lire dans le storage.
    func test_isCardBlock_outOfBounds_isFalse() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("Texte"))
        XCTAssertFalse(BlockGutterLayout.isCardBlock(in: storage, at: -1))
        XCTAssertFalse(BlockGutterLayout.isCardBlock(in: storage, at: storage.length))
        XCTAssertFalse(BlockGutterLayout.isCardBlock(in: storage, at: storage.length + 50))
    }

    func test_isCardBlock_isFalseForOrdinaryText() throws {
        let cases = ["Un paragraphe", "# Un titre", "- un item"]
        for markdown in cases {
            let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
            StyleRenderer.applyVisualStyle(to: storage)
            let block = BlockRange.of(in: storage, at: 0).range
            XCTAssertFalse(
                BlockGutterLayout.isCardBlock(in: storage, at: block.location),
                "« \(markdown) » est du texte courant"
            )
        }
    }

    func test_cardBlockSpacing_isVisiblyLargerThanTextSpacing() {
        XCTAssertGreaterThan(BlockGutterLayout.cardBlockSpacing, BlockGutterLayout.blockSpacing)
    }

    func test_styledAdjacentBlocks_keepAVisibleVerticalGap() throws {
        let (storage, manager, container, _) = makeEditor(markdown: "- Premier\n> Deuxième")
        let first = BlockRange.of(in: storage, at: 0).range
        let secondLocation = (storage.string as NSString).range(of: "Deuxième").location
        let second = BlockRange.of(in: storage, at: secondLocation).range

        let firstStyle = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: first.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertGreaterThanOrEqual(firstStyle.paragraphSpacing, BlockGutterLayout.blockSpacing)

        let firstRect = try XCTUnwrap(BlockGutterLayout.containerRect(
            for: first, layoutManager: manager, container: container
        ))
        let secondRect = try XCTUnwrap(BlockGutterLayout.containerRect(
            for: second, layoutManager: manager, container: container
        ))
        XCTAssertGreaterThanOrEqual(secondRect.minY - firstRect.maxY, BlockGutterLayout.blockSpacing)
    }

    func test_insertSlashBlock_createsACommandLineAboveTheBlock() {
        let (storage, _, _, editor) = makeEditor(markdown: "Premier\n\nDeuxième")
        let secondLocation = (storage.string as NSString).range(of: "Deuxième").location
        let second = BlockRange.of(in: storage, at: secondLocation).range

        editor.insertSlashBlock(above: second)

        XCTAssertEqual(storage.string, "Premier\n/\nDeuxième")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: second.location + 1, length: 0))
    }

    func test_contextMenuInAnOffsetWindow_targetsTheClickedBlock() throws {
        let (storage, manager, container, editor) = makeEditor(markdown: "Premier\n\nDeuxième")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        editor.frame = NSRect(x: 170, y: 120, width: 640, height: 400)
        host.addSubview(editor)
        manager.ensureLayout(for: container)

        let secondLocation = (storage.string as NSString).range(of: "Deuxième").location
        let secondRange = BlockRange.of(in: storage, at: secondLocation).range
        let glyph = manager.glyphIndexForCharacter(at: secondLocation)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let localPoint = NSPoint(
            x: line.minX + editor.textContainerOrigin.x + 10,
            y: line.midY + editor.textContainerOrigin.y
        )
        let windowPoint = editor.convert(localPoint, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        let menu = try XCTUnwrap(editor.menu(for: event))

        XCTAssertEqual(editor.selectedBlockRange, secondRange)
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title), [
            "Monter", "Descendre", "Dupliquer", "Modifier le source", "Supprimer le bloc"
        ])
    }

    // MARK: - Lecture seule

    /// `.markdownReadOnly(true)` : le clic droit doit rendre le menu natif
    /// d'AppKit — jamais le menu de bloc mutable (Monter/Descendre
    /// réécrivent le storage, Supprimer/Dupliquer aussi).
    func test_contextMenuOnAReadOnlyEditor_isNotTheBlockMenu() throws {
        let (storage, manager, container, editor) = makeEditor(markdown: "Premier\n\nDeuxième")
        editor.isEditable = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        editor.frame = NSRect(x: 170, y: 120, width: 640, height: 400)
        host.addSubview(editor)
        manager.ensureLayout(for: container)

        let secondLocation = (storage.string as NSString).range(of: "Deuxième").location
        let glyph = manager.glyphIndexForCharacter(at: secondLocation)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let localPoint = NSPoint(
            x: line.minX + editor.textContainerOrigin.x + 10,
            y: line.midY + editor.textContainerOrigin.y
        )
        let windowPoint = editor.convert(localPoint, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: windowPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        ))

        let menu = editor.menu(for: event)

        XCTAssertNil(editor.selectedBlockRange, "un clic droit en lecture seule ne sélectionne pas le bloc comme objet")
        XCTAssertFalse(
            (menu?.items.map(\.title) ?? []).contains("Supprimer le bloc"),
            "le menu de bloc mutable ne doit pas être proposé en lecture seule"
        )
    }

    /// Même exigence pour la gouttière : la poignée `⠿` (sélection de bloc +
    /// menu mutable) et le `+` (insertion d'une ligne `/`) ne répondent pas
    /// en lecture seule.
    func test_blockGutterHit_onAReadOnlyEditor_returnsNil() throws {
        let (storage, manager, container, editor) = makeEditor(markdown: "Premier\n\nDeuxième")
        let secondLocation = (storage.string as NSString).range(of: "Deuxième").location
        let range = BlockRange.of(in: storage, at: secondLocation).range
        let bodyRect = try XCTUnwrap(BlockGutterLayout.containerRect(
            for: range, layoutManager: manager, container: container
        )).offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        let handle = BlockGutterLayout.iconsFrame(forBodyRect: bodyRect).handle
        let point = NSPoint(x: handle.midX, y: handle.midY)
        XCTAssertNotNil(editor.blockGutterHit(at: point), "prémisse : la poignée répond en mode éditable")

        editor.isEditable = false

        XCTAssertNil(editor.blockGutterHit(at: point))
    }

    private func makeEditor(markdown: String) -> (NSTextStorage, MarkdownLayoutManager, NSTextContainer, EditorTextView) {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        let manager = MarkdownLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(containerSize: NSSize(width: 520, height: 1_000))
        manager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), textContainer: container)
        StyleRenderer.applyVisualStyle(to: storage)
        manager.ensureLayout(for: container)
        return (storage, manager, container, editor)
    }
}
