import Foundation

/// Construit la liste des passages marqués comme importants par l'utilisateur,
/// formatée pour injection dans le prompt LLM via `{{transcript.highlights}}`.
/// Format : `[mm:ss · Nom du Speaker] Texte du segment` une ligne par highlight.
enum TranscriptHighlightsBuilder {

    /// Retourne les segments surlignés (`isHighlighted`) triés chronologiquement,
    /// une ligne par highlight au format `[mm:ss · Speaker] texte`.
    /// Retourne une chaîne vide si aucun segment n'est surligné.
    static func build(meeting: Meeting) -> String {
        let highlighted = meeting.transcriptSegments
            .filter { $0.isHighlighted }
            .sorted { $0.startSeconds < $1.startSeconds }
        guard !highlighted.isEmpty else { return "" }

        return highlighted.map { seg in
            "[\(seg.formattedTimestamp) · \(seg.displayLabel)] \(seg.text)"
        }.joined(separator: "\n")
    }
}
