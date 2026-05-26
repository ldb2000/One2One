import Foundation
import SwiftData

/// Édition destructive du transcript. Suppression atomique d'un segment :
/// texte + portion audio + shift des segments postérieurs.
enum TranscriptEditService {

    /// Supprime `seg` du transcript et splice la portion `[seg.startSeconds,
    /// seg.endSeconds]` du wav si dispo. Tous les segments commençant après
    /// ou égal à `seg.endSeconds` voient leurs timestamps shiftés vers la
    /// gauche par `seg.endSeconds - seg.startSeconds`.
    ///
    /// Si `meeting.audioAvailability != .original`, le splice audio est skippé
    /// (texte supprimé seul).
    ///
    /// Throw si le splice audio échoue (transcript intact dans ce cas).
    static func deleteSegment(_ seg: TranscriptSegment,
                               in meeting: Meeting,
                               context: ModelContext) async throws {
        let removedDuration = seg.endSeconds - seg.startSeconds
        let cutFrom = seg.startSeconds
        let cutTo = seg.endSeconds

        // 1. Splice audio first (failure-safe : si throw, transcript intact)
        if meeting.audioAvailability == .original, let wavURL = meeting.wavFileURL {
            try await AudioFileEditor.cut(url: wavURL, from: cutFrom, to: cutTo)
        }

        // 2. Shift segments après la coupe
        for other in meeting.transcriptSegments {
            if other.persistentModelID == seg.persistentModelID { continue }
            if other.startSeconds >= cutTo {
                other.startSeconds -= removedDuration
                other.endSeconds -= removedDuration
            }
        }

        // 3. Suppression du segment cible
        context.delete(seg)
        try context.save()
    }
}
