import XCTest
import SwiftData
@testable import OneToOne

final class OrphanCleanupServiceTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_listsAttachmentsWithMissingFiles() throws {
        let ctx = try makeContext()
        let existing = URL(fileURLWithPath: Bundle.main.executablePath ?? "/bin/sh")
        let a1 = MeetingAttachment(url: existing, kind: "document")
        ctx.insert(a1)
        let missingURL = URL(fileURLWithPath: "/tmp/onetoone-missing-\(UUID().uuidString)")
        let a2 = MeetingAttachment(url: missingURL, kind: "document")
        ctx.insert(a2)
        try ctx.save()

        let orphans = OrphanCleanupService.orphanAttachments(in: ctx)
        XCTAssertEqual(orphans.map(\.filePath), [missingURL.path])
    }

    /// Politique D5 (ADR `2026-09-07-pieces-copiees-jamais-referencees.md`) :
    /// une pièce **copiée** dont le fichier manque n'est pas candidate au
    /// nettoyage. C'est un incident — le tiroir la marque orpheline et propose
    /// de la relier — et non une ligne à effacer avec son texte extrait, ses
    /// chunks RAG et ses citations.
    @MainActor
    func test_copiedAttachmentIsNotACleanupCandidate() throws {
        let ctx = try makeContext()
        let interne = AttachmentImporter.baseDirectory()
            .appending(path: "recordings/\(UUID().uuidString)/documents/20260904-091500_a.pdf")
        let piece = MeetingAttachment(url: interne, kind: "pdf")
        ctx.insert(piece)
        try ctx.save()

        XCTAssertFalse(FileManager.default.fileExists(atPath: piece.filePath))
        XCTAssertTrue(OrphanCleanupService.orphanAttachments(in: ctx).isEmpty)
    }

    /// Une pièce `link` n'a pas de fichier : `fileExists` sur une URL rend
    /// toujours faux, et la proposer au nettoyage supprimerait tous les liens
    /// collés en séance.
    @MainActor
    func test_linkAttachmentIsNotACleanupCandidate() throws {
        let ctx = try makeContext()
        let lien = MeetingAttachment(url: URL(fileURLWithPath: "/x"),
                                     kind: AttachmentCopyPolicy.linkKind)
        lien.filePath = "https://gitlab.example.com/board"
        ctx.insert(lien)
        try ctx.save()

        XCTAssertTrue(OrphanCleanupService.orphanAttachments(in: ctx).isEmpty)
    }
}
