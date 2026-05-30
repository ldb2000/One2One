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
    /// Ordre : audio d'abord (échec validation/I-O → transcript intact, cas
    /// commun), puis texte. Il n'existe pas de commit 2-phase entre le système
    /// de fichiers et SwiftData : si `context.save()` échoue APRÈS le splice
    /// audio (cas rare : disque plein…), audio et texte sont désynchronisés et
    /// non récupérables. Ce cas remonte une `TranscriptEditError.saveFailedAfterAudioCut`
    /// explicite pour que l'appelant alerte (re-transcription recommandée).
    static func deleteSegment(_ seg: TranscriptSegment,
                               in meeting: Meeting,
                               context: ModelContext) async throws {
        let removedDuration = seg.endSeconds - seg.startSeconds
        let cutFrom = seg.startSeconds
        let cutTo = seg.endSeconds

        // 1. Splice audio first (failure-safe : si throw, transcript intact)
        let audioCut = meeting.audioAvailability == .original && meeting.wavFileURL != nil
        if audioCut, let wavURL = meeting.wavFileURL {
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
        do {
            try context.save()
        } catch {
            // Pas de rollback du splice audio possible : signaler la désync.
            if audioCut {
                throw TranscriptEditError.saveFailedAfterAudioCut(underlying: error)
            }
            throw error
        }
    }
}

enum TranscriptEditError: LocalizedError {
    /// L'audio a été coupé mais la persistance du transcript a échoué :
    /// audio et texte sont désynchronisés et non récupérables.
    case saveFailedAfterAudioCut(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .saveFailedAfterAudioCut(let underlying):
            return "L'audio a été modifié mais le transcript n'a pas pu être "
                + "enregistré (\(underlying.localizedDescription)). "
                + "Audio et texte sont désormais désynchronisés — "
                + "une re-transcription est recommandée."
        }
    }
}
