import Foundation
import SwiftData
import os

private let migrationLog = Logger(subsystem: "com.onetoone.app", category: "attachment-migration")

/// Migration **paresseuse** des pièces de séance antérieures à la décision D5
/// (ADR `2026-09-07-pieces-copiees-jamais-referencees.md`).
///
/// Appelée à l'ouverture de l'espace Ressources d'une réunion, et non au
/// lancement de l'application : migrer 500 réunions au démarrage bloquerait
/// l'app pour un bénéfice nul sur celles qu'on ne consulte plus.
///
/// Deux cas, et deux seulement :
///
/// - **la source existe** → elle est copiée sous `recordings/<uuid>/documents/`,
///   `filePath` est réécrit, `byteCount` et `mimeType` complétés, le signet
///   effacé ;
/// - **la source a disparu** → **rien n'est supprimé**. La pièce reste visible
///   et devient *orpheline* (état calculé, cf. `AttachmentState.swift`) ; le
///   tiroir affiche « Fichier introuvable — relier ».
///
/// Aucun drapeau « migrée » n'est persisté : c'est le chemin qui dit la vérité
/// (`AttachmentCopyPolicy.isCopied`). Un drapeau mentirait dès qu'on restaure
/// une sauvegarde sur une autre machine.
@MainActor
enum AttachmentMigration {

    /// Ce qu'un passage de migration a fait. Sert aux journaux et aux tests ;
    /// l'interface, elle, ne montre rien — une migration réussie est invisible.
    struct Outcome: Equatable, Sendable {
        /// Pièces effectivement copiées pendant ce passage.
        var copied: Int = 0
        /// Pièces dont la source a disparu, laissées en place et orphelines.
        var orphaned: Int = 0
        /// Pièces déjà conformes, ignorées.
        var untouched: Int = 0
    }

    /// Migre les pièces de `meeting`. Idempotent : un second appel ne fait
    /// rien, parce qu'une pièce copiée est reconnue à son chemin.
    @discardableResult
    static func migrate(meeting: Meeting,
                        in context: ModelContext,
                        base: URL = AttachmentImporter.baseDirectory()) -> Outcome {
        var bilan = Outcome()
        var aEcrire = false

        for piece in meeting.attachments {
            // Un identifiant stable pour toutes : sans lui, `Citer` ne saurait
            // pas quoi mettre dans le `sourceRef` de la puce insérée dans la
            // note (spec §4.2).
            if piece.stableID == nil {
                _ = piece.ensuredStableID
                aEcrire = true
            }

            // Les liens n'ont pas de fichier ; les lots de captures (`slides`)
            // portent un chemin virtuel et leurs PNG vivent déjà sous
            // `recordings/<uuid>/slides/`.
            guard piece.kind != AttachmentCopyPolicy.linkKind,
                  piece.kind != AttachmentCopyPolicy.slidesKind,
                  !piece.filePath.isEmpty else {
                bilan.untouched += 1
                continue
            }

            if AttachmentCopyPolicy.isCopied(path: piece.filePath, base: base) {
                bilan.untouched += 1
                continue
            }

            let source = resolvedSource(for: piece)
            guard FileManager.default.fileExists(atPath: source.path) else {
                bilan.orphaned += 1
                migrationLog.info("orpheline: \(piece.fileName, privacy: .public)")
                continue
            }

            do {
                try copy(piece, from: source, into: meeting, base: base)
                bilan.copied += 1
                aEcrire = true
            } catch {
                // Un échec de copie (disque plein, permission) ne fait pas
                // échouer l'ouverture de l'espace : la pièce reste référencée,
                // le prochain passage réessaiera.
                migrationLog.error("copie impossible pour \(piece.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                bilan.untouched += 1
            }
        }

        if aEcrire { try? context.save() }
        if bilan.copied > 0 || bilan.orphaned > 0 {
            migrationLog.info("migrate: meeting=\(meeting.ensuredStableID.uuidString, privacy: .public) copiées=\(bilan.copied) orphelines=\(bilan.orphaned)")
        }
        return bilan
    }

    /// Relie une pièce orpheline à un fichier désigné par l'utilisateur : le
    /// nouveau fichier est **copié**, comme n'importe quel import.
    static func relink(_ piece: MeetingAttachment,
                       to url: URL,
                       in context: ModelContext,
                       base: URL = AttachmentImporter.baseDirectory()) throws {
        guard let meeting = piece.meeting else { return }
        try copy(piece, from: url, into: meeting, base: base, renaming: true)
        try context.save()
    }

    // MARK: - Interne

    /// Copie `source` dans la réunion et réécrit la ligne.
    ///
    /// - Parameter renaming: vrai quand l'utilisateur a désigné un autre
    ///   fichier (reliaison) — le nom affiché suit alors le nouveau fichier.
    ///   Faux en migration : la copie est un détail de stockage, le nom
    ///   affiché ne doit pas changer sous les yeux de l'utilisateur.
    private static func copy(_ piece: MeetingAttachment,
                             from source: URL,
                             into meeting: Meeting,
                             base: URL,
                             renaming: Bool = false) throws {
        let copie = try AttachmentImporter.copyIntoAppSupport(
            source: source,
            bucket: .meetingDocuments(meetingStableID: meeting.ensuredStableID),
            base: base)

        if renaming { piece.fileName = source.lastPathComponent }
        piece.filePath = copie.path
        piece.bookmarkData = nil
        piece.scope = .meeting
        if piece.mimeType.isEmpty {
            piece.mimeType = AttachmentCopyPolicy.mimeType(forExtension: source.pathExtension)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: copie.path)
        piece.byteCount = (attrs?[.size] as? NSNumber)?.intValue ?? piece.byteCount
        _ = piece.ensuredStableID
    }

    /// Le fichier d'origine, résolu par le signet quand il en existe un.
    ///
    /// C'est la dernière fois que `bookmarkData` sert : il donne à la migration
    /// une chance de retrouver un fichier simplement **déplacé**, ce que le
    /// chemin brut ne sait pas faire. Après la copie, il est effacé.
    private static func resolvedSource(for piece: MeetingAttachment) -> URL {
        let brut = URL(fileURLWithPath: piece.filePath)
        guard let signet = piece.bookmarkData else { return brut }
        var perime = false
        guard let resolue = try? URL(resolvingBookmarkData: signet,
                                     options: [.withSecurityScope],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &perime) else { return brut }
        return FileManager.default.fileExists(atPath: resolue.path) ? resolue : brut
    }
}
