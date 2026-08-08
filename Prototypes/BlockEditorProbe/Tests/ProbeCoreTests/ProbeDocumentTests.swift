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

/// `replace` est l'unique mutation structurante du document. Tous les gestes
/// destructifs de la sonde s'y ramènent.
final class ProbeDocumentReplaceTests: XCTestCase {

    func test_replace_insideOneBlock_replacesTheRun() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 0),
                                       head: ProbePosition(blockIndex: 0, offset: 3))

        let caret = document.replace(selection, with: "Salut")

        XCTAssertEqual(document.blocks.map(\.text), ["Salutjour"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 0, offset: 5))
    }

    /// Cas de la fusion par ⌫ : la queue du bloc suivant se recolle à la tête
    /// du précédent, et les blocs intermédiaires disparaissent.
    func test_replace_acrossBlocks_mergesHeadAndTail() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 2),
                                       head: ProbePosition(blockIndex: 2, offset: 0))

        let caret = document.replace(selection, with: "")

        XCTAssertEqual(document.blocks.map(\.text), ["UnTrois"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 0, offset: 2))
    }

    /// Cas de la scission par ⏎.
    func test_replace_withNewline_splitsTheBlock() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let caret = document.replace(
            ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 3)),
            with: "\n")

        XCTAssertEqual(document.blocks.map(\.text), ["Bon", "jour"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 1, offset: 0))
    }

    /// Cas du collage multi-lignes sur une sélection multi-blocs.
    func test_replace_acrossBlocks_withMultilineText_producesOneBlockPerLine() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let caret = document.replace(selection, with: "a\nb\nc")

        XCTAssertEqual(document.blocks.map(\.text), ["Ua", "b", "cois"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 2, offset: 1))
    }

    /// L'identité du premier bloc touché survit à la mutation : sans cela, la
    /// pile de vues détruirait et reconstruirait le `NSTextView` focalisé à
    /// chaque frappe, et le curseur sauterait.
    func test_replace_keepsTheIdentityOfTheFirstBlock() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let firstID = document.blocks[0].id
        let secondID = document.blocks[1].id

        document.replace(ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 2)),
                         with: "x")

        XCTAssertEqual(document.blocks[0].id, firstID)
        XCTAssertEqual(document.blocks[1].id, secondID, "un bloc hors plage ne doit pas changer d'identité")
    }

    /// Invariant : le document n'est jamais vide. Tout effacer laisse un bloc
    /// vide, pas zéro bloc.
    func test_replace_neverEmptiesTheDocument() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let everything = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 0),
                                        head: ProbePosition(blockIndex: 1, offset: 4))

        let caret = document.replace(everything, with: "")

        XCTAssertEqual(document.blocks.map(\.text), [""])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 0, offset: 0))
    }

    /// Les décalages sont en UTF-16 : couper entre les deux unités d'un « é »
    /// décomposé se fait à l'offset 3..5, pas 3..4.
    func test_replace_offsetsAreUTF16() {
        var document = ProbeDocument(texts: ["cafe\u{0301}"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 3),
                                       head: ProbePosition(blockIndex: 0, offset: 5))

        document.replace(selection, with: "é")

        XCTAssertEqual(document.blocks[0].text, "café")
    }

    /// Un document construit vide se normalise en un bloc vide.
    func test_emptyDocument_normalisesToOneEmptyBlock() {
        let document = ProbeDocument(blocks: [])
        XCTAssertEqual(document.blocks.map(\.text), [""])
    }
}
