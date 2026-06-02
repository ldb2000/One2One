import Foundation

/// Helpers purs du pipeline diarize-first. Aucune dépendance audio/modèle.
enum TurnMerger {
    /// Tour de parole issu de la diarisation.
    /// `clusterID` est 0-indexé et stable entre les appels (un même identifiant
    /// désigne toujours le même locuteur au sein d'une session de diarisation).
    struct DiarTurn: Sendable, Equatable {
        var startSec: Double
        var endSec: Double
        var clusterID: Int
    }

    /// Un tour transcrit (sortie finale d'un appel STT).
    /// `speaker` reprend directement la valeur de `DiarTurn.clusterID`
    /// (0-indexé) : c'est le même espace d'identifiants de locuteur.
    struct Block: Sendable, Equatable {
        var speaker: Int      // clusterID 0-indexé
        var start: Double
        var end: Double
        var text: String
    }

    /// Fusionne les tours consécutifs du même locuteur séparés de ≤ maxGap.
    /// `maxGap` est exprimé en secondes (inclusif), cohérent avec `startSec`/`endSec`.
    /// Trie défensivement par start. Gère les tours contenus/chevauchants via `max(end)`.
    static func mergeAdjacent(_ turns: [DiarTurn], maxGap: Double) -> [DiarTurn] {
        guard !turns.isEmpty else { return [] }
        let sorted = turns.sorted { $0.startSec < $1.startSec }
        var merged: [DiarTurn] = [sorted[0]]
        for t in sorted.dropFirst() {
            let lastIdx = merged.count - 1
            let last = merged[lastIdx]
            if t.clusterID == last.clusterID && (t.startSec - last.endSec) <= maxGap {
                merged[lastIdx].endSec = max(last.endSec, t.endSec)
            } else {
                merged.append(t)
            }
        }
        return merged
    }

    /// Re-fusionne les blocs adjacents du même locuteur (post-canonicalisation).
    static func mergeConsecutiveBlocks(_ blocks: [Block]) -> [Block] {
        var merged: [Block] = []
        for b in blocks {
            if var last = merged.last, last.speaker == b.speaker {
                merged.removeLast()
                last.end = b.end
                last.text = (last.text + " " + b.text).trimmingCharacters(in: .whitespaces)
                merged.append(last)
            } else {
                merged.append(b)
            }
        }
        return merged
    }
}
