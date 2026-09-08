import Foundation
import SwiftData

/// Détecte et nettoie les ressources orphelines : pièces jointes dont le fichier a
/// disparu du disque, et fichiers WAV temporaires laissés par un enregistrement interrompu.
@MainActor
enum OrphanCleanupService {

    /// Pièces jointes dont le fichier pointé par `filePath` n'existe plus sur
    /// le disque **et** qui sont des références externes.
    ///
    /// Deux familles sont exclues depuis la décision D5 (ADR
    /// `2026-09-07-pieces-copiees-jamais-referencees.md`) :
    ///
    /// - **les pièces copiées** dans le dossier de l'application. Un fichier
    ///   interne manquant est un incident à signaler — le tiroir la marque
    ///   orpheline et propose de la relier — pas une ligne à nettoyer. La
    ///   proposer ici reviendrait à effacer le texte extrait, les chunks RAG et
    ///   les citations de la seule pièce qu'on ne peut plus retrouver ailleurs.
    /// - **les pièces `link`**, dont le `filePath` porte une URL : aucun
    ///   fichier local ne peut leur manquer, et `fileExists` sur une URL rend
    ///   toujours faux.
    static func orphanAttachments(in context: ModelContext) -> [MeetingAttachment] {
        let descriptor = FetchDescriptor<MeetingAttachment>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            guard $0.kind != AttachmentCopyPolicy.linkKind else { return false }
            guard !AttachmentCopyPolicy.isCopied(path: $0.filePath) else { return false }
            return !FileManager.default.fileExists(atPath: $0.filePath)
        }
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
