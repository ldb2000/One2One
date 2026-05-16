import Foundation

/// Pure helper. Maps Cohere STT chunks to diarization clusters by temporal
/// overlap, then merges consecutive chunks belonging to the same cluster.
enum TurnAligner {

    /// Speaker turn from diarization. `clusterID` is local to the meeting
    /// (0-indexed). Use `clusterID + 1` when persisting `TranscriptSegment.speakerID`.
    struct DiarTurn: Sendable {
        let startSec: Double
        let endSec: Double
        let clusterID: Int
    }

    /// One transcribed chunk produced by Cohere.
    struct STTChunkInput {
        let startSec: Double
        let endSec: Double
        let text: String
    }

    /// Resulting segment: cluster-tagged + merged.
    struct AlignedSegment {
        let startSec: Double
        let endSec: Double
        let text: String
        let clusterID: Int
    }

    /// Align + merge. Empty `turns` => all chunks fall into cluster 0.
    static func align(chunks: [STTChunkInput], turns: [DiarTurn]) -> [AlignedSegment] {
        let mapped: [(STTChunkInput, Int)] = chunks.map { chunk in
            (chunk, clusterIDForChunk(chunk, turns: turns))
        }

        var merged: [AlignedSegment] = []
        for (chunk, cid) in mapped {
            if let last = merged.last, last.clusterID == cid {
                merged.removeLast()
                let newText = (last.text + " " + chunk.text).trimmingCharacters(in: .whitespaces)
                merged.append(AlignedSegment(
                    startSec: last.startSec,
                    endSec: chunk.endSec,
                    text: newText,
                    clusterID: cid
                ))
            } else {
                merged.append(AlignedSegment(
                    startSec: chunk.startSec,
                    endSec: chunk.endSec,
                    text: chunk.text,
                    clusterID: cid
                ))
            }
        }
        return merged
    }

    /// Returns the clusterID of the turn with max temporal overlap.
    /// Falls back to 0 if `turns` is empty. Ties → first matching turn.
    private static func clusterIDForChunk(_ chunk: STTChunkInput, turns: [DiarTurn]) -> Int {
        guard !turns.isEmpty else { return 0 }
        var bestCluster: Int = turns[0].clusterID
        var bestOverlap: Double = -1
        for t in turns {
            let overlap = min(chunk.endSec, t.endSec) - max(chunk.startSec, t.startSec)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestCluster = t.clusterID
            }
        }
        return bestCluster
    }
}
