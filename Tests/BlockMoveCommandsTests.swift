import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `BlockMoveCommands` (⌥↑/⌥↓) et son câblage —
/// `EditorTextView.onOptionVerticalArrow` → `Coordinator.moveCurrentBlock(up:)`.
/// Même schéma de montage que `Tests/ListEditingCommandsTests.swift`.
@MainActor
final class BlockMoveCommandsTests: XCTestCase {

    // MARK: - ⌥↑ / ⌥↓ sur des paragraphes simples

    func test_moveUp_swapsWithThePreviousParagraph() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux\n\nTrois")
        let cursor = (editor.textStorage!.string as NSString).range(of: "Deux").location + 2
        editor.setSelectedRange(NSRange(location: cursor, length: 0))

        let handled = BlockMoveCommands.moveUp(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(editor.textStorage!.string, "Deux\nUn\nTrois")
        XCTAssertEqual(serialized(editor), "Deux\n\nUn\n\nTrois")
        XCTAssertEqual(editor.textStorage!.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .paragraph)
    }

    func test_moveDown_swapsWithTheNextParagraph() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux\n\nTrois")
        editor.setSelectedRange(NSRange(location: 1, length: 0)) // dans "Un"

        let handled = BlockMoveCommands.moveDown(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(editor.textStorage!.string, "Deux\nUn\nTrois")
        XCTAssertEqual(serialized(editor), "Deux\n\nUn\n\nTrois")
    }

    /// Deux déplacements symétriques (⌥↓ sur « Un », ⌥↑ sur « Deux ») doivent
    /// produire le même résultat — même paire de blocs échangée.
    func test_moveUpAndMoveDown_onTheSamePair_areSymmetric() {
        let (up, _) = makeWiredEditor(markdown: "Un\n\nDeux\n\nTrois")
        let deuxStart = (up.textStorage!.string as NSString).range(of: "Deux").location
        up.setSelectedRange(NSRange(location: deuxStart, length: 0))
        _ = BlockMoveCommands.moveUp(in: up)

        let (down, _) = makeWiredEditor(markdown: "Un\n\nDeux\n\nTrois")
        down.setSelectedRange(NSRange(location: 0, length: 0))
        _ = BlockMoveCommands.moveDown(in: down)

        XCTAssertEqual(up.textStorage!.string, down.textStorage!.string)
    }

    // MARK: - Curseur : suit le bloc déplacé

    func test_moveUp_cursorFollowsTheMovedBlockAtTheSameRelativeOffset() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux\n\nTrois")
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "Deux").location
        editor.setSelectedRange(NSRange(location: deuxStart + 2, length: 0)) // "De|ux"

        _ = BlockMoveCommands.moveUp(in: editor)

        // "Deux" est maintenant en tête du storage : "De|ux" tombe à l'index 2.
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
    }

    func test_moveDown_cursorFollowsTheMovedBlockAtTheSameRelativeOffset() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux\n\nTrois")
        editor.setSelectedRange(NSRange(location: 1, length: 0)) // "U|n"

        _ = BlockMoveCommands.moveDown(in: editor)

        // Nouveau storage "Deux\nUn\nTrois" : "U|n" tombe à l'index 6.
        XCTAssertEqual(editor.textStorage!.string, "Deux\nUn\nTrois")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 6, length: 0))
    }

    // MARK: - Bords : pas d'effet, pas de crash

    func test_moveUp_onFirstBlock_isANoOp() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux")
        editor.setSelectedRange(NSRange(location: 1, length: 0))

        let handled = BlockMoveCommands.moveUp(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(editor.textStorage!.string, "Un\nDeux")
    }

    func test_moveDown_onLastBlock_isANoOp() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux")
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "Deux").location
        editor.setSelectedRange(NSRange(location: deuxStart, length: 0))

        let handled = BlockMoveCommands.moveDown(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(editor.textStorage!.string, "Un\nDeux")
    }

    /// Le dernier bloc réel est suivi d'un `\n` qui n'est lui-même suivi de
    /// rien (ligne finale vide fraîchement tapée, cf.
    /// `MarkdownBlockCommandsTests.test_setListKind_caretOnFinalEmptyLine`) :
    /// ce `\n` est le tout dernier caractère du storage, pas un vrai
    /// séparateur vers un bloc suivant. `⌥↓` ne doit rien faire.
    func test_moveDown_lastBlockFollowedOnlyByATrailingNewline_isANoOp() {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux")
        editor.textStorage?.append(NSAttributedString(string: "\n"))
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "Deux").location
        editor.setSelectedRange(NSRange(location: deuxStart, length: 0))

        let handled = BlockMoveCommands.moveDown(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(editor.textStorage!.string, "Un\nDeux\n")
    }

    func test_moveUp_singleBlockDocument_isANoOp() {
        let (editor, _) = makeWiredEditor(markdown: "Seul")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertFalse(BlockMoveCommands.moveUp(in: editor))
        XCTAssertFalse(BlockMoveCommands.moveDown(in: editor))
        XCTAssertEqual(editor.textStorage!.string, "Seul")
    }

    // MARK: - Blocs spéciaux : bloc de code, tableau — jamais fragmentés

    /// Le bloc de code se déplace d'un seul tenant (ses deux lignes internes
    /// ne se dispersent pas), attributs (`.mdBlockType`, `.mdCodeLanguage`)
    /// et contenu intacts.
    func test_moveUp_wholeCodeBlockMovesAsOneUnit() {
        let (editor, _) = makeWiredEditor(markdown: "Avant\n\n```swift\nune\ndeux\n```")
        let storage = editor.textStorage!
        let uneStart = (storage.string as NSString).range(of: "une").location
        editor.setSelectedRange(NSRange(location: uneStart, length: 0))

        let handled = BlockMoveCommands.moveUp(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "une\ndeux\nAvant")
        XCTAssertEqual(storage.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .codeBlock)
        XCTAssertEqual(storage.attribute(.mdCodeLanguage, at: 0, effectiveRange: nil) as? String, "swift")
        var effective = NSRange(location: NSNotFound, length: 0)
        _ = storage.attribute(.mdBlockType, at: 0, longestEffectiveRange: &effective,
                              in: NSRange(location: 0, length: storage.length))
        XCTAssertEqual(effective, NSRange(location: 0, length: 8), "les deux lignes « une »/« deux » doivent rester un seul run")
        XCTAssertEqual(storage.attribute(.mdBlockType, at: 9, effectiveRange: nil) as? BlockType, .paragraph)

        assertRoundTripIsStable(editor)
    }

    /// Un paragraphe qui saute par-dessus un tableau entier ne doit ni le
    /// disloquer ni fusionner l'une de ses cellules avec le paragraphe.
    func test_moveUp_pastAWholeTable_tableStaysIntact() throws {
        let (editor, _) = makeWiredEditor(markdown: "| A | B |\n|---|---|\n| 1 | 2 |\n\nAprès")
        let storage = editor.textStorage!
        let apresStart = (storage.string as NSString).range(of: "Après").location
        editor.setSelectedRange(NSRange(location: apresStart, length: 0))

        let handled = BlockMoveCommands.moveUp(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "Après\nA\nB\n1\n2")
        XCTAssertEqual(storage.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .paragraph)
        let cellA = try XCTUnwrap(storage.attribute(.mdTableCell, at: 6, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(cellA.row, 0)
        XCTAssertEqual(cellA.column, 0)
        let block = BlockRange.of(in: storage, at: 6)
        XCTAssertEqual(storage.attributedSubstring(from: block.range).string, "A\nB\n1\n2",
                       "le tableau doit rester un seul bloc contigu après le déplacement")

        assertRoundTripIsStable(editor)
    }

    // MARK: - Aller-retour : les frontières de bloc restent correctes après déplacement

    /// `MarkdownSerializer.needsBlankLine` insère une ligne vide entre deux
    /// citations consécutives — déplacer un paragraphe pour rendre deux
    /// citations adjacentes doit réapparaître avec cette ligne vide, sans
    /// quoi elles fusionneraient au reparse (continuation paresseuse de
    /// blockquote).
    func test_moveDown_newAdjacency_getsTheBlankLineItNeeds() {
        let (editor, _) = makeWiredEditor(markdown: "> Citation A\n\nParagraphe\n\n> Citation B")
        let paraStart = (editor.textStorage!.string as NSString).range(of: "Paragraphe").location
        editor.setSelectedRange(NSRange(location: paraStart, length: 0))

        let handled = BlockMoveCommands.moveDown(in: editor)
        XCTAssertTrue(handled)

        let md = serialized(editor)
        XCTAssertEqual(md, "> Citation A\n\n> Citation B\n\nParagraphe",
                       "ligne vide requise entre les deux citations désormais adjacentes")

        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
        let ns = reparsed.string as NSString
        XCTAssertEqual(reparsed.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .blockquote)
        let citationBStart = ns.range(of: "Citation B").location
        XCTAssertEqual(reparsed.attribute(.mdBlockType, at: citationBStart, effectiveRange: nil) as? BlockType, .blockquote,
                       "Citation B doit rester une citation séparée, pas fusionnée dans Citation A")
    }

    /// Symétrique : deux items de liste à puces déplacés l'un contre l'autre
    /// restent deux items distincts sans ligne vide superflue (paire
    /// volontairement sûre, cf. doc de `needsBlankLine` : « item de
    /// liste→item de liste » n'en a jamais besoin, une ligne vide romprait
    /// leur appartenance à la même liste visuelle sans que rien ne l'exige).
    func test_moveUp_listItemsStayAdjacent_withoutASpuriousBlankLine() {
        let (editor, _) = makeWiredEditor(markdown: "Para\n\n- un\n\n- deux")
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "deux").location
        editor.setSelectedRange(NSRange(location: deuxStart, length: 0))

        let handled = BlockMoveCommands.moveUp(in: editor)
        XCTAssertTrue(handled)

        let md = serialized(editor)
        XCTAssertEqual(md, "Para\n- deux\n- un", "pas de ligne vide superflue entre les deux items")

        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
        let ns = reparsed.string as NSString
        XCTAssertEqual(reparsed.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .paragraph)
        let deuxStartReparsed = ns.range(of: "deux").location
        XCTAssertNotNil(reparsed.attribute(.mdListInfo, at: deuxStartReparsed, effectiveRange: nil) as? ListInfo,
                        "« deux » doit rester un item de liste")
        let unStartReparsed = ns.range(of: "un").location
        XCTAssertNotNil(reparsed.attribute(.mdListInfo, at: unStartReparsed, effectiveRange: nil) as? ListInfo,
                        "« un » doit rester un item de liste distinct, pas fusionné dans le paragraphe")
    }

    // MARK: - Annulation

    func test_undoingAMove_restoresThePreviousStorage_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: "Un\n\nDeux\n\nTrois")
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)
        let originalString = storage.string
        editor.setSelectedRange(NSRange(location: 1, length: 0)) // dans "Un"

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(BlockMoveCommands.moveDown(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "Deux\nUn\nTrois")
        XCTAssertEqual(editor.undoManager?.canUndo, true, "le déplacement doit s'être enregistré auprès de l'undo manager")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, originalString, "⌘Z doit défaire le déplacement")
        XCTAssertEqual(serialized(editor), "Un\n\nDeux\n\nTrois")
        XCTAssertEqual(storage.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .paragraph)

        editor.undoManager?.redo()
        XCTAssertEqual(storage.string, "Deux\nUn\nTrois", "⇧⌘Z doit rétablir le déplacement")
    }

    /// Reproduit la mesure du rapport de tâche : frapper du texte (une
    /// édition réelle), puis déplacer un bloc. Le premier ⌘Z doit défaire le
    /// déplacement — pas retomber sur la frappe précédente, sans rapport.
    func test_undoAfterTyping_undoesTheMoveFirst_leavingTheTypedTextIntact() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: "Un\n\nDeux")
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)

        editor.undoManager?.beginUndoGrouping()
        editor.insertText(" svp", replacementRange: NSRange(location: storage.length, length: 0))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "Un\nDeux svp")

        editor.setSelectedRange(NSRange(location: 1, length: 0)) // dans "Un"
        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(BlockMoveCommands.moveDown(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "Deux svp\nUn")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, "Un\nDeux svp", "le premier ⌘Z doit défaire le déplacement, pas la frappe")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, "Un\nDeux")
    }

    // MARK: - Câblage clavier réel (⌥↑/⌥↓ synthétiques) et priorité des panneaux

    func test_realOptionUpKeyEvent_movesTheBlock() throws {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux")
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "Deux").location
        editor.setSelectedRange(NSRange(location: deuxStart, length: 0))

        editor.keyDown(with: try optionArrowEvent(up: true))

        XCTAssertEqual(editor.textStorage!.string, "Deux\nUn")
    }

    func test_realOptionDownKeyEvent_movesTheBlock() throws {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        editor.keyDown(with: try optionArrowEvent(up: false))

        XCTAssertEqual(editor.textStorage!.string, "Deux\nUn")
    }

    /// Option+Maj+↑ (sélection étendue par paragraphe) n'est pas notre
    /// geste : ne doit rien déplacer.
    func test_optionShiftUp_isNotOurGesture_doesNotMoveTheBlock() throws {
        let (editor, _) = makeWiredEditor(markdown: "Un\n\nDeux")
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "Deux").location
        editor.setSelectedRange(NSRange(location: deuxStart, length: 0))

        let char = String(UnicodeScalar(0xF700)!)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option, .shift], timestamp: 0,
            windowNumber: 0, context: nil, characters: char, charactersIgnoringModifiers: char,
            isARepeat: false, keyCode: 0x7E
        ))
        editor.keyDown(with: event)

        XCTAssertEqual(editor.textStorage!.string, "Un\nDeux", "ne doit pas avoir bougé")
    }

    func test_whileSlashMenuOpen_optionUp_doesNotMoveTheBlock() throws {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "Un\n\nDeux")
        let deuxStart = (editor.textStorage!.string as NSString).range(of: "Deux").location
        editor.setSelectedRange(NSRange(location: deuxStart, length: 0))
        type("/", into: editor) // "/" en tout début de ligne : déclenche le menu
        XCTAssertTrue(controller.isOpen, "prémisse : le menu doit être ouvert")

        coordinator.moveCurrentBlock(up: true)

        XCTAssertEqual(editor.textStorage!.string, "Un\n/Deux", "le déplacement ne doit pas s'exécuter, menu ouvert")
    }

    // MARK: - Fixtures

    private func assertRoundTripIsStable(_ editor: EditorTextView) {
        let md = serialized(editor)
        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "la sérialisation doit être stable au reparse")
    }

    private func makeWiredEditor(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator) {
        var text = markdown
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let representable = EditorRepresentable(
            markdown: binding, placeholder: "", features: .full, debounce: 0, readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        let editor = makeEditorTextView()
        editor.delegate = coordinator
        coordinator.textView = editor
        editor.onOptionVerticalArrow = { [weak coordinator] up in
            coordinator?.moveCurrentBlock(up: up)
        }

        let parsed = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(parsed)
        if let storage = editor.textStorage {
            StyleRenderer.applyVisualStyle(to: storage)
        }
        coordinator.lastKnownMarkdown = markdown
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        return (editor, coordinator)
    }

    private func makeWiredCoordinator(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator, SlashController) {
        let (editor, coordinator) = makeWiredEditor(markdown: markdown)
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: { [weak coordinator] in coordinator?.cancelPendingWrite() },
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(nil) },
            presentEmojiPicker: {},
            presentFilePicker: { $0(nil) }
        )
        coordinator.slashController = controller
        return (editor, coordinator, controller)
    }

    /// Comme `makeWiredEditor`, mais attache la vue à une vraie `NSWindow`
    /// (jamais affichée) : `NSResponder.undoManager` renvoie `nil` tant que
    /// la vue n'a pas de fenêtre. La fenêtre est renvoyée à l'appelant pour
    /// qu'il la garde en vie (repris de `EditorTextViewTaskToggleTests`).
    private func makeWiredEditorInWindow(markdown: String) -> (EditorTextView, NSWindow) {
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = editor
        // `NSUndoManager.groupsByEvent` suppose une vraie boucle d'événements
        // en cours, absente en test headless — voir la doc identique dans
        // `EditorTextViewTaskToggleTests.makeWiredEditorInWindow`.
        editor.undoManager?.groupsByEvent = false
        return (editor, window)
    }

    private func makeEditorTextView() -> EditorTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        return EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
    }

    private func type(_ text: String, into editor: EditorTextView) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    private func serialized(_ editor: EditorTextView) -> String {
        MarkdownSerializer.serialize(editor.textStorage!)
    }

    private func optionArrowEvent(up: Bool) throws -> NSEvent {
        let char = String(UnicodeScalar(up ? 0xF700 : 0xF701)!)
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: up ? 0x7E : 0x7D
        ))
    }
}
