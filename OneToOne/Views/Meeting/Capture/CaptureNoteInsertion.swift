import Foundation
import SwiftData

/// Insertion d'une capture dans la colonne de notes, et résolution du chemin
/// inverse (spec §5.3 : « une capture insérée dans une note s'affiche en carte
/// 56 × 36 + titre + première ligne d'OCR + `Agrandir` »).
///
/// La note n'embarque **pas** l'image : elle porte un `sourceRef {capture,
/// stableID, t}` (programme §3), et la carte va relire la capture. Copier le
/// texte d'OCR dans la note aurait figé un texte que l'OCR met à jour une
/// seconde plus tard, et dupliqué dans l'index ce que la pièce indexe déjà.
@MainActor
enum CaptureNoteInsertion {

    /// Insère la carte de capture dans les notes, au timecode de la capture.
    ///
    /// Idempotent : une capture déjà insérée n'est pas dupliquée — le bouton
    /// `＋ Note` est à portée de double-clic, et deux cartes identiques dans la
    /// colonne ne seraient distinguables par rien.
    @discardableResult
    static func insert(_ capture: SlideCapture,
                       in meeting: Meeting,
                       context: ModelContext) -> MeetingNote? {
        if let existante = note(for: capture, in: meeting) { return existante }

        let note = MeetingNote(t: capture.t ?? 0,
                               text: CaptureStripModel.title(for: capture),
                               kind: .note,
                               visibility: MeetingNoteStore.defaultVisibility(for: meeting.kind))
        note.sourceRef = SourceRef(kind: .capture, stableID: capture.id, t: capture.t)
        note.orderIndex = MeetingNoteStore.nextOrderIndex(at: note.t, in: meeting)
        note.meeting = meeting
        context.insert(note)
        try? context.save()
        NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
        return note
    }

    /// La note qui porte déjà cette capture, s'il y en a une.
    static func note(for capture: SlideCapture, in meeting: Meeting) -> MeetingNote? {
        meeting.timedNotes.first { note in
            note.sourceRef?.kind == .capture && note.sourceRef?.stableID == capture.id
        }
    }

    /// La capture désignée par une note, `nil` quand la référence ne mène plus
    /// nulle part (capture supprimée) : la colonne affiche alors la ligne de
    /// texte, jamais une carte vide.
    static func capture(for note: MeetingNote, in meeting: Meeting) -> SlideCapture? {
        guard let ref = note.sourceRef, ref.kind == .capture else { return nil }
        return meeting.attachments.flatMap(\.slides).first { $0.id == ref.stableID }
    }

    /// Le brouillon d'action d'une capture : le rail y ajoutera la pilule
    /// `◫ mm:ss` (`ActionCardEditing.libelleSource`, lot 3).
    static func actionDraft(for capture: SlideCapture) -> ActionDraft {
        ActionDraft(title: CaptureStripModel.firstOCRLine(of: capture) ?? CaptureStripModel.title(for: capture),
                    sourceRef: SourceRef(kind: .capture, stableID: capture.id, t: capture.t))
    }
}
