import Foundation

/// Accumule le texte de fenêtres STT qui se recouvrent, en supprimant le
/// chevauchement de mots entre la fin du texte déjà accumulé et le début de la
/// nouvelle fenêtre (Voxtral n'ayant aucun contexte inter-fenêtres). Comparaison
/// insensible à la casse ; on cherche le plus long chevauchement (jusqu'à 12 mots).
struct LiveTranscriptMerger {

    private(set) var text: String = ""
    private static let maxOverlapWords = 12

    mutating func append(_ window: String) -> String {
        let trimmed = window.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard !text.isEmpty else { text = trimmed; return text }

        let overlap = Self.overlapSuffixPrefix(text, trimmed)
        if overlap == 0 {
            text += " " + trimmed
        } else {
            let remainingWords = Self.words(trimmed).dropFirst(overlap)
            if !remainingWords.isEmpty {
                text += " " + remainingWords.joined(separator: " ")
            }
        }
        return text
    }

    /// Nombre de mots communs entre le suffixe de `previousTail` et le préfixe
    /// de `next` (le plus long, ≤ maxOverlapWords). Insensible à la casse.
    static func overlapSuffixPrefix(_ previousTail: String, _ next: String) -> Int {
        let tail = words(previousTail).map { $0.lowercased() }
        let head = words(next).map { $0.lowercased() }
        let maxK = min(maxOverlapWords, tail.count, head.count)
        var best = 0
        var k = 1
        while k <= maxK {
            if Array(tail.suffix(k)) == Array(head.prefix(k)) { best = k }
            k += 1
        }
        return best
    }

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }
}
