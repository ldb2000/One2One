import Foundation

/// L'état **calculé** d'une pièce de séance : son identifiant stable, l'URL de
/// son fichier, et le fait qu'elle soit orpheline.
///
/// Rien n'est persisté ici. « Orpheline » est une lecture du disque, pas une
/// colonne : un drapeau enregistré mentirait dès qu'on restaure une sauvegarde
/// sur une autre machine, ou dès qu'un volume revient. Le tiroir affiche
/// « Fichier introuvable — relier » à partir de cette lecture.
extension MeetingAttachment {

    /// Identifiant stable, backfillé si la ligne est antérieure au lot 6.
    /// Même contrat que `Meeting.ensuredStableID` : le premier accès écrit.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let nouveau = UUID()
        self.stableID = nouveau
        return nouveau
    }

    /// URL du fichier de la pièce. `nil` pour une pièce `link`, qui n'a pas de
    /// fichier — c'est son `linkURL` qui porte la cible.
    var fileURL: URL? {
        guard !filePath.isEmpty, kind != AttachmentCopyPolicy.linkKind else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    /// L'URL du lien, pour une pièce `link`. Le champ `filePath` sert de
    /// support : une pièce lien n'a pas de fichier, et ajouter une colonne
    /// `linkURL` pour la même information aurait créé deux vérités.
    var linkURL: URL? {
        guard kind == AttachmentCopyPolicy.linkKind else { return nil }
        return URL(string: filePath)
    }

    /// La pièce est copiée dans le dossier de l'application (politique D5).
    var isCopiedIntoApp: Bool {
        AttachmentCopyPolicy.isCopied(path: filePath)
    }

    /// Le fichier pointé n'existe plus. Une pièce `link` n'est jamais
    /// orpheline : rien de local ne peut lui manquer.
    var isOrphan: Bool {
        guard kind != AttachmentCopyPolicy.linkKind else { return false }
        guard !filePath.isEmpty else { return true }
        return !FileManager.default.fileExists(atPath: filePath)
    }

    /// Le badge de la vignette du tiroir (`XLS`, `PDF`, `PNG`, `URL`…).
    var badge: String {
        AttachmentCopyPolicy.badge(forKind: kind, fileName: fileName)
    }

    /// Le ton du fond de la vignette.
    var badgeTone: AttachmentCopyPolicy.BadgeTone {
        AttachmentCopyPolicy.badgeTone(forKind: kind)
    }
}
