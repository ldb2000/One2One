import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La migration paresseuse des pièces antérieures à D5 (ADR
/// `2026-09-07-pieces-copiees-jamais-referencees.md`).
///
/// Elle tourne à l'ouverture de l'espace Ressources, pas au lancement : migrer
/// 500 réunions au démarrage bloquerait l'app pour un bénéfice nul sur les
/// réunions qu'on ne consulte plus. Deux cas et deux seulement — la source
/// existe, on copie ; elle a disparu, la pièce reste **visible** et orpheline.
/// Jamais de suppression.
@Suite("Migration paresseuse des pièces référencées")
@MainActor
struct AttachmentMigrationTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-mig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeSourceFile(named nom: String, contenu: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-migsrc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(nom)
        try contenu.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeMeeting(in context: ModelContext) -> Meeting {
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        context.insert(reunion)
        return reunion
    }

    /// Une pièce « ancienne mode » : chemin d'origine + signet, aucune
    /// métadonnée. C'est exactement ce que produisait
    /// `MeetingAttachmentService.importDocument` avant D5.
    private func makeLegacyAttachment(at url: URL,
                                      in reunion: Meeting,
                                      context: ModelContext) -> MeetingAttachment {
        let piece = MeetingAttachment(url: url, kind: "text")
        piece.meeting = reunion
        context.insert(piece)
        return piece
    }

    // MARK: - Source présente

    @Test("Source présente : la pièce est copiée et son chemin réécrit")
    func sourcePresente() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "ancien.txt", contenu: "0123456789")
        let piece = makeLegacyAttachment(at: source, in: reunion, context: context)
        let cheminAvant = piece.filePath

        let bilan = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)

        #expect(bilan.copied == 1)
        #expect(bilan.orphaned == 0)
        #expect(piece.filePath != cheminAvant)
        #expect(AttachmentCopyPolicy.isCopied(path: piece.filePath, base: base))
        #expect(FileManager.default.fileExists(atPath: piece.filePath))
        #expect(piece.byteCount == 10)
        #expect(piece.mimeType == "text/plain")
        #expect(piece.bookmarkData == nil)
        #expect(!piece.isOrphan)
        // Le nom affiché ne change pas : la copie est un détail de stockage.
        #expect(piece.fileName == "ancien.txt")
    }

    @Test("La migration est idempotente")
    func idempotente() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "ancien.txt", contenu: "x")
        let piece = makeLegacyAttachment(at: source, in: reunion, context: context)

        _ = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)
        let cheminApresPremierPassage = piece.filePath
        let bilan = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)

        #expect(bilan.copied == 0)
        #expect(bilan.orphaned == 0)
        #expect(piece.filePath == cheminApresPremierPassage)
    }

    @Test("Une pièce déjà copiée n'est pas retouchée")
    func dejaCopiee() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "neuf.txt", contenu: "x")
        let piece = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)
        let chemin = piece.filePath

        let bilan = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)

        #expect(bilan.copied == 0)
        #expect(piece.filePath == chemin)
    }

    // MARK: - Source absente

    @Test("Source absente : la pièce reste, orpheline, sans exception")
    func sourceAbsente() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let fantome = URL(fileURLWithPath: "/tmp/onetoone-parti-\(UUID().uuidString).pdf")
        let piece = makeLegacyAttachment(at: fantome, in: reunion, context: context)

        let bilan = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)

        #expect(bilan.copied == 0)
        #expect(bilan.orphaned == 1)
        // Rien n'est supprimé : on préfère une ligne qui dit « ce document
        // manque » à une ligne supprimée qui ne dit plus rien.
        #expect(reunion.attachments.count == 1)
        #expect(piece.filePath == fantome.path)
        #expect(piece.isOrphan)
    }

    @Test("Une pièce lien n'est jamais orpheline et n'est pas copiée")
    func pieceLien() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let lien = MeetingAttachment(url: URL(fileURLWithPath: "/x"),
                                     kind: AttachmentCopyPolicy.linkKind)
        lien.filePath = "https://gitlab.example.com/board"
        lien.fileName = "Board GitLab — épiques migration"
        lien.meeting = reunion
        context.insert(lien)

        let bilan = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)

        #expect(bilan.copied == 0)
        #expect(bilan.orphaned == 0)
        #expect(!lien.isOrphan)
        #expect(lien.filePath == "https://gitlab.example.com/board")
        #expect(lien.linkURL?.host == "gitlab.example.com")
    }

    // MARK: - Reliaison manuelle

    @Test("Relier une orpheline la recopie sous la réunion")
    func relier() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let fantome = URL(fileURLWithPath: "/tmp/onetoone-parti-\(UUID().uuidString).txt")
        let piece = makeLegacyAttachment(at: fantome, in: reunion, context: context)
        #expect(piece.isOrphan)

        let retrouve = try makeSourceFile(named: "retrouve.txt", contenu: "abc")
        try AttachmentMigration.relink(piece, to: retrouve, in: context, base: base)

        #expect(!piece.isOrphan)
        #expect(AttachmentCopyPolicy.isCopied(path: piece.filePath, base: base))
        #expect(piece.byteCount == 3)
        #expect(piece.fileName == "retrouve.txt")
    }

    /// Une pièce sans `stableID` (toutes les lignes antérieures) doit en
    /// recevoir un : sans lui, `Citer` ne saurait pas quoi mettre dans le
    /// `sourceRef` de la puce insérée dans la note.
    @Test("La migration backfille les identifiants stables")
    func backfillDesIdentifiants() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let fantome = URL(fileURLWithPath: "/tmp/onetoone-parti-\(UUID().uuidString).pdf")
        let piece = makeLegacyAttachment(at: fantome, in: reunion, context: context)
        piece.stableID = nil

        _ = AttachmentMigration.migrate(meeting: reunion, in: context, base: base)

        #expect(piece.stableID != nil)
    }
}
