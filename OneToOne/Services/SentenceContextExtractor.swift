import Foundation

/// Extracts ~2 sentences before and ~2 sentences after a selected NSRange in a
/// text. Used by the manager report flow to capture context around a snippet
/// without invoking the AI at selection time.
///
/// Algorithm:
/// - `before` = walk backwards from `range.location`, collecting characters
///   until we have crossed 2 sentence terminators (`.`, `!`, `?`, `…`) OR a
///   paragraph break (`\n\n`) OR reached a hard cap of 400 characters.
/// - `after` = symmetric, walking forward from `range.location + range.length`.
///
/// All ranges are NSRange (UTF-16 offsets) for consistency with NSTextView.
enum SentenceContextExtractor {

    static let maxContextChars = 400
    static let targetSentences = 2

    /// Renvoie le contexte (`before`, `after`) autour de `range` dans `text`.
    /// - Une `range.length` de 0 (sélection vide / curseur) est valide : `before`
    ///   et `after` sont alors calculés autour du même point d'insertion.
    /// - « Phrase » = segment délimité par un terminateur `.`, `!`, `?` ou `…`
    ///   (les abréviations comme « M. » ne sont PAS reconnues : tout point compte).
    /// - Renvoie ("", "") si `text` est vide ou `range.location` est hors bornes.
    static func extractContext(text: String, range: NSRange) -> (before: String, after: String) {
        let nsText = text as NSString
        let total = nsText.length
        guard total > 0 else { return ("", "") }
        guard range.location >= 0, range.location <= total else { return ("", "") }

        let safeStart = min(range.location, total)
        let safeEnd = min(range.location + max(range.length, 0), total)

        let before = walkBackward(in: nsText, from: safeStart)
        let after = walkForward(in: nsText, from: safeEnd, total: total)
        return (before, after)
    }

    private static let terminators: Set<Character> = [".", "!", "?", "…"]

    private static func walkBackward(in nsText: NSString, from start: Int) -> String {
        guard start > 0 else { return "" }
        var sentencesSeen = 0
        var idx = start - 1
        var collected: [Character] = []
        // Track whether we've seen any non-terminator, non-whitespace content
        // (walking backwards) since the last counted terminator. This prevents
        // a terminator that sits between the selection and prior content from
        // being miscounted before any sentence body has been gathered.
        var sawContentSinceTerminator = false

        while idx >= 0 && collected.count < maxContextChars {
            let charRange = NSRange(location: idx, length: 1)
            let sub = nsText.substring(with: charRange)
            // Detect paragraph break: current char is \n and previous is \n
            if sub == "\n" && idx > 0 {
                let prevSub = nsText.substring(with: NSRange(location: idx - 1, length: 1))
                if prevSub == "\n" { break }
            }
            if let ch = sub.first {
                if terminators.contains(ch) {
                    if sawContentSinceTerminator {
                        if sentencesSeen >= targetSentences { break }
                        sentencesSeen += 1
                        sawContentSinceTerminator = false
                    }
                } else if !ch.isWhitespace {
                    sawContentSinceTerminator = true
                }
                collected.append(ch)
            }
            idx -= 1
        }
        return String(collected.reversed()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walkForward(in nsText: NSString, from end: Int, total: Int) -> String {
        guard end < total else { return "" }
        var sentencesSeen = 0
        var idx = end
        var collected: [Character] = []
        // Track whether we've seen any non-terminator, non-whitespace content
        // since the last counted terminator. This avoids counting the trailing
        // terminator of the selection itself (e.g. "SELECTED." → leading "." in
        // the after-context) as a full sentence.
        var sawContentSinceTerminator = false

        while idx < total && collected.count < maxContextChars {
            let sub = nsText.substring(with: NSRange(location: idx, length: 1))
            if sub == "\n" && idx + 1 < total {
                let nextSub = nsText.substring(with: NSRange(location: idx + 1, length: 1))
                if nextSub == "\n" { break }
            }
            if let ch = sub.first {
                collected.append(ch)
                if terminators.contains(ch) {
                    if sawContentSinceTerminator {
                        sentencesSeen += 1
                        sawContentSinceTerminator = false
                        if sentencesSeen >= targetSentences { break }
                    }
                } else if !ch.isWhitespace {
                    sawContentSinceTerminator = true
                }
            }
            idx += 1
        }
        return String(collected).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
