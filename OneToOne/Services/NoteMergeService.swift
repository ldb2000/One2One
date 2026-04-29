import Foundation

/// Fusion transcription + notes prises en live.
///
/// Stratégie v1 : concaténation simple avec séparateur (on a décidé d'éviter
/// les timestamps par ligne — cf. décision produit). Le prompt IA aval sait
/// que la partie "Notes" vient de l'utilisateur et doit primer sur la
/// transcription en cas de divergence.
enum NoteMergeService {

    static let transcriptHeader = "## Transcription audio (Cohere MLX)"
    static let notesHeader = "## Notes prises en live"

    static func merge(transcript: String, liveNotes: String) -> String {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (t.isEmpty, n.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return "\(transcriptHeader)\n\n\(t)"
        case (true, false):
            return "\(notesHeader)\n\n\(n)"
        case (false, false):
            return """
            \(transcriptHeader)

            \(t)

            ---

            \(notesHeader)

            \(n)
            """
        }
    }
}
