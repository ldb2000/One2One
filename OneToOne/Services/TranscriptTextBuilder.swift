import Foundation

/// Render le contenu de la variable `{{transcript}}` à partir des segments
/// de la réunion. Les segments marqués `isHighlighted` sont entourés de
/// marqueurs `**[IMPORTANT]**...**[/IMPORTANT]**` pour signaler explicitement
/// au LLM les passages prioritaires.
///
/// Fallback : si la réunion n'a pas de `transcriptSegments` (transcript pasté
/// manuellement), retourne `meeting.mergedTranscript` tel quel.
enum TranscriptTextBuilder {

    static func build(meeting: Meeting) -> String {
        let segments = meeting.transcriptSegments.sorted { $0.orderIndex < $1.orderIndex }
        guard !segments.isEmpty else { return meeting.mergedTranscript }

        return segments.map { seg in
            let prefix = "[\(seg.formattedTimestamp) · \(seg.displayLabel)] "
            if seg.isHighlighted {
                return prefix + "**[IMPORTANT]** " + seg.text + " **[/IMPORTANT]**"
            }
            return prefix + seg.text
        }.joined(separator: "\n")
    }
}
