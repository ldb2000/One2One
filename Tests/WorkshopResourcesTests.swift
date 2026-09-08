import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La section `PIÈCES & CAPTURES` du dock (spec §7.2) : ce qu'elle liste, dans
/// quel ordre, et sous quels libellés.
@Suite("Section « Pièces & captures » du dock de l'atelier")
@MainActor
struct WorkshopResourcesTests {

    private func bac() throws -> (ModelContext, Meeting) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let reunion = Meeting(title: "Atelier", date: Date(), notes: "")
        reunion.kind = .workshop
        context.insert(reunion)
        try context.save()
        return (context, reunion)
    }

    /// Une pièce de séance déposée par quelqu'un.
    private func piece(_ nom: String,
                       kind: String,
                       par auteur: String,
                       to meeting: Meeting,
                       in context: ModelContext) -> MeetingAttachment {
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/\(nom)"), kind: kind)
        piece.addedByName = auteur
        piece.scope = .meeting
        context.insert(piece)
        piece.meeting = meeting
        return piece
    }

    /// Une capture de la séance, rangée sous son lot `slides` comme le veut le
    /// modèle (`MeetingAttachment.slides`).
    private func capture(t: Double,
                         source: CaptureSource,
                         ocr: String,
                         to meeting: Meeting,
                         in context: ModelContext) -> SlideCapture {
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = meeting
        let capture = SlideCapture(index: 0,
                                   capturedAt: Date(),
                                   imagePath: "/tmp/capture-\(Int(t)).png")
        capture.t = t
        capture.source = source
        capture.ocrText = ocr
        context.insert(capture)
        capture.attachment = lot
        return capture
    }

    @Test("Les pièces passent avant les captures, et le lot de captures n'est pas une ligne")
    func piecesBeforeCaptures() throws {
        let (context, reunion) = try bac()
        _ = piece("Archi_cible_Cléva.pdf", kind: "pdf", par: "Yann",
                  to: reunion, in: context)
        _ = capture(t: 1_270, source: .teams, ocr: "schéma réseau partagé",
                    to: reunion, in: context)
        try context.save()

        let lignes = ResourceItem.workshopRows(for: reunion)
        #expect(lignes.count == 2)
        #expect(lignes[0].name == "Archi_cible_Cléva.pdf")
        #expect(lignes[1].nature == .capture)
    }

    @Test("Un lien et une pièce de projet ne s'insèrent pas sur une planche")
    func linksAndProjectPiecesAreExcluded() throws {
        let (context, reunion) = try bac()
        let lien = piece("https://exemple.fr", kind: AttachmentCopyPolicy.linkKind,
                         par: "Yann", to: reunion, in: context)
        lien.filePath = "https://exemple.fr"
        _ = piece("Note.md", kind: "markdown", par: "Yann", to: reunion, in: context)
        try context.save()

        let lignes = ResourceItem.workshopRows(for: reunion)
        #expect(lignes.count == 1)
        #expect(lignes[0].name == "Note.md")
        // Et la règle elle-même, sur la ligne du lien.
        let toutes = ResourceItem.all(for: reunion)
        let ligneLien = try #require(toutes.first { $0.nature == .lien })
        #expect(ligneLien.isBoardInsertable == false)
    }

    @Test("Une capture porte son instant en titre et son outil en badge")
    func captureLabels() throws {
        let (context, reunion) = try bac()
        _ = capture(t: 1_270, source: .teams, ocr: "schéma réseau partagé",
                    to: reunion, in: context)
        try context.save()

        let ligne = try #require(ResourceItem.workshopRows(for: reunion).first)
        #expect(ligne.workshopTitle() == "Capture 21:10")
        #expect(ligne.workshopBadge(in: reunion) == "TEAMS")
        #expect(ligne.workshopSubtitle(in: reunion) == "schéma réseau partagé")
    }

    @Test("Une capture d'écran ordinaire garde le badge du fichier")
    func screenCaptureKeepsItsBadge() throws {
        let (context, reunion) = try bac()
        _ = capture(t: 60, source: .screen, ocr: "", to: reunion, in: context)
        try context.save()

        let ligne = try #require(ResourceItem.workshopRows(for: reunion).first)
        #expect(ligne.workshopBadge(in: reunion) == "PNG")
        // Jamais de sous-titre vide : la ligne dirait alors moins que rien.
        #expect(ligne.workshopSubtitle(in: reunion) == "capture d'écran de la séance")
    }

    @Test("Une pièce dit qui l'a déposée")
    func pieceSubtitle() throws {
        let (context, reunion) = try bac()
        let sansAuteur = piece("Sans_auteur.pdf", kind: "pdf", par: "",
                               to: reunion, in: context)
        _ = piece("Archi.pdf", kind: "pdf", par: "Yann", to: reunion, in: context)
        try context.save()

        let lignes = ResourceItem.workshopRows(for: reunion)
        let avec = try #require(lignes.first { $0.name == "Archi.pdf" })
        #expect(avec.workshopSubtitle(in: reunion) == "déposé par Yann")
        #expect(avec.workshopBadge(in: reunion) == "PDF")
        let sans = try #require(lignes.first { $0.name == sansAuteur.fileName })
        #expect(sans.workshopSubtitle(in: reunion) == "déposé dans la séance")
    }
}
