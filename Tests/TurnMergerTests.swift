import XCTest
@testable import OneToOne

final class TurnMergerTests: XCTestCase {
    private func turn(_ s: Double, _ e: Double, _ c: Int) -> TurnMerger.DiarTurn {
        TurnMerger.DiarTurn(startSec: s, endSec: e, clusterID: c)
    }

    func testEmpty() {
        XCTAssertTrue(TurnMerger.mergeAdjacent([], maxGap: 0.5).isEmpty)
    }

    func testSingle() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
    }

    func testMergesSameSpeakerWithinGap() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.3, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].endSec, 2, accuracy: 0.0001)
    }

    func testGapExactlyMaxMerges() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.5, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
    }

    func testGapAboveMaxSeparates() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.6, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 2)
    }

    func testDifferentSpeakersSeparate() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.1, 2, 1)], maxGap: 0.5)
        XCTAssertEqual(r.count, 2)
    }

    func testContainedTurnKeepsMaxEnd() {
        let r = TurnMerger.mergeAdjacent([turn(0, 5, 0), turn(1, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].endSec, 5, accuracy: 0.0001)
    }

    func testUnsortedInputSortedFirst() {
        let r = TurnMerger.mergeAdjacent([turn(1.3, 2, 0), turn(0, 1, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].startSec, 0, accuracy: 0.0001)
        XCTAssertEqual(r[0].endSec, 2, accuracy: 0.0001)
    }

    func testMergeConsecutiveBlocksConcatsText() {
        let blocks = [
            TurnMerger.Block(speaker: 0, start: 0, end: 1, text: "bonjour"),
            TurnMerger.Block(speaker: 0, start: 1, end: 2, text: "ça va"),
            TurnMerger.Block(speaker: 1, start: 2, end: 3, text: "oui"),
        ]
        let r = TurnMerger.mergeConsecutiveBlocks(blocks)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].text, "bonjour ça va")
        XCTAssertEqual(r[0].end, 2, accuracy: 0.0001)
        XCTAssertEqual(r[1].speaker, 1)
    }
}
