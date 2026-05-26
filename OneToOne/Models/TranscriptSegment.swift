import Foundation
import SwiftData

/// Segment de transcription avec timestamp + speaker. Distinct de
/// `TranscriptChunk` (utilisé pour RAG embeddings).
///
/// - `speakerID = 0` → non-assigné (par défaut quand pas encore diarized)
/// - `speakerID >= 1` → cluster anonyme (Speaker 1, 2, …)
/// - `speaker != nil` → cluster résolu vers un participant nommé
@Model
final class TranscriptSegment {
    /// Optional — see SwiftData migration caveat. Use `ensuredStableID`
    /// when you need a guaranteed non-nil UUID.
    var stableID: UUID? = nil
    var orderIndex: Int = 0
    var startSeconds: Double = 0
    var endSeconds: Double = 0
    var text: String = ""

    /// 0 = pas encore diarized, sinon index de cluster (1, 2, …).
    var speakerID: Int = 0

    /// Marqué par l'utilisateur comme passage important pour le reporting.
    /// Injecté dans `{{transcript.highlights}}` et entouré de marqueurs
    /// `**[IMPORTANT]**...**[/IMPORTANT]**` dans `{{transcript}}`.
    var isHighlighted: Bool = false

    /// Quand l'utilisateur a renommé le speaker vers un participant.
    var speaker: Collaborator?

    var meeting: Meeting?

    init(orderIndex: Int,
         startSeconds: Double,
         endSeconds: Double,
         text: String,
         speakerID: Int = 0) {
        self.stableID = UUID()
        self.orderIndex = orderIndex
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.speakerID = speakerID
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    /// Display label : nom du participant si renommé, sinon "Speaker N".
    var displayLabel: String {
        if let s = speaker { return s.name }
        if speakerID == 0 { return "?" }
        return "Speaker \(speakerID)"
    }

    var formattedTimestamp: String {
        let total = Int(startSeconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
