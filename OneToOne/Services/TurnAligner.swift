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
        let initial: [AlignedSegment] = mapped.map { chunk, cid in
            AlignedSegment(startSec: chunk.startSec, endSec: chunk.endSec, text: chunk.text, clusterID: cid)
        }
        return mergeConsecutive(initial)
    }

    /// Merge consecutive segments sharing the same `clusterID`.
    /// Pure helper, reusable post-canonicalization.
    static func mergeConsecutive(_ segments: [AlignedSegment]) -> [AlignedSegment] {
        var merged: [AlignedSegment] = []
        for s in segments {
            if let last = merged.last, last.clusterID == s.clusterID {
                merged.removeLast()
                let newText = (last.text + " " + s.text).trimmingCharacters(in: .whitespaces)
                merged.append(AlignedSegment(
                    startSec: last.startSec,
                    endSec: s.endSec,
                    text: newText,
                    clusterID: s.clusterID
                ))
            } else {
                merged.append(s)
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
