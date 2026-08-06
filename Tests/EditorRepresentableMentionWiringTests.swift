import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre le câblage du menu « @ » dans `OneToOne/Markdown/Core/
/// EditorRepresentable.swift` : `MentionController` hébergé par
/// `Coordinator` seulement quand `mentionSearch` est fourni, court-circuit de
/// `Coordinator.textDidChange` quand le menu absorbe la frappe, priorité sur
/// `SlashController` pour `textView(_:doCommandBy:)` quand ouvert,
/// rafraîchissement des closures à chaque `updateNSView`, et démontage via
/// `dismantleNSView` — même structure que `Tests/
/// EditorRepresentableSlashWiringTests.swift`, dont ce fichier reprend le
/// harnais.
@MainActor
final class EditorRepresentableMentionWiringTests: XCTestCase {

    // MARK: - `Coordinator` héberge un `MentionController` seulement si configuré

    func test_coordinator_hostsAMentionController_whenSearchIsProvided() {
        let (_, coordinator, controller) = makeWiredCoordinator(markdown: "")
        XCTAssertTrue(coordinator.mentionController === controller)
    }

    /// Par défaut (`mentionSearch == nil`), aucune fonctionnalité de mention
    /// n'est activée — un éditeur qui ne fournit pas `markdownMentions(search:)`
    /// ne doit pas se comporter différemment d'avant cette fonctionnalité.
    func test_coordinator_hasNoMentionController_whenSearchIsNotProvided() {
        let representable = EditorRepresentable(
            markdown: .constant(""), placeholder: "", features: .full, debounce: 0, readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        XCTAssertNil(coordinator.mentionController)
    }

    // MARK: - `Coordinator.textDidChange` court-circuite quand le menu absorbe la frappe

    func test_typingAt_shortCircuitsSerialization_menuAbsorbsTheKeystroke() {
        let (editor, coordinator, _) = makeWiredCoordinator(markdown: "")
        XCTAssertEqual(coordinator.lastKnownMarkdown, "")

        editor.insertText("@", replacementRange: editor.selectedRange())

        XCTAssertFalse(coordinator.hasPendingLocalWrite, "le menu ouvert doit empêcher toute écriture programmée")
        XCTAssertEqual(coordinator.lastKnownMarkdown, "", "la sérialisation ne doit pas avoir tourné")
    }

    func test_witness_typingOrdinaryText_updatesLastKnownMarkdown() {
        let (editor, coordinator, _) = makeWiredCoordinator(markdown: "")
        editor.insertText("a", replacementRange: editor.selectedRange())
        XCTAssertEqual(coordinator.lastKnownMarkdown, "a")
    }

    func test_afterMentionMenuCloses_typingResumesNormalSerialization() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        editor.insertText("@", replacementRange: editor.selectedRange())
        XCTAssertTrue(controller.isOpen)

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(controller.isOpen)

        editor.insertText("x", replacementRange: editor.selectedRange())
        XCTAssertEqual(coordinator.lastKnownMarkdown, "@x")
    }

    // MARK: - `textView(_:doCommandBy:)` priorise le menu « @ » quand il est ouvert

    func test_doCommandBy_delegatesToMentionController_whenMentionMenuOpen() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("@mar", into: editor)
        XCTAssertTrue(controller.isOpen)

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(editor.textStorage?.string, "@mar", "Échap ne doit pas toucher au texte")
    }

    /// Preuve directe de la priorité annoncée par la doc de `Coordinator.
    /// textView(_:doCommandBy:)` : un vrai `SlashController` est attaché en
    /// plus du `MentionController` (pas seulement ce dernier, comme le fait
    /// `makeWiredCoordinator`) — sur une ligne de titre, son correctif
    /// « Retour après un titre » (piège 4) transformerait normalement `⏎` en
    /// un nouveau titre plutôt qu'un paragraphe (voir `Tests/
    /// SlashControllerTests.test_witness_defaultInsertNewline_withoutController_propagatesHeadingType`
    /// pour la mesure du bug qu'il corrige). Ce test vérifie qu'avec le menu
    /// « @ » ouvert, `⏎` applique la mention à la place — sans jamais laisser
    /// `SlashController.handle` s'exécuter.
    func test_doCommandBy_mentionMenuOpen_takesPriorityOverSlashHeadingFix() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, coordinator) = makeWiredEditor(markdown: "## Titre")
        coordinator.slashController = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(nil) },
            presentEmojiPicker: {}
        )
        let controller = MentionController(
            textView: editor,
            panel: MentionPanel(),
            cancelPendingWrite: { [weak coordinator] in coordinator?.cancelPendingWrite() },
            searchCollaborators: { _ in [marie] },
            createCollaborator: { _ in nil }
        )
        coordinator.mentionController = controller

        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        type(" @mar", into: editor)
        XCTAssertTrue(controller.isOpen)

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertFalse(controller.isOpen, "⏎ doit avoir appliqué la mention et fermé le menu, pas déclenché le correctif de titre")
        XCTAssertEqual(
            MarkdownSerializer.serialize(editor.textStorage!),
            "## Titre [@Marie Dupont](\(MentionCatalog.mentionURL(for: marie.id).absoluteString))"
        )
    }

    func test_doCommandBy_withoutMentionController_fallsBackToSlashController() {
        let representable = EditorRepresentable(
            markdown: .constant(""), placeholder: "", features: .full, debounce: 0, readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        let editor = makeEditorTextView()
        editor.delegate = coordinator
        coordinator.textView = editor
        // `mentionController` volontairement non assigné (`mentionSearch` absent).
        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(handled)
    }

    // MARK: - `textViewDidChangeSelection(_:)` délègue aussi au menu « @ »

    func test_textViewDidChangeSelection_closesMentionMenu_whenCursorLeavesTheQuery() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("@mar", into: editor)
        XCTAssertTrue(controller.isOpen)

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: editor))

        XCTAssertFalse(controller.isOpen)
    }

    // MARK: - `dismantleNSView` démonte aussi le contrôleur de mention

    func test_dismantleNSView_teardownsMentionController_andReleasesReference() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("@mar", into: editor)
        XCTAssertTrue(controller.isOpen)

        let scroll = NSScrollView()
        scroll.documentView = editor
        EditorRepresentable.dismantleNSView(scroll, coordinator: coordinator)

        XCTAssertFalse(controller.isOpen, "teardown() doit fermer le menu")
        XCTAssertNil(coordinator.mentionController, "la référence doit être relâchée après démontage")
    }

    // MARK: - Fixtures
    //
    // Le rafraîchissement des closures de recherche/création à chaque rendu
    // (`updateNSView` appelant `MentionController.updateHandlers`) n'est PAS
    // testé ici : `updateNSView(_:context:)` prend un
    // `NSViewRepresentableContext<Coordinator>`, non constructible depuis un
    // test (même contrainte que documentée en tête de `Tests/
    // EditorRepresentableSlashWiringTests.swift`, qui pour cette raison
    // n'appelle jamais `makeNSView`/`updateNSView` directement non plus). Le
    // mécanisme lui-même (`MentionController.updateHandlers` remplace bien
    // les closures utilisées par la suite) est couvert directement, sans
    // passer par `EditorRepresentable`, par
    // `MentionControllerTests.test_updateHandlers_replacesSearchAndCreateClosures`.

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

        let parsed = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(parsed)
        if let storage = editor.textStorage {
            StyleRenderer.applyVisualStyle(to: storage)
        }
        coordinator.lastKnownMarkdown = markdown
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        return (editor, coordinator)
    }

    private func makeWiredCoordinator(
        markdown: String,
        search: @escaping (String) -> [MentionCandidate] = { _ in [] }
    ) -> (EditorTextView, EditorRepresentable.Coordinator, MentionController) {
        let (editor, coordinator) = makeWiredEditor(markdown: markdown)
        let controller = MentionController(
            textView: editor,
            panel: MentionPanel(),
            cancelPendingWrite: { [weak coordinator] in coordinator?.cancelPendingWrite() },
            searchCollaborators: search,
            createCollaborator: { _ in nil }
        )
        coordinator.mentionController = controller
        return (editor, coordinator, controller)
    }

    private func type(_ text: String, into editor: EditorTextView) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    private func makeEditorTextView() -> EditorTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        return EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
    }
}
