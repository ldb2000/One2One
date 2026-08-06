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
        let rect = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400)

        XCTAssertEqual(
            rect.maxX, 400 - MermaidSourceLayout.doneButtonTrailingMargin,
            "collé au bord droit du conteneur, pas de la ligne"
        )
        XCTAssertEqual(rect.width, MermaidSourceLayout.doneButtonWidth)
        XCTAssertEqual(rect.height, MermaidSourceLayout.doneButtonHeight)
    }

    func test_doneButtonRect_sitsInTheHeaderStripAboveTheFirstLine() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400)

        XCTAssertLessThanOrEqual(rect.maxY, firstLine.minY, "jamais sous la première ligne de source")
        XCTAssertGreaterThanOrEqual(rect.minY, firstLine.minY - MermaidSourceLayout.headerHeight)
    }

    // MARK: - headerRect

    func test_headerRect_spansTheFullContainerWidth() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400)

        XCTAssertEqual(rect.width, 400)
        XCTAssertEqual(rect.height, MermaidSourceLayout.headerHeight)
        XCTAssertEqual(rect.maxY, firstLine.minY, "directement accolé au-dessus de la première ligne")
    }

    // MARK: - lineNumberOrigin

    func test_lineNumberOrigin_isRightAlignedInsideTheGutter() {
        let lineRect = NSRect(x: 0, y: 50, width: 300, height: 20)
        let numberSize = NSSize(width: 10, height: 12)
        let origin = MermaidSourceLayout.lineNumberOrigin(lineRect: lineRect, numberSize: numberSize)

        XCTAssertEqual(origin.x, MermaidSourceLayout.gutterWidth - 6 - 10)
        XCTAssertLessThan(origin.x + numberSize.width, MermaidSourceLayout.gutterWidth, "reste dans la gouttière, jamais sur le texte")
    }

    func test_lineNumberOrigin_isVerticallyCenteredOnTheLine() {
        let lineRect = NSRect(x: 0, y: 50, width: 300, height: 20)
        let numberSize = NSSize(width: 10, height: 10)
        let origin = MermaidSourceLayout.lineNumberOrigin(lineRect: lineRect, numberSize: numberSize)

        XCTAssertEqual(origin.y, 55, "centré : 50 + (20-10)/2")
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
