import Foundation
import SwiftData

/// Détecte et nettoie les ressources orphelines : pièces jointes dont le fichier a
/// disparu du disque, et fichiers WAV temporaires laissés par un enregistrement interrompu.
@MainActor
enum OrphanCleanupService {

    /// Pièces jointes dont le fichier pointé par `filePath` n'existe plus sur le disque.
    static func orphanAttachments(in context: ModelContext) -> [MeetingAttachment] {
        let descriptor = FetchDescriptor<MeetingAttachment>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !FileManager.default.fileExists(atPath: $0.filePath) }
    }

    /// Fichiers `*.tmp.wav` de `directory` modifiés il y a plus de `minutes` minutes
    /// (défaut 5), considérés comme des restes d'enregistrements abandonnés.
    static func staleTmpWavs(in directory: URL, olderThan minutes: Int = 5) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        return entries.filter {
            guard $0.lastPathComponent.hasSuffix(".tmp.wav") else { return false }
            let attrs = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
            guard let mtime = attrs?.contentModificationDate else { return false }
            return mtime < cutoff
        }
    }

    /// Supprime les pièces jointes données du contexte puis sauvegarde. L'échec de
    /// sauvegarde est volontairement ignoré (`try?`) : c'est une opération de nettoyage
    /// best-effort qui ne doit pas faire échouer l'appelant.
    static func deleteAttachments(_ rows: [MeetingAttachment], in context: ModelContext) {
        for r in rows { context.delete(r) }
        try? context.save()
    }

    /// Supprime les fichiers donnés du disque. Les échecs individuels sont ignorés
    /// silencieusement (`try?`) : nettoyage best-effort, un fichier déjà absent ou verrouillé
    /// n'interrompt pas la suppression des suivants.
    static func deleteFiles(_ urls: [URL]) {
        for u in urls { try? FileManager.default.removeItem(at: u) }
    }
}
