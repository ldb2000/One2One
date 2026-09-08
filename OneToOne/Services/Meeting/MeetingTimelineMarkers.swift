import Foundation

/// Les repères de la frise audio, construits depuis la réunion (spec §2.4 :
/// « marqueurs ronds (note), carrés (capture, chantier 4), losanges
/// (décision) »).
///
/// Hors de la vue pour deux raisons vérifiables par un test : une capture non
/// horodatée (`SlideCapture.t == nil`, faite hors enregistrement) doit être
/// **ignorée** et non dessinée à `00:00` — un repère à zéro désigne un instant
/// où rien ne s'est passé ; et l'ordre d'une relation SwiftData n'est pas
/// garanti, donc le tri par timecode se fait ici, une fois.
@MainActor
enum MeetingTimelineMarkers {

    /// Forme du repère selon la nature de la ligne. Les natures propres au 1:1
    /// (feedback, promesse, demande, preuve) sont des notes : la frise n'a que
    /// trois formes, et en inventer une quatrième par nature la rendrait
    /// illisible.
    static func kind(for noteKind: MeetingNoteKind) -> MeetingPlayhead.Marker.Kind {
        switch noteKind {
        case .decision: return .decision
        case .risk:     return .risk
        case .note, .feedback, .promise, .request, .proof: return .note
        }
    }

    /// Tous les repères d'une réunion, triés par timecode.
    static func markers(for meeting: Meeting) -> [MeetingPlayhead.Marker] {
        var repères: [MeetingPlayhead.Marker] = meeting.timedNotes.map { note in
            MeetingPlayhead.Marker(t: note.t,
                                   kind: kind(for: note.kind),
                                   label: note.text)
        }

        // Les captures vivent sous les pièces jointes de type `slides`
        // (`MeetingAttachment.slides`), et non directement sur la réunion.
        let captures = meeting.attachments.flatMap(\.slides)
        repères += captures.compactMap { capture in
            guard let t = capture.t else { return nil }
            return MeetingPlayhead.Marker(t: t, kind: .capture, label: capture.ocrText)
        }

        return repères.sorted { $0.t < $1.t }
    }
}
