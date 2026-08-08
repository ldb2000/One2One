import XCTest
@testable import ProbeCore

/// Primitives du document : longueur UTF-16 d'un bloc et ordre des positions.
final class ProbePrimitivesTests: XCTestCase {

    /// La longueur d'un bloc est comptée en UTF-16, comme les `NSRange`
    /// d'AppKit — un « é » décomposé vaut 2, un emoji vaut 2.
    func test_blockLength_isCountedInUTF16() {
        XCTAssertEqual(ProbeBlock(text: "abc").length, 3)
        XCTAssertEqual(ProbeBlock(text: "cafe\u{0301}").length, 5)
        XCTAssertEqual(ProbeBlock(text: "👍").length, 2)
    }

    /// Les positions s'ordonnent par bloc d'abord, puis par décalage.
    func test_positions_areOrderedByBlockThenOffset() {
        let first = ProbePosition(blockIndex: 0, offset: 9)
        let second = ProbePosition(blockIndex: 1, offset: 0)
        XCTAssertLessThan(first, second)
        XCTAssertLessThan(ProbePosition(blockIndex: 1, offset: 0),
                          ProbePosition(blockIndex: 1, offset: 1))
    }

    /// `start` et `end` normalisent une sélection posée à l'envers.
    func test_selection_normalisesABackwardsDrag() {
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 2, offset: 1),
                                       head: ProbePosition(blockIndex: 0, offset: 4))
        XCTAssertEqual(selection.start, ProbePosition(blockIndex: 0, offset: 4))
        XCTAssertEqual(selection.end, ProbePosition(blockIndex: 2, offset: 1))
        XCTAssertFalse(selection.isCollapsed)
        XCTAssertTrue(selection.spansBlocks)
    }

    func test_caretSelection_isCollapsedAndStaysInOneBlock() {
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 1, offset: 3))
        XCTAssertTrue(caret.isCollapsed)
        XCTAssertFalse(caret.spansBlocks)
    }
}
