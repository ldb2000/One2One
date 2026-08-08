import XCTest
import AppKit
@testable import OneToOne

/// `MermaidSourceLayout` est de la géométrie pure (état 3 — bloc mermaid
/// ouvert, source en édition) — même patron que `MermaidBlockLayoutTests`
/// pour l'état fermé : aucune vue vivante nécessaire.
///
/// Les bornes sont fabriquées par `sourceTextBoundsForTesting` : le type
/// `SourceTextBounds` n'a pas de constructeur public, précisément pour
/// qu'aucun appelant ne puisse y glisser un rect de fragment (voir sa doc).
/// La suite se termine par des tests de **mise en page réelle**, seuls
/// capables d'attraper une erreur d'ancrage — les relations algébriques
/// ci-dessous, elles, restaient vraies avec le mauvais rect.
final class MermaidSourceLayoutTests: XCTestCase {

    /// Bornes d'un bloc de deux lignes de source, comme si TextKit les avait
    /// mesurées : texte de 100 à 160.
    private let bounds = MermaidSourceLayout.sourceTextBoundsForTesting(top: 100, bottom: 160)

    // MARK: - doneButtonRect

    func test_doneButtonRect_isAlignedToTheRightEdgeOfTheContainer() {
        let rect = MermaidSourceLayout.doneButtonRect(above: bounds, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(
            rect.maxX, 400 - MermaidSourceLayout.doneButtonTrailingMargin,
            "collé au bord droit du conteneur, pas de la ligne"
        )
        XCTAssertEqual(rect.width, MermaidSourceLayout.doneButtonWidth)
        XCTAssertEqual(rect.height, MermaidSourceLayout.doneButtonHeight)
    }

    func test_doneButtonRect_sitsInTheHeaderStripAboveTheFirstLine() {
        let rect = MermaidSourceLayout.doneButtonRect(above: bounds, containerWidth: 400, previewHeight: 0)

        XCTAssertGreaterThanOrEqual(rect.minY, bounds.top - MermaidSourceLayout.bodyTopPadding - MermaidSourceLayout.headerHeight)
        XCTAssertLessThanOrEqual(rect.maxY, bounds.top - MermaidSourceLayout.bodyTopPadding)
    }

    // MARK: - headerRect

    func test_headerRect_spansTheFullContainerWidth() {
        let rect = MermaidSourceLayout.headerRect(above: bounds, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(rect.width, 400)
        XCTAssertEqual(rect.height, MermaidSourceLayout.headerHeight)
        XCTAssertEqual(rect.minY, bounds.top - MermaidSourceLayout.bodyTopPadding - MermaidSourceLayout.headerHeight)
    }

    func test_frameRect_wrapsHeaderCodeAndBottomPadding() {
        let frame = MermaidSourceLayout.frameRect(
            textBounds: bounds,
            containerWidth: 400,
            previewHeight: 0
        )
        let header = MermaidSourceLayout.headerRect(above: bounds, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(frame.minY, header.minY)
        XCTAssertEqual(frame.maxY, bounds.bottom + MermaidSourceLayout.bodyBottomPadding)
        XCTAssertEqual(frame.width, 400)
    }

    // MARK: - lineNumberOrigin

    func test_lineNumberOrigin_isRightAlignedInsideTheGutter() {
        let lineRect = NSRect(x: 0, y: 50, width: 300, height: 20)
        let numberSize = NSSize(width: 10, height: 12)
        let origin = MermaidSourceLayout.lineNumberOrigin(usedRect: lineRect, numberSize: numberSize)

        XCTAssertEqual(origin.x, MermaidSourceLayout.gutterWidth - 7 - 10)
        XCTAssertLessThan(origin.x + numberSize.width, MermaidSourceLayout.gutterWidth, "reste dans la gouttière, jamais sur le texte")
    }

    func test_lineNumberOrigin_isVerticallyCenteredOnTheLine() {
        let lineRect = NSRect(x: 0, y: 50, width: 300, height: 20)
        let numberSize = NSSize(width: 10, height: 10)
        let origin = MermaidSourceLayout.lineNumberOrigin(usedRect: lineRect, numberSize: numberSize)

        XCTAssertEqual(origin.y, 55, "centré : 50 + (20-10)/2")
    }

    func test_sourceLineRect_matchesTheNormalTextLine() {
        let line = NSRect(x: 0, y: 20, width: 300, height: 63)
        let source = MermaidSourceLayout.sourceLineRect(for: 0, usedRect: line)

        XCTAssertEqual(source, line)
    }

    // MARK: - Bande d'aperçu figé (bloc ouvert)

    /// Sans image livrée par le rendu, pas de bande : le cadre garde
    /// exactement l'allure qu'il avait avant ce chantier (en-tête + source).
    func test_previewHeight_withoutAnImage_isZero() {
        XCTAssertEqual(MermaidSourceLayout.previewHeight(forAttachmentSize: nil, containerWidth: 400), 0)
        XCTAssertEqual(MermaidSourceLayout.previewHeight(forAttachmentSize: .zero, containerWidth: 400), 0)
    }

    /// Un diagramme plus haut que le plafond est réduit à `previewMaximumHeight` :
    /// sans ça, une carte de 450 pt repousserait le source hors de l'écran
    /// pendant qu'on le tape.
    func test_previewHeight_capsATallDiagram() {
        let height = MermaidSourceLayout.previewHeight(
            forAttachmentSize: NSSize(width: 300, height: 900), containerWidth: 400
        )
        XCTAssertEqual(height, MermaidSourceLayout.previewMaximumHeight + 2 * MermaidSourceLayout.previewVerticalPadding)
    }

    func test_previewHeight_keepsASmallDiagramAtItsRealHeight() {
        let height = MermaidSourceLayout.previewHeight(
            forAttachmentSize: NSSize(width: 300, height: 100), containerWidth: 400
        )
        XCTAssertEqual(height, 100 + 2 * MermaidSourceLayout.previewVerticalPadding)
    }

    // MARK: - previewHeight(in:blockRange:containerWidth:)

    /// Point d'entrée **unique** utilisé par le dessin et le hit-test : doit
    /// renvoyer exactement ce que renvoie `previewHeight(forAttachmentSize:
    /// containerWidth:)` pour la taille de l'image portée par
    /// `.mdMermaidAttachment` sur le bloc — jamais un calcul recopié à la
    /// main qui pourrait diverger de l'original.
    func test_previewHeightInStorage_matchesPreviewHeightForTheAttachmentImageSize() {
        let storage = NSTextStorage(string: "graph TD\nA-->B")
        let blockRange = NSRange(location: 0, length: storage.length)
        let imageSize = NSSize(width: 300, height: 100)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        image.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.image = image
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: blockRange)

        let height = MermaidSourceLayout.previewHeight(in: storage, blockRange: blockRange, containerWidth: 400)
        let expected = MermaidSourceLayout.previewHeight(forAttachmentSize: imageSize, containerWidth: 400)

        XCTAssertEqual(height, expected)
    }

    /// Bloc sans `.mdMermaidAttachment` (pas encore stylé, ou attribut
    /// retiré) : pas de bande, comme si l'image n'existait pas.
    func test_previewHeightInStorage_withoutTheAttribute_isZero() {
        let storage = NSTextStorage(string: "graph TD\nA-->B")
        let blockRange = NSRange(location: 0, length: storage.length)

        XCTAssertEqual(MermaidSourceLayout.previewHeight(in: storage, blockRange: blockRange, containerWidth: 400), 0)
    }

    /// L'attribut est typé `Any` dans `NSAttributedString` : rien n'empêche
    /// un objet qui n'est pas un `NSTextAttachment` de s'y retrouver. Le cast
    /// raté doit renvoyer 0, jamais crasher.
    func test_previewHeightInStorage_withANonAttachmentValue_isZeroWithoutCrashing() {
        let storage = NSTextStorage(string: "graph TD\nA-->B")
        let blockRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.mdMermaidAttachment, value: "not an attachment", range: blockRange)

        XCTAssertEqual(MermaidSourceLayout.previewHeight(in: storage, blockRange: blockRange, containerWidth: 400), 0)
    }

    /// Le rendu asynchrone n'a pas encore livré d'image (`attachment.image
    /// == nil`) : pas de bande tant qu'il n'y a rien à montrer.
    func test_previewHeightInStorage_withAnAttachmentWithoutAnImage_isZero() {
        let storage = NSTextStorage(string: "graph TD\nA-->B")
        let blockRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.mdMermaidAttachment, value: NSTextAttachment(), range: blockRange)

        XCTAssertEqual(MermaidSourceLayout.previewHeight(in: storage, blockRange: blockRange, containerWidth: 400), 0)
    }

    /// `blockRange.location` négatif ou hors bornes ne doit jamais être
    /// transmis à `storage.attribute(at:effectiveRange:)` — sinon crash.
    func test_previewHeightInStorage_withAnOutOfBoundsLocation_isZeroWithoutReadingOutOfBounds() {
        let storage = NSTextStorage(string: "graph TD\nA-->B")

        XCTAssertEqual(
            MermaidSourceLayout.previewHeight(
                in: storage, blockRange: NSRange(location: -1, length: 0), containerWidth: 400
            ),
            0
        )
        XCTAssertEqual(
            MermaidSourceLayout.previewHeight(
                in: storage, blockRange: NSRange(location: storage.length, length: 0), containerWidth: 400
            ),
            0
        )
    }

    /// L'image est réduite **deux fois** : d'abord à la largeur du conteneur,
    /// puis au plafond de hauteur. Sans la première réduction, la hauteur
    /// réservée serait celle de l'image native alors que le dessin, lui,
    /// tiendrait dans le conteneur — un vide sous l'aperçu.
    func test_previewImageSize_fitsTheContainerWidthBeforeCappingTheHeight() {
        let size = MermaidSourceLayout.previewImageSize(
            forAttachmentSize: NSSize(width: 800, height: 200), containerWidth: 400
        )
        XCTAssertEqual(size.width, 400, accuracy: 0.001)
        XCTAssertEqual(size.height, 100, accuracy: 0.001, "ratio conservé : 200 × (400/800)")
    }

    func test_previewImageSize_neverEnlargesASmallDiagram() {
        let size = MermaidSourceLayout.previewImageSize(
            forAttachmentSize: NSSize(width: 120, height: 80), containerWidth: 400
        )
        XCTAssertEqual(size, NSSize(width: 120, height: 80))
    }

    func test_previewRect_isHorizontallyCenteredUnderTheHeader() {
        let tall = MermaidSourceLayout.sourceTextBoundsForTesting(top: 400, bottom: 460)
        let imageSize = NSSize(width: 200, height: 100)
        let previewHeight = MermaidSourceLayout.previewHeight(forAttachmentSize: imageSize, containerWidth: 400)

        let rect = MermaidSourceLayout.previewRect(above: tall, containerWidth: 400, imageSize: imageSize)
        let header = MermaidSourceLayout.headerRect(above: tall, containerWidth: 400, previewHeight: previewHeight)

        XCTAssertEqual(rect.midX, 200, accuracy: 0.001, "centré dans le conteneur")
        XCTAssertEqual(rect.minY, header.maxY + MermaidSourceLayout.previewVerticalPadding, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
    }

    func test_previewRect_withoutAnImage_isEmpty() {
        let rect = MermaidSourceLayout.previewRect(above: bounds, containerWidth: 400, imageSize: nil)

        XCTAssertTrue(rect.isEmpty)
    }

    /// L'en-tête reste **en haut** du cadre : la bande d'aperçu s'insère
    /// entre lui et le source, elle ne le pousse pas dedans. C'est ce qui
    /// empêche l'en-tête de paraître coiffer la carte du bloc précédent.
    func test_headerAndDoneButton_shiftUpByTheWholePreviewBand() {
        let band: CGFloat = 160

        let header = MermaidSourceLayout.headerRect(above: bounds, containerWidth: 400, previewHeight: band)
        let flat = MermaidSourceLayout.headerRect(above: bounds, containerWidth: 400, previewHeight: 0)
        XCTAssertEqual(header.minY, flat.minY - band, accuracy: 0.001)
        XCTAssertEqual(header.height, MermaidSourceLayout.headerHeight)

        let button = MermaidSourceLayout.doneButtonRect(above: bounds, containerWidth: 400, previewHeight: band)
        XCTAssertGreaterThanOrEqual(button.minY, header.minY)
        XCTAssertLessThanOrEqual(button.maxY, header.maxY, "le bouton reste dans sa bande, jamais sur l'aperçu")
    }

    func test_frameRect_wrapsTheWholeBandIncludingThePreview() {
        let band: CGFloat = 160

        let frame = MermaidSourceLayout.frameRect(
            textBounds: bounds, containerWidth: 400, previewHeight: band
        )
        let header = MermaidSourceLayout.headerRect(above: bounds, containerWidth: 400, previewHeight: band)

        XCTAssertEqual(frame.minY, header.minY)
        XCTAssertEqual(frame.maxY, bounds.bottom + MermaidSourceLayout.bodyBottomPadding)
    }

    /// Le corps (fond du source + gouttière) commence **sous** la bande
    /// d'aperçu, jamais sous l'en-tête seul — sinon la gouttière de numéros
    /// de ligne serait peinte derrière le diagramme.
    func test_bodyRect_startsBelowThePreviewBand() {
        let band: CGFloat = 160

        let body = MermaidSourceLayout.bodyRect(
            textBounds: bounds, containerWidth: 400, previewHeight: band
        )
        let header = MermaidSourceLayout.headerRect(above: bounds, containerWidth: 400, previewHeight: band)

        XCTAssertEqual(body.minY, header.maxY + band, accuracy: 0.001)
    }

    // MARK: - Mise en page réelle (piège `lineFragmentRect` vs `lineFragmentUsedRect`)

    /// Le cadre d'un bloc mermaid ouvert ne doit jamais remonter au-dessus du
    /// **bas du texte** du bloc précédent.
    ///
    /// Tous les autres tests de cette suite sont algébriquement
    /// auto-cohérents (`header.minY == flat.minY - band`) : aucun ne met en
    /// page un storage réel, et c'est pour ça qu'ils ont laissé passer un
    /// ancrage sur le mauvais rect. Celui-ci part d'un éditeur réellement mis
    /// en page (`ensureLayout`), donc de la géométrie que TextKit calcule
    /// vraiment.
    func test_openBlockFrame_neverRisesAboveThePreviousBlock() throws {
        let fixture = try makeLaidOutOpenMermaidBlock()
        let geometry = openBlockGeometry(fixture)

        XCTAssertGreaterThan(fixture.previewBand, 0, "prémisse : l'attachment porte une image, donc une bande d'aperçu")
        XCTAssertGreaterThanOrEqual(
            geometry.frame.minY, fixture.previousBlockTextBottom,
            "le cadre déborde sur le bloc précédent : la bande est ancrée sur le rect de fragment "
            + "(qui inclut `paragraphSpacingBefore`) au lieu du rect *used* (sommet du texte)"
        )
    }

    /// L'en-tête et l'aperçu vivent dans l'espace réservé au-dessus du source,
    /// entre le bloc précédent et la première ligne de code — jamais par-dessus
    /// l'un ou l'autre.
    func test_openBlockHeaderAndPreview_sitBetweenThePreviousBlockAndTheSource() throws {
        let fixture = try makeLaidOutOpenMermaidBlock()
        let geometry = openBlockGeometry(fixture)

        XCTAssertEqual(geometry.header.minY, geometry.frame.minY, accuracy: 0.001, "l'en-tête coiffe le cadre")
        XCTAssertGreaterThanOrEqual(
            geometry.header.minY, fixture.previousBlockTextBottom,
            "l'en-tête ne doit pas coiffer le bloc précédent"
        )
        XCTAssertLessThanOrEqual(
            geometry.header.maxY, fixture.sourceTextTop,
            "l'en-tête est au-dessus de la première ligne de source, jamais dessus"
        )
        XCTAssertGreaterThanOrEqual(geometry.preview.minY, geometry.header.maxY)
        XCTAssertLessThanOrEqual(
            geometry.preview.maxY, fixture.sourceTextTop,
            "l'aperçu reste au-dessus du source"
        )
    }

    /// Le cadre contient tout le source et rien de plus que ses paddings : le
    /// bas suit le **texte** de la dernière ligne, pas son fragment — sinon
    /// l'écart de 28 pt qu'`StyleRenderer.applyBlockSpacing` pose pour
    /// *séparer* la carte du bloc suivant se retrouve *dans* le cadre (38 pt
    /// de vide en bas, écart visible nul en dessous).
    func test_openBlockFrame_keepsTheBlockSpacingOutsideTheCard() throws {
        let fixture = try makeLaidOutOpenMermaidBlock()
        let geometry = openBlockGeometry(fixture)

        XCTAssertEqual(
            geometry.frame.maxY - fixture.sourceTextBottom,
            MermaidSourceLayout.bodyBottomPadding,
            accuracy: 0.001,
            "sous la dernière ligne de source, le cadre ne garde que son padding"
        )
        XCTAssertLessThanOrEqual(
            geometry.frame.maxY, fixture.nextBlockTextTop,
            "le cadre ne mord pas sur le bloc suivant"
        )
        XCTAssertGreaterThan(
            fixture.nextBlockTextTop - geometry.frame.maxY, 0,
            "un écart visible subsiste entre la carte et le bloc suivant"
        )
        XCTAssertLessThanOrEqual(
            geometry.body.maxY, geometry.frame.maxY,
            "la zone de source reste dans le cadre"
        )
    }

    // MARK: - Fixture de mise en page

    /// Un bloc mermaid **ouvert** (curseur dedans, image d'aperçu livrée),
    /// précédé et suivi d'un paragraphe, réellement mis en page.
    ///
    /// Construit sans `StyleRenderer.applyVisualStyle` : sur un bloc mermaid,
    /// elle lancerait un vrai `WKWebView` en tâche de fond (voir la doc de
    /// tête de `StyleRendererMermaidTests`). Les attributs posés ici sont
    /// exactement ceux du chemin de production —
    /// `applyOpenMermaidGeometryForTesting` pour la géométrie ouverte, et à la
    /// main l'écart de bloc qu'`applyBlockSpacing` pose ensuite sur le dernier
    /// paragraphe de chaque bloc voisin d'une carte.
    private struct LaidOutOpenMermaidBlock {
        let storage: NSTextStorage
        let layoutManager: NSLayoutManager
        let containerWidth: CGFloat
        let blockRange: NSRange
        let imageSize: NSSize
        let previewBand: CGFloat
        /// Bas du **texte** du paragraphe qui précède la carte.
        let previousBlockTextBottom: CGFloat
        /// Sommet du **texte** du paragraphe qui suit la carte.
        let nextBlockTextTop: CGFloat
        let sourceTextTop: CGFloat
        let sourceTextBottom: CGFloat
    }

    private func makeLaidOutOpenMermaidBlock(
        imageSize: NSSize = NSSize(width: 300, height: 150)
    ) throws -> LaidOutOpenMermaidBlock {
        let markdown = "intro\n\n```mermaid\ngraph TD\nA-->B\n```\n\nsuite"
        let containerWidth: CGFloat = 400

        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: containerWidth, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 100), textContainer: container)

        let ns = storage.string as NSString
        let blockStart = ns.range(of: "graph TD").location
        guard blockStart != NSNotFound else { throw XCTSkip("bloc mermaid introuvable — prémisse de fixture non remplie") }
        var blockRange = NSRange(location: 0, length: 0)
        let blockType = storage.attribute(
            .mdBlockType, at: blockStart, longestEffectiveRange: &blockRange,
            in: NSRange(location: 0, length: storage.length)
        ) as? BlockType
        guard blockType == .codeBlock,
              storage.attribute(.mdCodeLanguage, at: blockStart, effectiveRange: nil) as? String == "mermaid"
        else { throw XCTSkip("bloc mermaid introuvable — prémisse de fixture non remplie") }

        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.image = image
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: blockRange)

        // Curseur dans le bloc : c'est ce qui le rend « ouvert ».
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: blockRange,
            attachmentImageSize: imageSize, containerWidth: containerWidth
        )

        // Ce qu'`applyBlockSpacing` pose ensuite : l'écart large sur le dernier
        // paragraphe de tout bloc voisin d'une carte — donc sur « intro » comme
        // sur la dernière ligne du bloc mermaid lui-même (`max` avec le
        // `bodyBottomPadding` que la géométrie ouverte vient d'y poser).
        addParagraphSpacing(BlockGutterLayout.cardBlockSpacing, in: storage, atParagraphContaining: ns.range(of: "intro").location)
        addParagraphSpacing(BlockGutterLayout.cardBlockSpacing, in: storage, atParagraphContaining: NSMaxRange(blockRange) - 1)

        layoutManager.ensureLayout(for: container)

        return LaidOutOpenMermaidBlock(
            storage: storage,
            layoutManager: layoutManager,
            containerWidth: containerWidth,
            blockRange: blockRange,
            imageSize: imageSize,
            previewBand: MermaidSourceLayout.previewHeight(
                in: storage, blockRange: blockRange, containerWidth: containerWidth
            ),
            previousBlockTextBottom: usedRect(at: ns.range(of: "intro").location, layoutManager).maxY,
            nextBlockTextTop: usedRect(at: ns.range(of: "suite").location, layoutManager).minY,
            sourceTextTop: usedRect(at: blockRange.location, layoutManager).minY,
            sourceTextBottom: usedRect(at: max(blockRange.location, NSMaxRange(blockRange) - 1), layoutManager).maxY
        )
    }

    /// `paragraphSpacing = max(existant, spacing)` sur le paragraphe portant
    /// `location` — la règle exacte d'`StyleRenderer.applyBlockSpacing`.
    private func addParagraphSpacing(_ spacing: CGFloat, in storage: NSTextStorage, atParagraphContaining location: Int) {
        let paragraph = (storage.string as NSString).lineRange(for: NSRange(location: location, length: 0))
        let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.paragraphSpacing = max(style.paragraphSpacing, spacing)
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    /// Rect du **texte** de la ligne portant le caractère `location` —
    /// `lineFragmentUsedRect`, jamais `lineFragmentRect` : c'est toute la
    /// différence que ces tests mesurent.
    private func usedRect(at location: Int, _ layoutManager: NSLayoutManager) -> NSRect {
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }

    /// Reproduit **exactement** l'appel que fait le dessin
    /// (`MarkdownLayoutManager.drawOpenMermaidBackgrounds`). Avant ce
    /// correctif, ce helper lisait `lineFragmentRect` pour la première et la
    /// dernière ligne, comme le faisait la production ; c'est la seule chose
    /// qui a changé ici — les assertions des trois tests ci-dessus sont
    /// restées mot pour mot les mêmes.
    private func openBlockGeometry(
        _ fixture: LaidOutOpenMermaidBlock
    ) -> (frame: NSRect, header: NSRect, preview: NSRect, body: NSRect) {
        let textBounds = MermaidSourceLayout.textBounds(
            forBlockRange: fixture.blockRange, layoutManager: fixture.layoutManager
        )

        return (
            frame: MermaidSourceLayout.frameRect(
                textBounds: textBounds,
                containerWidth: fixture.containerWidth, previewHeight: fixture.previewBand
            ),
            header: MermaidSourceLayout.headerRect(
                above: textBounds, containerWidth: fixture.containerWidth, previewHeight: fixture.previewBand
            ),
            preview: MermaidSourceLayout.previewRect(
                above: textBounds, containerWidth: fixture.containerWidth, imageSize: fixture.imageSize
            ),
            body: MermaidSourceLayout.bodyRect(
                textBounds: textBounds,
                containerWidth: fixture.containerWidth, previewHeight: fixture.previewBand
            )
        )
    }

    // MARK: - Constantes de contrat (état 3 : interligne normal, jamais 110pt/ligne)

    /// Preuve directe : l'interligne d'un bloc ouvert doit rester proche de
    /// la normale (1.0–2.0), jamais un multiplicateur qui reproduirait
    /// l'ancien défaut (une ligne de ~14pt gonflée à 110pt, soit un
    /// multiplicateur d'environ 8).
    func test_lineHeightMultiple_staysCloseToNormalReading() {
        XCTAssertGreaterThan(MermaidSourceLayout.lineHeightMultiple, 1.0)
        XCTAssertLessThan(MermaidSourceLayout.lineHeightMultiple, 2.0)
    }
}
