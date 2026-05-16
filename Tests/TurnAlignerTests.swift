import XCTest
@testable import OneToOne

final class TurnAlignerTests: XCTestCase {

    func test_singleChunk_assignedToMaxOverlapTurn() {
        let turns: [TurnAligner.DiarTurn] = [
            .init(startSec: 0, endSec: 10, clusterID: 0),
            .init(startSec: 10, endSec: 20, clusterID: 1)
        ]
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 8, endSec: 12, text: "hello world")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: turns)
        XCTAssertEqual(out.count, 1)
        // Chunk overlaps turn 0 by 2s and turn 1 by 2s → tie → first wins.
        XCTAssertEqual(out[0].clusterID, 0)
    }

    func test_consecutiveChunks_sameCluster_merged() {
        let turns: [TurnAligner.DiarTurn] = [
            .init(startSec: 0, endSec: 30, clusterID: 0)
        ]
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 0, endSec: 10, text: "Bonjour"),
            .init(startSec: 10, endSec: 20, text: "comment ça va"),
            .init(startSec: 20, endSec: 30, text: "aujourd'hui")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: turns)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].text, "Bonjour comment ça va aujourd'hui")
        XCTAssertEqual(out[0].clusterID, 0)
        XCTAssertEqual(out[0].startSec, 0, accuracy: 0.001)
        XCTAssertEqual(out[0].endSec, 30, accuracy: 0.001)
    }

    func test_consecutiveChunks_differentClusters_notMerged() {
        let turns: [TurnAligner.DiarTurn] = [
            .init(startSec: 0, endSec: 10, clusterID: 0),
            .init(startSec: 10, endSec: 20, clusterID: 1)
        ]
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 1, endSec: 9, text: "first"),
            .init(startSec: 11, endSec: 19, text: "second")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: turns)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].clusterID, 0)
        XCTAssertEqual(out[0].text, "first")
        XCTAssertEqual(out[1].clusterID, 1)
        XCTAssertEqual(out[1].text, "second")
    }

    func test_emptyTurns_singleClusterFallback() {
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 0, endSec: 5, text: "X")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: [])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].clusterID, 0)
    }
}
