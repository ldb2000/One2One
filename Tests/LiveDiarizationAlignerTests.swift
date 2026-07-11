import Testing
@testable import OneToOne

struct LiveDiarizationAlignerTests {

    @Test func segmentTakesClusterWithMaxOverlap() {
        let segments = [
            LiveSegment(start: 0, end: 4, text: "bonjour"),
            LiveSegment(start: 5, end: 9, text: "ça va bien"),
        ]
        let turns = [
            TurnMerger.DiarTurn(startSec: 0, endSec: 4.5, clusterID: 0),
            TurnMerger.DiarTurn(startSec: 4.5, endSec: 10, clusterID: 1),
        ]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: turns)
        #expect(blocks.count == 2)
        #expect(blocks[0].speaker == 0)
        #expect(blocks[0].text == "bonjour")
        #expect(blocks[1].speaker == 1)
        #expect(blocks[1].text == "ça va bien")
    }

    @Test func segmentWithNoOverlapDefaultsToClusterZero() {
        let segments = [LiveSegment(start: 20, end: 24, text: "isolé")]
        let turns = [TurnMerger.DiarTurn(startSec: 0, endSec: 5, clusterID: 3)]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: turns)
        #expect(blocks.count == 1)
        #expect(blocks[0].speaker == 0)
    }

    @Test func emptyTurnsPutsEverythingOnClusterZero() {
        let segments = [LiveSegment(start: 0, end: 3, text: "a"), LiveSegment(start: 3, end: 6, text: "b")]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: [])
        #expect(blocks.allSatisfy { $0.speaker == 0 })
        #expect(blocks.count == 2)
    }

    @Test func preservesSegmentTextAndTimes() {
        let segments = [LiveSegment(start: 1, end: 2, text: "exact")]
        let turns = [TurnMerger.DiarTurn(startSec: 0, endSec: 3, clusterID: 7)]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: turns)
        #expect(blocks[0].start == 1)
        #expect(blocks[0].end == 2)
        #expect(blocks[0].text == "exact")
        #expect(blocks[0].speaker == 7)
    }
}
