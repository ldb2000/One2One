import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La copie systématique à l'import (D5, ADR
/// `2026-09-07-pieces-copiees-jamais-referencees.md`).
///
/// Le test qui compte est le dernier : **supprimer l'original ne rend pas la
/// pièce illisible**. C'est exactement ce que l'ancienne politique — signet
/// vers le fichier d'origine — ne savait pas tenir, et sans quoi ni « À
/// l'écran », ni l'annotation, ni l'épinglage ne peuvent exister.
@Suite("Import d'une pièce de séance : la copie")
@MainActor
struct AttachmentCopyImportTests {

    // MARK: - Décor

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Une racine temporaire tenant lieu d'`Application Support/OneToOne` : les
    /// tests n'écrivent jamais dans le dossier réel de l'utilisateur.
    private func makeBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeSourceFile(named nom: String, contenu: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-src-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Tests

    @Test("Le fichier est copié sous recordings/<uuid>/documents")
    func fichierCopie() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "Chiffrage_Marine_v3.txt", contenu: "21 000 €")

        let piece = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)

        let attendu = base.appendingPathComponent(
            AttachmentCopyPolicy.documentsSubpath(meetingStableID: reunion.ensuredStableID))
        #expect(piece.filePath.hasPrefix(attendu.path + "/"))
        #expect(piece.filePath != source.path)
        #expect(FileManager.default.fileExists(atPath: piece.filePath))
        #expect(AttachmentCopyPolicy.isCopied(path: piece.filePath, base: base))
    }

    @Test("Les métadonnées du modèle cible sont renseignées")
    func metadonnees() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let settings = AppSettings()
        settings.ownerName = "Sylvain Marchand"
        context.insert(settings)
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "note.txt", contenu: "0123456789")

        let piece = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)

        #expect(piece.scope == .meeting)
        #expect(piece.mimeType == "text/plain")
        #expect(piece.byteCount == 10)
        #expect(piece.addedByName == "Sylvain Marchand")
        #expect(piece.kind == "text")
        // Le nom affiché reste celui du fichier d'origine, pas le nom horodaté
        // de la copie : c'est ce nom-là qu'on reconnaît dans le tiroir.
        #expect(piece.fileName == "note.txt")
        // Un signet vers une copie interne n'a aucune valeur, et son absence
        // est le signal le plus simple que la pièce relève de D5.
        #expect(piece.bookmarkData == nil)
        #expect(piece.stableID != nil)
    }

    @Test("Sans nom de propriétaire réglé, le champ reste vide")
    func sansProprietaire() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "a.txt", contenu: "x")

        let piece = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)
        #expect(piece.addedByName == "")
    }

    /// Le test qui justifie l'ADR.
    @Test("Supprimer l'original ne rend pas la pièce illisible")
    func originalSupprime() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "devis.txt", contenu: "40 000 €")

        let piece = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)
        try FileManager.default.removeItem(at: source.deletingLastPathComponent())

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: piece.filePath))
        let relu = try String(contentsOf: URL(fileURLWithPath: piece.filePath), encoding: .utf8)
        #expect(relu == "40 000 €")
        // Et la pièce n'est pas orpheline : c'est la copie qui compte.
        #expect(!piece.isOrphan)
    }

    @Test("Deux imports du même fichier ne s'écrasent pas")
    func deuxImports() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let source = try makeSourceFile(named: "doublon.txt", contenu: "x")

        let a = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)
        let b = try MeetingAttachmentService.attachDocument(
            url: source, into: reunion, context: context, base: base)

        #expect(a.filePath != b.filePath)
        #expect(FileManager.default.fileExists(atPath: a.filePath))
        #expect(FileManager.default.fileExists(atPath: b.filePath))
    }

    @Test("Une source illisible échoue sans insérer de ligne")
    func sourceAbsente() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let reunion = makeMeeting(in: context)
        let fantome = URL(fileURLWithPath: "/tmp/onetoone-absent-\(UUID().uuidString).txt")

        #expect(throws: (any Error).self) {
            _ = try MeetingAttachmentService.attachDocument(
                url: fantome, into: reunion, context: context, base: base)
        }
        // Aucune ligne à moitié créée : une pièce sans fichier ne se distingue
        // pas d'une pièce orpheline, et le tiroir proposerait de « relier » un
        // document qui n'a jamais existé.
        #expect(reunion.attachments.isEmpty)
    }
}
