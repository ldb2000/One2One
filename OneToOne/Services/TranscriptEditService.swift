import Foundation
import SwiftData

/// Échecs propres à l'édition de transcription.
enum TranscriptEditError: Error, LocalizedError {

    /// La coupe audio a réussi, la sauvegarde qui suit a échoué.
    ///
    /// C'est l'état dangereux : le fichier audio est **déjà** modifié sur disque, la
    /// transcription non. Les deux ne correspondent plus, et seul un message explicite
    /// permet à l'utilisateur de le savoir.
    case saveFailedAfterAudioCut(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .saveFailedAfterAudioCut(let underlying):
            return """
            L'audio a été coupé mais la transcription n'a pas pu être enregistrée : \
            les deux ne correspondent plus. Cause : \
            \((underlying as? LocalizedError)?.errorDescription ?? String(describing: underlying))
            """
        }
    }
}

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
    /// Throw si le splice audio échoue : transcript intact dans ce cas, seule cette
    /// première étape est sans risque. Throw aussi (`TranscriptEditError
    /// .saveFailedAfterAudioCut`) si la sauvegarde finale échoue une fois la coupe audio
    /// déjà effectuée sur disque : dans ce cas la suppression et le shift en mémoire sont
    /// annulés (`context.rollback()`), donc la transcription reste intacte — mais l'audio,
    /// lui, reste coupé sur disque. L'audio et la transcription ne correspondent plus.
    static func deleteSegment(_ seg: TranscriptSegment,
                               in meeting: Meeting,
                               context: ModelContext) async throws {
        let removedDuration = seg.endSeconds - seg.startSeconds
        let cutFrom = seg.startSeconds
        let cutTo = seg.endSeconds

        // 1. Splice audio first (sans risque seulement à cette étape : si throw ici,
        // transcript intact). Au-delà, l'échec de la sauvegarde finale laisse l'audio
        // déjà coupé sur disque et le texte désaccordé — voir TranscriptEditError.
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
        do {
            try context.save()
        } catch {
            // La suppression et le shift des timestamps ci-dessus ne sont encore
            // qu'en mémoire : on les annule pour que la transcription revienne
            // exactement à son état d'avant l'appel. C'est un choix assumé — l'audio,
            // lui, reste coupé sur disque, ce que le message d'erreur annonce.
            // L'alternative (garder la suppression en mémoire sans la sauvegarder)
            // laisserait l'écran afficher une suppression réussie qui ne l'est pas,
            // et une sauvegarde ultérieure sans rapport pourrait la persister par
            // accident. Mieux vaut une transcription intacte face à un audio coupé
            // qu'une suppression fantôme.
            context.rollback()
            throw TranscriptEditError.saveFailedAfterAudioCut(underlying: error)
        }
    }
}
