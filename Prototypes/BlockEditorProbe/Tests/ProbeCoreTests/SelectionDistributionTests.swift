import XCTest
@testable import ProbeCore

/// Répartition d'une sélection traversante : chaque bloc reçoit sa part —
/// partielle aux extrêmes, entière au milieu.
final class SelectionDistributionTests: XCTestCase {

    func test_ranges_insideOneBlock_giveThatBlockTheRun() {
        let document = ProbeDocument(texts: ["Bonjour", "Monde"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 2),
                                       head: ProbePosition(blockIndex: 0, offset: 5))

        let ranges = SelectionDistribution.ranges(for: selection, in: document)

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0], NSRange(location: 2, length: 3))
    }

    func test_ranges_acrossBlocks_arePartialAtTheEndsAndWholeInBetween() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois", "Quatre"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 3, offset: 2))

        let ranges = SelectionDistribution.ranges(for: selection, in: document)

        XCTAssertEqual(ranges.count, 4)
        XCTAssertEqual(ranges[0], NSRange(location: 1, length: 1), "queue du premier bloc")
        XCTAssertEqual(ranges[1], NSRange(location: 0, length: 4), "bloc intermédiaire entier")
        XCTAssertEqual(ranges[2], NSRange(location: 0, length: 5), "bloc intermédiaire entier")
        XCTAssertEqual(ranges[3], NSRange(location: 0, length: 2), "tête du dernier bloc")
    }

    /// Une sélection posée à l'envers donne exactement le même surlignage.
    func test_ranges_ignoreTheDirectionOfTheDrag() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let forward = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                     head: ProbePosition(blockIndex: 2, offset: 2))
        let backward = ProbeSelection(anchor: ProbePosition(blockIndex: 2, offset: 2),
                                      head: ProbePosition(blockIndex: 0, offset: 1))

        XCTAssertEqual(SelectionDistribution.ranges(for: forward, in: document),
                       SelectionDistribution.ranges(for: backward, in: document))
    }

    /// Un curseur simple : une seule entrée, de longueur zéro, sur son bloc.
    func test_ranges_forACaret_giveOneEmptyRange() {
        let document = ProbeDocument(texts: ["Un", "Deux"])
        let ranges = SelectionDistribution.ranges(
            for: ProbeSelection(caret: ProbePosition(blockIndex: 1, offset: 3)),
            in: document)

        XCTAssertEqual(ranges, [1: NSRange(location: 3, length: 0)])
    }

    func test_ranges_forTheWholeDocument_coverEveryBlockEntirely() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let ranges = SelectionDistribution.ranges(for: document.wholeDocument, in: document)

        XCTAssertEqual(ranges[0], NSRange(location: 0, length: 2))
        XCTAssertEqual(ranges[1], NSRange(location: 0, length: 4))
        XCTAssertEqual(ranges[2], NSRange(location: 0, length: 5))
    }
}
