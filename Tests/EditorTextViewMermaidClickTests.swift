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

    // MARK: - mermaidErrorActionButtonRange (état 4 — bouton « Ouvrir le source »)

    /// Cliquer sur la pastille « Ouvrir le source » d'un cadre d'erreur
    /// doit renvoyer la plage du bloc — le même geste (ouvrir le bloc) que
    /// n'importe quel autre clic sur le cadre (`mermaidBlockRange`), mais
    /// hit-testé précisément sur le bouton, voir la doc de la fonction.
    func test_clickingTheErrorActionButton_onAClosedErrorBlock_returnsItsRange() throws {
        let (editor, blockRange, image) = try makeWiredEditorWithMermaidErrorBlock(prefix: "intro\n\n")

        let point = try pointInErrorActionButton(forBlockRange: blockRange, image: image, in: editor)
        XCTAssertEqual(editor.mermaidErrorActionButtonRange(at: point), blockRange)
    }

    /// Un clic ailleurs sur le cadre (ex. sur le titre, en haut) ne doit pas
    /// être confondu avec un clic sur le bouton — `mermaidErrorActionButtonRange`
    /// doit rester borné à la pastille, `mermaidBlockRange` prend le relais
    /// pour le reste du cadre (même schéma que `mermaidDoneButtonRange` vs
    /// le texte source d'un bloc ouvert).
    func test_clickingElsewhereOnTheErrorFrame_isNotMistakenForTheActionButton() throws {
        let (editor, blockRange, _) = try makeWiredEditorWithMermaidErrorBlock(prefix: "intro\n\n")

        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        // Près du sommet du cadre (titre « Diagramme invalide »), bien
        // au-dessus de la pastille (posée près du bas, voir
        // `MermaidBlockLayout.errorActionButtonRect`).
        let titlePoint = NSPoint(
            x: firstLineRect.minX + 20 + editor.textContainerInset.width,
            y: firstLineRect.minY + 12 + editor.textContainerInset.height
        )
        XCTAssertNil(editor.mermaidErrorActionButtonRange(at: titlePoint))
    }

    /// Un bloc **ouvert** (curseur dedans) ne peint aucun cadre d'erreur —
    /// le hit-test doit renvoyer `nil`, jamais la géométrie de la dernière
    /// fois qu'il était fermé.
    func test_errorActionButtonRange_onAnOpenBlock_returnsNil() throws {
        let (editor, blockRange, image) = try makeWiredEditorWithMermaidErrorBlock(prefix: "intro\n\n")
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))

        let point = try pointInErrorActionButton(forBlockRange: blockRange, image: image, in: editor)
        XCTAssertNil(editor.mermaidErrorActionButtonRange(at: point))
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

    /// Bâtit un éditeur dont le bloc mermaid est déjà **fermé en erreur**
    /// (cadre teinté, bouton « Ouvrir le source ») — renvoie la vue, la
    /// plage du bloc et l'image du cadre (pour calculer le point à cliquer,
    /// voir `pointInErrorActionButton`).
    ///
    /// Construit le storage à la main, sans passer par `StyleRenderer.
    /// applyVisualStyle` (qui déclencherait un vrai rendu `WKWebView` en
    /// tâche de fond, timing non déterministe — voir la doc de tête de
    /// `StyleRendererMermaidTests` et `makeClosedMermaidStorage`, même
    /// patron ici) : pose directement l'attachment portant le cadre
    /// d'erreur et la géométrie fermée que `StyleRenderer.
    /// applyClosedMermaidGeometry` aurait posées une fois ce cadre livré.
    private func makeWiredEditorWithMermaidErrorBlock(prefix: String) throws -> (EditorTextView, NSRange, NSImage) {
        let markdown = prefix + "```mermaid\ngraph TD\nA-->B\n```"
        let (editor, _) = makeWiredEditor(markdown: markdown, skipInitialStyling: true, attachDelegate: false)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let blockStart = (storage.string as NSString).range(of: "graph TD").location
        var blockRange = NSRange(location: 0, length: 0)
        let blockType = storage.attribute(.mdBlockType, at: blockStart, longestEffectiveRange: &blockRange, in: NSRange(location: 0, length: storage.length)) as? BlockType
        guard blockType == .codeBlock,
              storage.attribute(.mdCodeLanguage, at: blockStart, effectiveRange: nil) as? String == "mermaid"
        else {
            throw XCTSkip("aucun bloc mermaid détecté — prémisse de fixture non remplie")
        }

        let image = MainActor.assumeIsolated {
            MermaidAttachmentFactory.frameImage(
                title: "Diagramme invalide", detail: "Lexical error on line 2. Unrecognized text.",
                borderColor: .systemRed, titleColor: .systemRed,
                tinted: true, actionLabel: MermaidBlockLayout.errorActionLabel
            )
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: blockRange)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: blockRange)

        let ns = storage.string as NSString
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: blockRange, in: ns)
        let firstLineStyle = NSMutableParagraphStyle()
        firstLineStyle.minimumLineHeight = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: image.size)
        storage.addAttribute(.paragraphStyle, value: firstLineStyle, range: firstLine)
        if rest.length > 0 {
            let restStyle = NSMutableParagraphStyle()
            restStyle.maximumLineHeight = MermaidBlockLayout.hiddenLineMaximumHeight
            storage.addAttribute(.paragraphStyle, value: restStyle, range: rest)
        }
        editor.layoutManager?.ensureLayout(for: try XCTUnwrap(editor.textContainer))

        return (editor, blockRange, image)
    }

    /// Reproduit le câblage TextKit + coordinateur de
    /// `EditorRepresentable.makeNSView` (repris de
    /// `EditorTextViewTaskToggleTests`), puis y charge `markdown` via le
    /// pipeline réel (`MarkdownParser` + `StyleRenderer`).
    ///
    /// `skipInitialStyling` : `true` pour ne **pas** appeler `StyleRenderer.
    /// applyVisualStyle` — utilisé par `makeWiredEditorWithMermaidErrorBlock`,
    /// qui pose sa propre géométrie fermée à la main (cadre d'erreur
    /// figé, sans dépendre du timing d'un vrai `WKWebView` déclenché en
    /// tâche de fond par `applyMermaidAttachment`).
    ///
    /// `attachDelegate` : `false` pour ne **pas** poser `coordinator` comme
    /// délégué — sans ça, `setSelectedRange` (ex. simuler l'ouverture d'un
    /// bloc) déclenche `Coordinator.textViewDidChangeSelection` →
    /// `updateMermaidBlockGeometryIfNeeded` → un restylage ciblé réel qui
    /// **écrase** un attachment posé à la main (voir
    /// `makeWiredEditorWithMermaidErrorBlock`) par un nouveau placeholder —
    /// mesuré : un premier essai de `test_errorActionButtonRange_
    /// onAnOpenBlock_returnsNil` passait pour cette mauvaise raison (image
    /// remplacée, donc geométrie différente) plutôt que par le garde-fou
    /// réellement sous test.
    private func makeWiredEditor(markdown: String, skipInitialStyling: Bool = false, attachDelegate: Bool = true) -> (EditorTextView, EditorRepresentable.Coordinator) {
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
        if attachDelegate {
            editor.delegate = coordinator
            coordinator.textView = editor
        }

        let parsed = MarkdownParser.parse(markdown)
        textStorage.setAttributedString(parsed)
        if !skipInitialStyling {
            StyleRenderer.applyVisualStyle(to: textStorage)
        }
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

    /// Point (coordonnées de la vue) au centre du bouton « Ouvrir le
    /// source » du cadre d'erreur peint pour `blockRange` — même calcul de
    /// géométrie que `EditorTextView.mermaidErrorActionButtonRange(at:)`
    /// (position/échelle de l'image dessinée + `MermaidBlockLayout.
    /// errorActionButtonRect`/`imageLocalPoint`, dont ceci est l'inverse),
    /// pour ne jamais dupliquer une géométrie qui pourrait diverger.
    private func pointInErrorActionButton(forBlockRange blockRange: NSRange, image: NSImage, in editor: EditorTextView) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let maxWidth = max(container.size.width - firstLineRect.minX, 0)
        let drawSize = MermaidBlockLayout.fittedSize(for: image.size, maxWidth: maxWidth)
        let drawnRect = NSRect(x: firstLineRect.minX, y: firstLineRect.minY, width: drawSize.width, height: drawSize.height)

        let labelSize = (MermaidBlockLayout.errorActionLabel as NSString).size(withAttributes: [.font: MermaidBlockLayout.errorActionFont])
        let nativeButtonRect = MermaidBlockLayout.errorActionButtonRect(labelSize: labelSize)
        let scale = drawnRect.width / image.size.width

        // Inverse de `MermaidBlockLayout.imageLocalPoint` : natif (bas-gauche)
        // → conteneur (l'axe Y s'inverse, voir sa documentation).
        let containerPoint = NSPoint(
            x: drawnRect.minX + nativeButtonRect.midX * scale,
            y: drawnRect.maxY - nativeButtonRect.midY * scale
        )
        return NSPoint(
            x: containerPoint.x + editor.textContainerInset.width,
            y: containerPoint.y + editor.textContainerInset.height
        )
    }
}
