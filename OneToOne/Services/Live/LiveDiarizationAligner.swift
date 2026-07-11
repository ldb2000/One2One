import Foundation

/// Attribue chaque segment de transcription live au locuteur (clusterID) du
/// tour Pyannote avec lequel il partage le plus de temps. La diarisation étant
/// batch, cette attribution se fait après l'enregistrement, par recouvrement de
/// timestamps — sans réexécuter la STT.
enum LiveDiarizationAligner {

    static func alignToBlocks(segments: [LiveSegment],
                              turns: [TurnMerger.DiarTurn]) -> [TurnMerger.Block] {
        segments.map { seg in
            let speaker = dominantCluster(start: seg.start, end: seg.end, turns: turns)
            return TurnMerger.Block(speaker: speaker, start: seg.start, end: seg.end, text: seg.text)
        }
    }

    /// clusterID du tour de plus grand recouvrement ; 0 par défaut (aucun tour
    /// ne recouvre le segment, ou liste vide).
    private static func dominantCluster(start: Double, end: Double,
                                        turns: [TurnMerger.DiarTurn]) -> Int {
        var best = 0
        var bestOverlap = 0.0
        for t in turns {
            let overlap = min(end, t.endSec) - max(start, t.startSec)
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = t.clusterID
            }
        }
        return best
    }
}
