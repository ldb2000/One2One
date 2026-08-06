import XCTest
import AppKit
@testable import OneToOne

/// `MermaidBlockLayout` est de la géométrie pure — aucun `WKWebView`, aucun
/// rendu réel : entièrement testable en tête, contrairement au rendu mermaid
/// lui-même (voir `MermaidRenderer`, dont le rendu web asynchrone n'est pas
/// pilotable en test headless).
///
/// Couvre le cœur du défaut corrigé par ce chantier : la hauteur du cadre
/// fermé (`closedFrameHeight`/`closedFrameWidth`) suit l'image de
/// l'attachment, jamais une réservation étalée sur le nombre de lignes du
/// source (l'ancien `reservedHeight / lineCount`, 220pt pour 2 lignes de
/// source = 110pt la ligne).
final class MermaidBlockLayoutTests: XCTestCase {

    // MARK: - lineCount

    func test_lineCount_singleLine_isOne() {
        XCTAssertEqual(MermaidBlockLayout.lineCount(in: "graph TD"), 1)
    }

    func test_lineCount_countsNewlines() {
        XCTAssertEqual(MermaidBlockLayout.lineCount(in: "a\nb\nc"), 3)
    }

    /// Un bloc édité jusqu'à le vider ne doit pas produire de division par
    /// zéro ailleurs (gouttière de numéros de ligne, `MermaidSourceLayout`).
    func test_lineCount_emptySource_isAtLeastOne() {
        XCTAssertEqual(MermaidBlockLayout.lineCount(in: ""), 1)
    }

    // MARK: - closedFrameHeight — le cœur du défaut corrigé

    /// Sans image connue (rendu web pas encore livré), la hauteur retombe
    /// sur `placeholderHeight` — jamais sur une valeur dérivée du nombre de
    /// lignes de source.
    func test_closedFrameHeight_noImage_isPlaceholderHeight() {
        XCTAssertEqual(MermaidBlockLayout.closedFrameHeight(forAttachmentSize: nil), MermaidBlockLayout.placeholderHeight)
    }

    func test_closedFrameHeight_degenerateSize_isPlaceholderHeight() {
        XCTAssertEqual(
            MermaidBlockLayout.closedFrameHeight(forAttachmentSize: NSSize(width: 100, height: 0)),
            MermaidBlockLayout.placeholderHeight
        )
    }

    /// Avec une image connue, la hauteur suit **cette image**, plus la marge
    /// interne des deux côtés — jamais une fraction de `220pt`, quel que soit
    /// le nombre de lignes du source (qui n'entre même plus dans ce calcul).
    func test_closedFrameHeight_withImage_followsImageHeightPlusInset() {
        let height = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: NSSize(width: 300, height: 180))
        XCTAssertEqual(height, 180 + MermaidBlockLayout.inset * 2)
    }

    /// Preuve directe de la régression corrigée : un diagramme dont l'image
    /// tient sur 40pt de haut ne doit **pas** hériter d'une réservation de
    /// 220pt (ou toute fraction de 220) sous prétexte que son source tient
    /// sur 2 lignes — la hauteur ne dépend plus du tout du nombre de lignes.
    func test_closedFrameHeight_smallImage_isNotInflatedByReservedHeightLegacy() {
        let height = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: NSSize(width: 300, height: 40))
        XCTAssertEqual(height, 40 + MermaidBlockLayout.inset * 2)
        XCTAssertLessThan(height, 110, "l'ancien défaut réservait 110pt par ligne pour un bloc de 2 lignes")
    }

    func test_closedFrameWidth_noImage_isPlaceholderWidth() {
        XCTAssertEqual(MermaidBlockLayout.closedFrameWidth(forAttachmentSize: nil), MermaidBlockLayout.placeholderWidth)
    }

    func test_closedFrameWidth_withImage_followsImageWidthPlusInset() {
        let width = MermaidBlockLayout.closedFrameWidth(forAttachmentSize: NSSize(width: 300, height: 180))
        XCTAssertEqual(width, 300 + MermaidBlockLayout.inset * 2)
    }

    // MARK: - centeredImageRect — jamais de redimensionnement (letterbox)

    /// Contrairement à l'ancien `fittedRect` (retiré : il redimensionnait
    /// l'image pour remplir une zone réservée arbitraire), l'image garde ici
    /// sa taille native, quelle que soit `containerRect`.
    func test_centeredImageRect_neverResizesTheImage() {
        let container = NSRect(x: 0, y: 0, width: 400, height: 300)
        let rect = MermaidBlockLayout.centeredImageRect(for: NSSize(width: 120, height: 60), in: container)
        XCTAssertEqual(rect.width, 120)
        XCTAssertEqual(rect.height, 60)
    }

    func test_centeredImageRect_centersHorizontallyWhenContainerIsWider() {
        let container = NSRect(x: 0, y: 0, width: 200, height: 60)
        let rect = MermaidBlockLayout.centeredImageRect(for: NSSize(width: 100, height: 60), in: container)
        XCTAssertEqual(rect.minX, 50, "centré : (200-100)/2")
        XCTAssertEqual(rect.minY, 0)
    }

    func test_centeredImageRect_degenerateImageSize_returnsContainerRectUnchanged() {
        let container = NSRect(x: 10, y: 20, width: 200, height: 100)
        let rect = MermaidBlockLayout.centeredImageRect(for: .zero, in: container)
        XCTAssertEqual(rect, container)
    }

    func test_centeredImageRect_degenerateContainerRect_returnsContainerRectUnchanged() {
        let container = NSRect(x: 0, y: 0, width: 0, height: 0)
        let rect = MermaidBlockLayout.centeredImageRect(for: NSSize(width: 10, height: 10), in: container)
        XCTAssertEqual(rect, container)
    }

    // MARK: - splitFirstLine

    func test_splitFirstLine_multilineBlock_firstLineIncludesTrailingNewline() {
        let text = "```mermaid\ngraph TD\nA-->B\n```" as NSString
        let range = NSRange(location: 0, length: text.length)
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: range, in: text)

        XCTAssertEqual(text.substring(with: firstLine), "```mermaid\n")
        XCTAssertEqual(text.substring(with: rest), "graph TD\nA-->B\n```")
    }

    func test_splitFirstLine_singleLineWithoutNewline_restIsEmpty() {
        let text = "graph TD" as NSString
        let range = NSRange(location: 0, length: text.length)
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: range, in: text)

        XCTAssertEqual(firstLine, range)
        XCTAssertEqual(rest.length, 0)
        XCTAssertEqual(rest.location, range.location + range.length)
    }

    func test_splitFirstLine_rangesTogetherCoverTheWholeInputRange() {
        let text = "a\nb\nc\nd" as NSString
        let range = NSRange(location: 0, length: text.length)
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: range, in: text)

        XCTAssertEqual(firstLine.length + rest.length, range.length)
        XCTAssertEqual(firstLine.location + firstLine.length, rest.location)
    }

    // MARK: - selectionTouches

    func test_selectionTouches_locationInsideBlock_isTrue() {
        XCTAssertTrue(MermaidBlockLayout.selectionTouches(5, blockRange: NSRange(location: 2, length: 10)))
    }

    func test_selectionTouches_locationAtBothEdges_isTrue() {
        let block = NSRange(location: 2, length: 10)
        XCTAssertTrue(MermaidBlockLayout.selectionTouches(2, blockRange: block), "borne de début incluse")
        XCTAssertTrue(MermaidBlockLayout.selectionTouches(12, blockRange: block), "borne de fin incluse")
    }

    func test_selectionTouches_locationOutsideBlock_isFalse() {
        let block = NSRange(location: 10, length: 5)
        XCTAssertFalse(MermaidBlockLayout.selectionTouches(1, blockRange: block))
        XCTAssertFalse(MermaidBlockLayout.selectionTouches(20, blockRange: block))
    }

    func test_selectionTouches_notFoundLocation_isFalse() {
        XCTAssertFalse(MermaidBlockLayout.selectionTouches(NSNotFound, blockRange: NSRange(location: 0, length: 10)))
    }
}
