import Foundation
import SwiftData

/// Énumère les meetings éligibles aux traitements par lots (génération de compte rendu,
/// transcription, diarisation). Chaque méthode récupère tous les meetings puis filtre en mémoire.
@MainActor
enum BatchJobsService {

    /// Meetings transcrits mais sans compte rendu : `rawTranscript` non vide et `summary` vide.
    static func meetingsWithoutReport(in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            !$0.rawTranscript.isEmpty && $0.summary.isEmpty
        }
    }

    /// Meetings non transcrits mais transcriptibles : `rawTranscript` vide et audio jouable disponible.
    static func meetingsWithoutTranscript(in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            $0.rawTranscript.isEmpty && $0.hasPlayableAudio
        }
    }

    /// Meetings ayant des segments de transcription et un audio jouable mais aucune diarisation :
    /// `speakerAssignmentsJSON` vide ou égal à `"{}"`.
    static func meetingsWithoutDiarisation(in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { m in
            !m.transcriptSegments.isEmpty
                && m.hasPlayableAudio
                && (m.speakerAssignmentsJSON.isEmpty || m.speakerAssignmentsJSON == "{}")
        }
    }

    /// Chunks RAG dont l'embedding est absent ou calculé avec un autre modèle
    /// que le modèle courant (`EmbeddingService.model`). Candidats au
    /// ré-embedding après changement de backend/modèle.
    static func staleChunks(in context: ModelContext) -> [TranscriptChunk] {
        let descriptor = FetchDescriptor<TranscriptChunk>()
        let all = (try? context.fetch(descriptor)) ?? []
        let current = EmbeddingService.model
        return all.filter { $0.embeddingData == nil || $0.embeddingModel != current }
    }
}
