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

    /// Avec une image connue, la hauteur suit **directement** cette image
    /// (elle porte déjà son propre cadre composé par `MermaidAttachmentFactory`,
    /// jamais une marge rajoutée ici en plus — un double cadre) — jamais une
    /// fraction de `220pt`, quel que soit le nombre de lignes du source (qui
    /// n'entre même plus dans ce calcul).
    func test_closedFrameHeight_withImage_followsImageHeightExactly() {
        let height = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: NSSize(width: 300, height: 180))
        XCTAssertEqual(height, 180)
    }

    /// Preuve directe de la régression corrigée : un diagramme dont l'image
    /// tient sur 40pt de haut ne doit **pas** hériter d'une réservation de
    /// 220pt (ou toute fraction de 220) sous prétexte que son source tient
    /// sur 2 lignes — la hauteur ne dépend plus du tout du nombre de lignes.
    func test_closedFrameHeight_smallImage_isNotInflatedByReservedHeightLegacy() {
        let height = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: NSSize(width: 300, height: 40))
        XCTAssertEqual(height, 40)
        XCTAssertLessThan(height, 110, "l'ancien défaut réservait 110pt par ligne pour un bloc de 2 lignes")
    }

    func test_closedFrameWidth_noImage_isPlaceholderWidth() {
        XCTAssertEqual(MermaidBlockLayout.closedFrameWidth(forAttachmentSize: nil), MermaidBlockLayout.placeholderWidth)
    }

    func test_closedFrameWidth_withImage_followsImageWidthExactly() {
        let width = MermaidBlockLayout.closedFrameWidth(forAttachmentSize: NSSize(width: 300, height: 180))
        XCTAssertEqual(width, 300)
    }

    // MARK: - fittedSize — jamais agrandie, réduite seulement si trop large

    func test_fittedSize_imageNarrowerThanMaxWidth_isUnchanged() {
        let size = MermaidBlockLayout.fittedSize(for: NSSize(width: 200, height: 100), maxWidth: 400)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 100)
    }

    /// Preuve directe : jamais de double cadre / redimensionnement en
    /// letterbox dans une zone plus grande (l'ancien défaut, `fittedRect`,
    /// retiré) — seule une image effectivement plus large que `maxWidth` est
    /// réduite, en conservant son ratio d'aspect.
    func test_fittedSize_imageWiderThanMaxWidth_isScaledDownPreservingAspectRatio() {
        let size = MermaidBlockLayout.fittedSize(for: NSSize(width: 400, height: 100), maxWidth: 200)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 50, "ratio d'aspect conservé : /2 sur les deux dimensions")
    }

    func test_fittedSize_degenerateSize_returnsSizeUnchanged() {
        let size = MermaidBlockLayout.fittedSize(for: .zero, maxWidth: 200)
        XCTAssertEqual(size, .zero)
    }

    func test_fittedSize_degenerateMaxWidth_returnsSizeUnchanged() {
        let size = MermaidBlockLayout.fittedSize(for: NSSize(width: 100, height: 50), maxWidth: 0)
        XCTAssertEqual(size, NSSize(width: 100, height: 50))
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

    // MARK: - blockRange(in:at:) — régression mesurée sur cette branche

    /// Preuve directe de la régression mesurée pendant ce chantier, sur le
    /// storage réel produit par `StyleRenderer` (`.mdMermaidAttachment` porte
    /// la même instance sur tout le bloc, mais `.paragraphStyle` diffère
    /// entre la première ligne et le reste — voir `applyClosedMermaidGeometry`
    /// — ce qui scinde la représentation interne du storage) : mesuré,
    /// `storage.attribute(_:at:effectiveRange:)` (non « longest ») renvoyait
    /// {location, 9} au lieu de {location, 14} interrogé au tout début du
    /// bloc. `blockRange(in:at:)` doit renvoyer la même plage complète quel
    /// que soit le point d'entrée dans le bloc.
    func test_blockRange_mergesAcrossTheParagraphStyleBoundaryOfARealClosedBlock() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        StyleRenderer.applyVisualStyle(to: storage)
        defer { MainActor.assumeIsolated { MermaidAttachmentFactory.invalidateLiveCache() } }

        // Le source stocké (fences exclues) est "graph TD\nA-->B" (14
        // caractères) ; la première ligne ("graph TD\n") en fait 9.
        let start = (storage.string as NSString).range(of: "graph TD").location
        let expected = NSRange(location: start, length: 14)

        XCTAssertEqual(MermaidBlockLayout.blockRange(in: storage, at: start), expected)
        XCTAssertEqual(MermaidBlockLayout.blockRange(in: storage, at: start + 9), expected, "peu importe l'index de départ dans le bloc")
        XCTAssertEqual(MermaidBlockLayout.blockRange(in: storage, at: start + 13), expected)
    }

    func test_blockRange_noAttachment_isNil() {
        let storage = NSTextStorage(string: "hello world")
        XCTAssertNil(MermaidBlockLayout.blockRange(in: storage, at: 0))
    }

    func test_blockRange_outOfBoundsLocation_isNil() {
        let storage = NSTextStorage(string: "hi")
        XCTAssertNil(MermaidBlockLayout.blockRange(in: storage, at: 10))
        XCTAssertNil(MermaidBlockLayout.blockRange(in: storage, at: -1))
    }

    /// `location == storage.length` (juste après le dernier caractère, ex.
    /// curseur en toute fin de document) doit renvoyer `nil` — pas
    /// planter : `storage.attribute(at:effectiveRange:)` exige une position
    /// strictement inférieure à la longueur.
    func test_blockRange_locationExactlyAtStorageLength_isNil() {
        let storage = NSTextStorage(string: "hi")
        XCTAssertNil(MermaidBlockLayout.blockRange(in: storage, at: storage.length))
    }
}
