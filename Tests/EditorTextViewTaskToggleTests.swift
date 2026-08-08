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

    /// La zone cliquable doit suivre le rect du **texte**
    /// (`lineFragmentUsedRect`), jamais celui du fragment : le fragment
    /// englobe le `paragraphSpacing` que `StyleRenderer.applyBlockSpacing`
    /// pose sous le dernier item d'une liste (10 pt, ou 28 pt au voisinage
    /// d'une carte). La case est peinte en haut de cette zone — centrée sur le
    /// rect *used*, comme le fait déjà `MarkdownLayoutManager.drawMarker` —
    /// donc cliquer dans le **vide** en dessous cochait une case qui n'y était
    /// pas.
    ///
    /// Fixture : une checklist suivie d'une carte, pour que l'écart soit le
    /// plus large (28 pt) et le vide indiscutable.
    func test_clickingInTheGapBelowTheLastItem_doesNotToggle() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire\n\n```swift\nprint(1)\n```")
        let storage = try XCTUnwrap(editor.textStorage)
        let layoutManager = try XCTUnwrap(editor.layoutManager)

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: 0)
        let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        XCTAssertGreaterThan(
            fragmentRect.maxY - usedRect.maxY, 10,
            "prémisse : l'écart inter-blocs large doit bien vivre dans le fragment, sous le texte"
        )

        // Plein milieu du vide : sous le texte, toujours dans le fragment.
        let point = NSPoint(
            x: try markerPoint(in: editor).x,
            y: (usedRect.maxY + fragmentRect.maxY) / 2 + editor.textContainerInset.height
        )
        let didToggle = editor.toggleTaskMarker(at: point)

        XCTAssertFalse(didToggle, "cliquer sous la case, dans l'écart inter-blocs, ne doit rien basculer")
        let info = try XCTUnwrap(storage.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        XCTAssertEqual(info.checked, false, "ne doit pas avoir basculé")
    }

    /// Contrepartie du test précédent : la case elle-même reste cliquable sur
    /// toute la hauteur de son **texte**, y compris quand un écart large est
    /// posé sous son item.
    func test_clickingTheMarkerOfAnItemNextToACard_stillToggles() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire\n\n```swift\nprint(1)\n```")
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let usedRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: layoutManager.glyphIndexForCharacter(at: 0), effectiveRange: nil
        )

        let point = NSPoint(
            x: try markerPoint(in: editor).x,
            y: usedRect.midY + editor.textContainerInset.height
        )
        XCTAssertTrue(editor.toggleTaskMarker(at: point))
    }

    /// Une puce n'est pas une tâche : cliquer sur son marqueur ne doit rien
    /// basculer (il n'y a rien à basculer).
    func test_clickingBulletMarker_doesNotToggle() throws {
        let (editor, _) = makeWiredEditor(markdown: "- puce")

        let didToggle = editor.toggleTaskMarker(at: try markerPoint(in: editor))

        XCTAssertFalse(didToggle)
    }

    /// Lecture seule : basculer une case reste une édition, elle ne doit pas
    /// fonctionner sur un éditeur `isEditable == false`.
    func test_toggling_doesNothingWhenNotEditable() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] à faire")
        editor.isEditable = false

        let didToggle = editor.toggleTaskMarker(at: try markerPoint(in: editor))

        XCTAssertFalse(didToggle)
        let info = try XCTUnwrap(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        XCTAssertEqual(info.checked, false, "ne doit pas avoir basculé en lecture seule")
    }

    // MARK: - Régression : une checklist neuve ne doit pas cocher toute la série

    /// `ListInfo` est `Hashable`, donc `NSAttributedString` fusionne les runs
    /// adjacents de valeur égale : trois items de tâche décochés consécutifs
    /// (état le plus courant — une checklist qu'on vient de créer) ne portent
    /// donc qu'un **unique** run `.mdListInfo` sur les trois lignes. Utiliser
    /// `longestEffectiveRange` pour localiser « l'item cliqué », comme le
    /// faisait la version précédente de `toggleTaskMarker`, renvoyait donc la
    /// plage des *trois* items — et cocher n'importe lequel les cochait tous.
    func test_togglingOneTaskAmongThreeUncheckedTasks_onlyTogglesTheClickedOne() throws {
        let (editor, _) = makeWiredEditor(markdown: "- [ ] un\n- [ ] deux\n- [ ] trois")
        let storage = try XCTUnwrap(editor.textStorage)

        // Prémisse du test : les trois items partagent bien un seul run
        // fusionné — sinon cette fixture ne pourrait pas attraper la
        // régression que ce test vise.
        var mergedRange = NSRange(location: 0, length: 0)
        _ = storage.attribute(
            .mdListInfo, at: 0, longestEffectiveRange: &mergedRange,
            in: NSRange(location: 0, length: storage.length)
        )
        XCTAssertEqual(
            mergedRange, NSRange(location: 0, length: storage.length),
            "prémisse : les trois items décochés doivent fusionner en un seul run mdListInfo"
        )

        let secondLineStart = try lineStart(1, in: editor)
        let thirdLineStart = try lineStart(2, in: editor)

        let didToggle = editor.toggleTaskMarker(at: try markerPoint(in: editor, lineStart: secondLineStart))
        XCTAssertTrue(didToggle)

        let infoOne = try XCTUnwrap(storage.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
        let infoTwo = try XCTUnwrap(storage.attribute(.mdListInfo, at: secondLineStart, effectiveRange: nil) as? ListInfo)
        let infoThree = try XCTUnwrap(storage.attribute(.mdListInfo, at: thirdLineStart, effectiveRange: nil) as? ListInfo)

        XCTAssertEqual(infoOne.checked, false, "« un » ne doit pas avoir basculé")
        XCTAssertEqual(infoTwo.checked, true, "« deux » (celui cliqué) doit avoir basculé")
        XCTAssertEqual(infoThree.checked, false, "« trois » ne doit pas avoir basculé")

        XCTAssertEqual(
            MarkdownSerializer.serialize(storage),
            "- [ ] un\n- [x] deux\n- [ ] trois"
        )
    }

    // MARK: - Undo/redo

    /// ⌘Z doit annuler une bascule de case à cocher — pas rester sans effet
    /// sur elle en tombant sur l'édition précédente sans rapport (mesuré
    /// avant correctif : `storage.addAttribute` direct, sans passer par
    /// `undoManager`, laissait `canUndo == false` juste après une bascule).
    func test_undoingATaskToggle_restoresThePreviousState_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: "- [ ] à faire")
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(editor.toggleTaskMarker(at: try markerPoint(in: editor)))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual((storage.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)?.checked, true)
        XCTAssertEqual(editor.undoManager?.canUndo, true, "la bascule doit s'être enregistrée auprès de l'undo manager")

        editor.undoManager?.undo()
        XCTAssertEqual(
            (storage.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)?.checked, false,
            "⌘Z doit annuler la bascule"
        )
        XCTAssertEqual(MarkdownSerializer.serialize(storage), "- [ ] à faire")

        editor.undoManager?.redo()
        XCTAssertEqual(
            (storage.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)?.checked, true,
            "⇧⌘Z doit rétablir la bascule"
        )
    }

    /// Reproduit exactement la mesure de la revue : frapper du texte (une
    /// édition réelle, qui s'enregistre auprès de `undoManager` via
    /// `insertText`), puis basculer une case. ⌘Z doit annuler la bascule —
    /// l'édition la plus récente — sans toucher à la frappe précédente, sans
    /// rapport. Avant correctif, la bascule ne passait pas du tout par
    /// `undoManager` : ⌘Z retombait alors sur la frappe, annulée à la place
    /// de la bascule, en laissant la case cochée.
    func test_undoAfterTyping_undoesTheToggleFirst_leavingTheTypedTextIntact() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: "- [ ] à faire")
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)

        // Édition réelle : ajoute " svp" à la fin de l'item — un « événement »
        // à part, comme le serait une vraie frappe.
        editor.undoManager?.beginUndoGrouping()
        editor.insertText(" svp", replacementRange: NSRange(location: storage.length, length: 0))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(MarkdownSerializer.serialize(storage), "- [ ] à faire svp")

        // Bascule — un second « événement » distinct, comme un vrai clic.
        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(editor.toggleTaskMarker(at: try markerPoint(in: editor)))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(MarkdownSerializer.serialize(storage), "- [x] à faire svp")

        // Premier ⌘Z : annule la bascule (la plus récente), garde la frappe.
        editor.undoManager?.undo()
        XCTAssertEqual(
            MarkdownSerializer.serialize(storage), "- [ ] à faire svp",
            "le premier ⌘Z doit annuler la bascule, pas la frappe précédente"
        )

        // Deuxième ⌘Z : annule la frappe.
        editor.undoManager?.undo()
        XCTAssertEqual(MarkdownSerializer.serialize(storage), "- [ ] à faire")
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

    /// Comme `makeWiredEditor`, mais attache la vue à une vraie `NSWindow`
    /// (jamais affichée) : `NSResponder.undoManager` renvoie `nil` tant que
    /// la vue n'a pas de fenêtre (vérifié empiriquement — `allowsUndo = true`
    /// seul ne suffit pas), c'est la fenêtre qui fournit paresseusement le
    /// `NSUndoManager` partagé. Nécessaire uniquement pour les tests
    /// d'annulation : les autres n'ont pas besoin d'un vrai undo manager.
    /// La fenêtre est renvoyée à l'appelant pour que celui-ci la garde en vie
    /// (une variable locale du test suffit, `NSWindow.contentView` ne
    /// retient pas son propriétaire) : sans référence forte, elle serait
    /// désallouée par ARC et `editor.window` redeviendrait `nil`.
    private func makeWiredEditorInWindow(markdown: String) -> (EditorTextView, NSWindow) {
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = editor
        // `NSUndoManager.groupsByEvent` (par défaut `true`) ferme
        // automatiquement un groupe d'annulation à la fin de chaque
        // itération de run loop — mécanisme qui suppose une vraie boucle
        // d'événements AppKit en cours, absente dans un test XCTest headless
        // sans `NSApp.run()`. Sans le désactiver, deux actions simulées
        // l'une après l'autre (sans jamais rendre la main au run loop entre
        // les deux) fusionnent dans le même groupe non fermé — mesuré : un
        // ⌘Z les annulait alors *toutes les deux* d'un coup. Les tests
        // délimitent donc chaque action simulée par
        // `beginUndoGrouping()`/`endUndoGrouping()` explicites, à la place.
        editor.undoManager?.groupsByEvent = false
        return (editor, window)
    }

    /// Index (dans `editor.textStorage`) du premier caractère de la ligne
    /// `line` (0-based), en comptant les retours à la ligne réels du
    /// storage.
    private func lineStart(_ line: Int, in editor: EditorTextView) throws -> Int {
        let ns = try XCTUnwrap(editor.textStorage?.string) as NSString
        var index = 0
        for _ in 0..<line {
            let range = ns.range(of: "\n", range: NSRange(location: index, length: ns.length - index))
            guard range.location != NSNotFound else {
                throw XCTSkip("markdown de test insuffisamment long pour la ligne \(line)")
            }
            index = range.location + 1
        }
        return index
    }

    /// Point (coordonnées de la vue) tombant sur le marqueur de la première
    /// ligne. Raccourci pour `markerPoint(in:lineStart:)` avec `lineStart:
    /// 0`, seul cas dont avaient besoin les tests avant la fixture à trois
    /// items.
    private func markerPoint(in editor: EditorTextView) throws -> NSPoint {
        try markerPoint(in: editor, lineStart: 0)
    }

    /// Point (coordonnées de la vue) tombant sur le marqueur de la ligne
    /// commençant à `lineStart` : au milieu verticalement de son fragment de
    /// ligne, à `firstLineHeadIndent - 2` horizontalement — dans la marge,
    /// pas dans le texte. Dérivé de la mise en page réelle plutôt que de
    /// constantes devinées, pour ne pas dépendre d'une métrique de police
    /// précise.
    private func markerPoint(in editor: EditorTextView, lineStart: Int) throws -> NSPoint {
        let storage = try XCTUnwrap(editor.textStorage)
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let paragraphStyle = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil) as? NSParagraphStyle
        )
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        let containerX = max(0, paragraphStyle.firstLineHeadIndent - 2)
        let containerY = lineRect.midY
        return NSPoint(
            x: containerX + editor.textContainerInset.width,
            y: containerY + editor.textContainerInset.height
        )
    }
}
