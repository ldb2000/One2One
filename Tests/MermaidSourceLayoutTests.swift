import XCTest
import AppKit
@testable import OneToOne

/// `MermaidSourceLayout` est de la géométrie pure (état 3 — bloc mermaid
/// ouvert, source en édition) — même patron que `MermaidBlockLayoutTests`
/// pour l'état fermé : aucune vue vivante nécessaire.
final class MermaidSourceLayoutTests: XCTestCase {

    // MARK: - doneButtonRect

    func test_doneButtonRect_isAlignedToTheRightEdgeOfTheContainer() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(
            rect.maxX, 400 - MermaidSourceLayout.doneButtonTrailingMargin,
            "collé au bord droit du conteneur, pas de la ligne"
        )
        XCTAssertEqual(rect.width, MermaidSourceLayout.doneButtonWidth)
        XCTAssertEqual(rect.height, MermaidSourceLayout.doneButtonHeight)
    }

    func test_doneButtonRect_sitsInTheHeaderStripAboveTheFirstLine() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertGreaterThanOrEqual(rect.minY, firstLine.minY - MermaidSourceLayout.bodyTopPadding - MermaidSourceLayout.headerHeight)
        XCTAssertLessThanOrEqual(rect.maxY, firstLine.minY - MermaidSourceLayout.bodyTopPadding)
    }

    // MARK: - headerRect

    func test_headerRect_spansTheFullContainerWidth() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(rect.width, 400)
        XCTAssertEqual(rect.height, MermaidSourceLayout.headerHeight)
        XCTAssertEqual(rect.minY, firstLine.minY - MermaidSourceLayout.bodyTopPadding - MermaidSourceLayout.headerHeight)
    }

    func test_frameRect_wrapsHeaderCodeAndBottomPadding() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let lastLine = NSRect(x: 0, y: 140, width: 300, height: 20)

        let frame = MermaidSourceLayout.frameRect(
            firstLineRect: firstLine,
            lastLineRect: lastLine,
            containerWidth: 400,
            previewHeight: 0
        )
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(frame.minY, header.minY)
        XCTAssertEqual(frame.maxY, lastLine.maxY + MermaidSourceLayout.bodyBottomPadding)
        XCTAssertEqual(frame.width, 400)
    }

    // MARK: - lineNumberOrigin

    func test_lineNumberOrigin_isRightAlignedInsideTheGutter() {
        let lineRect = NSRect(x: 0, y: 50, width: 300, height: 20)
        let numberSize = NSSize(width: 10, height: 12)
        let origin = MermaidSourceLayout.lineNumberOrigin(lineRect: lineRect, numberSize: numberSize)

        XCTAssertEqual(origin.x, MermaidSourceLayout.gutterWidth - 7 - 10)
        XCTAssertLessThan(origin.x + numberSize.width, MermaidSourceLayout.gutterWidth, "reste dans la gouttière, jamais sur le texte")
    }

    func test_lineNumberOrigin_isVerticallyCenteredOnTheLine() {
        let lineRect = NSRect(x: 0, y: 50, width: 300, height: 20)
        let numberSize = NSSize(width: 10, height: 10)
        let origin = MermaidSourceLayout.lineNumberOrigin(lineRect: lineRect, numberSize: numberSize)

        XCTAssertEqual(origin.y, 55, "centré : 50 + (20-10)/2")
    }

    func test_sourceLineRect_matchesTheNormalTextLine() {
        let line = NSRect(x: 0, y: 20, width: 300, height: 63)
        let source = MermaidSourceLayout.sourceLineRect(for: 0, lineFragmentRect: line)

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
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let imageSize = NSSize(width: 200, height: 100)
        let previewHeight = MermaidSourceLayout.previewHeight(forAttachmentSize: imageSize, containerWidth: 400)

        let rect = MermaidSourceLayout.previewRect(above: firstLine, containerWidth: 400, imageSize: imageSize)
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: previewHeight)

        XCTAssertEqual(rect.midX, 200, accuracy: 0.001, "centré dans le conteneur")
        XCTAssertEqual(rect.minY, header.maxY + MermaidSourceLayout.previewVerticalPadding, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
    }

    func test_previewRect_withoutAnImage_isEmpty() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let rect = MermaidSourceLayout.previewRect(above: firstLine, containerWidth: 400, imageSize: nil)

        XCTAssertTrue(rect.isEmpty)
    }

    /// L'en-tête reste **en haut** du cadre : la bande d'aperçu s'insère
    /// entre lui et le source, elle ne le pousse pas dedans. C'est ce qui
    /// empêche l'en-tête de paraître coiffer la carte du bloc précédent.
    func test_headerAndDoneButton_shiftUpByTheWholePreviewBand() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let band: CGFloat = 160

        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: band)
        let flat = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: 0)
        XCTAssertEqual(header.minY, flat.minY - band, accuracy: 0.001)
        XCTAssertEqual(header.height, MermaidSourceLayout.headerHeight)

        let button = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400, previewHeight: band)
        XCTAssertGreaterThanOrEqual(button.minY, header.minY)
        XCTAssertLessThanOrEqual(button.maxY, header.maxY, "le bouton reste dans sa bande, jamais sur l'aperçu")
    }

    func test_frameRect_wrapsTheWholeBandIncludingThePreview() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let lastLine = NSRect(x: 0, y: 440, width: 300, height: 20)
        let band: CGFloat = 160

        let frame = MermaidSourceLayout.frameRect(
            firstLineRect: firstLine, lastLineRect: lastLine, containerWidth: 400, previewHeight: band
        )
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: band)

        XCTAssertEqual(frame.minY, header.minY)
        XCTAssertEqual(frame.maxY, lastLine.maxY + MermaidSourceLayout.bodyBottomPadding)
    }

    /// Le corps (fond du source + gouttière) commence **sous** la bande
    /// d'aperçu, jamais sous l'en-tête seul — sinon la gouttière de numéros
    /// de ligne serait peinte derrière le diagramme.
    func test_bodyRect_startsBelowThePreviewBand() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let lastLine = NSRect(x: 0, y: 440, width: 300, height: 20)
        let band: CGFloat = 160

        let body = MermaidSourceLayout.bodyRect(
            firstLineRect: firstLine, lastLineRect: lastLine, containerWidth: 400, previewHeight: band
        )
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: band)

        XCTAssertEqual(body.minY, header.maxY + band, accuracy: 0.001)
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
