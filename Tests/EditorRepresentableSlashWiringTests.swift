import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre le câblage de la tâche 6 (`OneToOne/Markdown/Core/EditorRepresentable.swift`) :
/// `SlashController` hébergé par `Coordinator`, court-circuit de
/// `Coordinator.textDidChange` quand le menu absorbe la frappe, délégation
/// de `textView(_:doCommandBy:)` et `textViewDidChangeSelection(_:)`, et
/// démontage via `dismantleNSView`.
///
/// `EditorRepresentable.makeNSView`/`updateNSView` prennent un
/// `NSViewRepresentableContext<Coordinator>`, non constructible depuis un
/// test (cf. `Tests/EditorTextViewPasteTests.swift`) : ces deux méthodes ne
/// sont donc **pas** appelées directement ici. Les tests reconstituent à la
/// main le câblage qu'elles font (même schéma que `Tests/SlashControllerTests.swift`),
/// pour vérifier les effets observables au niveau du `Coordinator` — pas la
/// ligne de code de `makeNSView` elle-même. `dismantleNSView`, en revanche,
/// ne dépend pas de `Context` : il est appelé pour de vrai.
@MainActor
final class EditorRepresentableSlashWiringTests: XCTestCase {

    // MARK: - `Coordinator` héberge bien un `SlashController`

    func test_coordinator_hostsASlashController_onceWired() {
        let (_, coordinator, controller) = makeWiredCoordinator(markdown: "")
        XCTAssertTrue(coordinator.slashController === controller)
    }

    func test_coordinator_hasNoSlashController_beforeWiring() {
        let representable = EditorRepresentable(
            markdown: .constant(""), placeholder: "", features: .full, debounce: 0, readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        XCTAssertNil(coordinator.slashController)
    }

    // MARK: - `Coordinator.textDidChange` court-circuite quand le menu absorbe la frappe

    /// Taper `/` en tête de ligne ouvre le menu (`SlashController.textDidChange()`
    /// renvoie `true`) : `Coordinator.textDidChange` doit alors sortir avant
    /// `ShortcutDetector`, la sérialisation et la programmation du debounce —
    /// mesuré ici par l'absence d'effet sur `hasPendingLocalWrite`/`lastKnownMarkdown`.
    func test_typingSlash_shortCircuitsSerialization_menuAbsorbsTheKeystroke() {
        let (editor, coordinator, _) = makeWiredCoordinator(markdown: "")
        XCTAssertEqual(coordinator.lastKnownMarkdown, "")

        editor.insertText("/", replacementRange: editor.selectedRange())

        XCTAssertFalse(coordinator.hasPendingLocalWrite, "le menu ouvert doit empêcher toute écriture programmée")
        XCTAssertEqual(coordinator.lastKnownMarkdown, "", "la sérialisation ne doit pas avoir tourné")
    }

    /// Témoin : une frappe qui n'ouvre pas le menu (pas de `/`) suit le
    /// chemin normal et met bien à jour `lastKnownMarkdown` — sans ce test,
    /// le précédent pourrait passer pour une tout autre raison (ex. si plus
    /// rien ne mettait jamais `lastKnownMarkdown` à jour).
    func test_witness_typingOrdinaryText_updatesLastKnownMarkdown() {
        let (editor, coordinator, _) = makeWiredCoordinator(markdown: "")
        editor.insertText("a", replacementRange: editor.selectedRange())
        XCTAssertEqual(coordinator.lastKnownMarkdown, "a")
    }

    /// Une fois le menu fermé (Échap), la frappe suivante redevient normale.
    func test_afterMenuCloses_typingResumesNormalSerialization() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        editor.insertText("/", replacementRange: editor.selectedRange())
        XCTAssertTrue(controller.isOpen)

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(controller.isOpen)

        editor.insertText("x", replacementRange: editor.selectedRange())
        XCTAssertEqual(coordinator.lastKnownMarkdown, "/x")
    }

    // MARK: - `textView(_:doCommandBy:)` délègue au contrôleur

    func test_doCommandBy_delegatesToSlashController_whenMenuOpen() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("/head", into: editor)
        XCTAssertTrue(controller.isOpen)

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(editor.textStorage?.string, "/head", "Échap ne doit pas toucher au texte")
    }

    func test_doCommandBy_withoutSlashController_returnsFalse() {
        let (editor, coordinator) = makeWiredEditor(markdown: "")
        // `slashController` volontairement non assigné.
        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(handled)
    }

    // MARK: - `textViewDidChangeSelection(_:)` délègue au contrôleur

    func test_textViewDidChangeSelection_closesMenu_whenCursorLeavesTheQuery() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("/head", into: editor)
        XCTAssertTrue(controller.isOpen)

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: editor))

        XCTAssertFalse(controller.isOpen)
    }

    func test_textViewDidChangeSelection_withoutSlashController_doesNothing() {
        // Ne doit pas planter en l'absence de contrôleur.
        let (editor, coordinator) = makeWiredEditor(markdown: "")
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: editor))
    }

    // MARK: - `dismantleNSView` démonte le contrôleur (pas de `Context` requis, testable directement)

    func test_dismantleNSView_teardownsSlashController_andReleasesReference() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("/head", into: editor)
        XCTAssertTrue(controller.isOpen)

        let scroll = NSScrollView()
        scroll.documentView = editor
        EditorRepresentable.dismantleNSView(scroll, coordinator: coordinator)

        XCTAssertFalse(controller.isOpen, "teardown() doit fermer le menu")
        XCTAssertNil(coordinator.slashController, "la référence doit être relâchée après démontage")
    }

    // MARK: - L'annulation du debounce, câblée comme dans `makeNSView`, coupe réellement la tâche en vol

    /// Reproduit le câblage exact de `makeNSView`
    /// (`cancelPendingWrite: { coordinator?.cancelPendingWrite() }`) plutôt
    /// qu'une espionne inerte, pour vérifier ce que le plan demande
    /// explicitement : que l'annulation « annule réellement la tâche
    /// existante » de `Coordinator.debounceTask`, pas seulement qu'une
    /// closure est appelée. Une écriture différée est d'abord programmée
    /// (comme le ferait une frappe normale via `pushMarkdownToBinding`),
    /// puis le menu s'ouvre : si l'annulation ne fonctionnait pas, le
    /// binding recevrait quand même l'écriture après le délai.
    func test_openingMenu_reallyCancelsThePendingDebouncedBindingWrite() async throws {
        var bound = ""
        let binding = Binding<String>(get: { bound }, set: { bound = $0 })
        let representable = EditorRepresentable(
            markdown: binding, placeholder: "", features: .full, debounce: 0.05, readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        let editor = makeEditorTextView()
        editor.delegate = coordinator
        coordinator.textView = editor
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        // Frappe ordinaire, réelle : `Coordinator.textDidChange` programme
        // lui-même `debounceTask` (chemin normal, pas d'appel manuel à
        // `pushMarkdownToBinding`).
        editor.insertText("a", replacementRange: editor.selectedRange())
        XCTAssertTrue(coordinator.hasPendingLocalWrite)

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

        // Espace puis "/" : déclencheur valide (précédé d'une espace). Chaque
        // frappe reprogramme `debounceTask` avec un nouveau délai de 0.05s à
        // partir de cet instant — c'est ce Task, en vol au moment de l'ouverture
        // du menu, dont l'annulation doit être vérifiée.
        editor.insertText(" ", replacementRange: editor.selectedRange())
        editor.insertText("/", replacementRange: editor.selectedRange())
        XCTAssertTrue(controller.isOpen)

        try await Task.sleep(for: .milliseconds(200)) // largement au-delà du délai de 0.05s

        XCTAssertEqual(bound, "", "la tâche de debounce annulée ne doit jamais écrire dans le binding")
    }

    // MARK: - Fixtures

    /// Reconstitue le câblage TextKit minimal (même schéma que
    /// `Tests/SlashControllerTests.swift`), sans `SlashController`.
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

    /// Idem, avec un `SlashController` assigné à `coordinator.slashController`
    /// exactement comme `makeNSView` le fait (même construction, mêmes
    /// closures inertes que `Tests/SlashControllerTests.swift`).
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

    /// Simule une frappe caractère par caractère : chaque caractère passe par
    /// `insertText`, qui déclenche pour de vrai le cycle délégué AppKit
    /// (`shouldChangeTextIn`/`textDidChange`) sur le `Coordinator` réellement
    /// branché comme `delegate` — donc, avec le câblage de cette tâche,
    /// `Coordinator.textDidChange` appelle lui-même `slashController.textDidChange()`.
    /// Contrairement à `Tests/SlashControllerTests.swift`, aucun appel manuel
    /// à `controller.textDidChange()` n'est nécessaire ici : c'est précisément
    /// ce déclenchement automatique que cette classe de tests vérifie.
    /// Insérer la chaîne entière d'un coup ne reproduirait pas cette
    /// granularité : la détection du `/` regarde le caractère juste avant le
    /// curseur à chaque frappe, pas la fin d'une insertion groupée.
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
