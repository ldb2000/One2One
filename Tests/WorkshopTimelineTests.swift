import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La frise de l'écran 6b (`6b-atelier-planche-de-seance.png`, spec §7.3) : la
/// fusion des trois sources d'éléments produits, dans l'**ordre du temps**.
///
/// C'est la moitié testable du critère n° 5 du chantier 6 (« le rapport
/// d'atelier contient les planches dans l'ordre du temps ») : la variable
/// `{{planches}}` rend cette liste, dans cet ordre.
@Suite("Atelier — frise de la planche de séance (6b)")
@MainActor
struct WorkshopTimelineTests {

    private func contexte() throws -> ModelContext {
        let conteneur = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(conteneur)
    }

    @Test("Les trois sources sont fusionnées dans l'ordre du temps")
    func timelineMergesThreeSourcesInTimeOrder() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier",
                              date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        reunion.meetingDurationSeconds = 3_720
        context.insert(reunion)

        for (index, couple) in [("Périmètre actuel", 495.0),
                                ("Flux réseau", 1_180.0)].enumerated() {
            let planche = Board(index: index, title: couple.0, mode: .sketch,
                                t: couple.1, authorNames: "Yann")
            context.insert(planche)
            planche.meeting = reunion
        }

        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: reunion.date,
                                   imagePath: "/tmp/slides/c.png")
        capture.t = 1_270
        capture.ocrText = "partage de Cléva — schéma réseau partagé"
        capture.source = .teams
        context.insert(capture)
        capture.attachment = lot

        let lignes = WorkshopTimelineModel.rows(for: reunion)
        #expect(lignes.map(\.t) == [495, 1_180, 1_270])
        #expect(lignes[0].footer == "Croquis — Périmètre actuel")
        #expect(lignes[0].trailing == "Yann")
        #expect(lignes[0].nature == .board)
        #expect(lignes[2].nature == .capture)
        #expect(lignes[2].typeLabel == "Capture")
        #expect(lignes[2].title == "partage de Cléva")
        #expect(lignes[2].trailing == "texte extrait")
        #expect(lignes[2].caption == "partage de Cléva — schéma réseau partagé")
        #expect(WorkshopTimelineModel.producedCount(for: reunion) == 3)
    }

    @Test("Une pièce de séance est un élément produit, un lot de captures non")
    func attachmentRowsExcludeContainersAndProjectPieces() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier 2",
                              date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        reunion.meetingDurationSeconds = 3_720
        context.insert(reunion)

        // Le conteneur de captures : un lot, pas une pièce (règle du lot 17).
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion

        // Un lien : rien à montrer.
        let lien = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/lien"),
                                     kind: AttachmentCopyPolicy.linkKind)
        context.insert(lien)
        lien.meeting = reunion

        // Une pièce du projet : elle n'a pas été produite dans la séance.
        let projet = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/projet.pdf"),
                                       kind: "pdf")
        projet.scope = .project
        context.insert(projet)
        projet.meeting = reunion

        // La vraie pièce, épinglée à 13:00.
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Archi.pdf"),
                                      kind: "pdf")
        piece.scope = .meeting
        piece.addedByName = "Yann"
        piece.pinnedAtT = 780
        context.insert(piece)
        piece.meeting = reunion

        let lignes = WorkshopTimelineModel.rows(for: reunion)
        #expect(lignes.count == 1)
        #expect(lignes[0].nature == .attachment)
        #expect(lignes[0].t == 780)
        #expect(lignes[0].footer == "Pièce — Archi.pdf")
        #expect(lignes[0].trailing == "Yann")
    }

    @Test("Une pièce non épinglée s'horodate dans la séance, jamais au-delà")
    func attachmentTimecodeFallsBackWithinTheSession() {
        let debut = Date(timeIntervalSince1970: 1_788_523_200)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: 780, importedAt: debut,
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 780)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(600),
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 600)
        // Importée deux jours plus tard : bornée à la fin de la séance plutôt
        // que d'apparaître à 2880:00.
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(200_000),
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 3_720)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(-50),
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 0)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(900),
                                                  meetingDate: debut,
                                                  durationSeconds: 0) == 0)
    }

    @Test("Le manuscrit et la planche sans titre gardent un pied lisible")
    func boardRowsFallBackOnDefaults() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier 3", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)

        let sansTitre = Board(index: 2, title: "", mode: .diagram, t: 10)
        context.insert(sansTitre)
        sansTitre.meeting = reunion
        let manuscrit = Board(index: 3, title: "Notes de Patrice", mode: .ink,
                              t: 1_685, authorNames: "stylet")
        manuscrit.caption = "Manuscrit — 3 tracés"
        context.insert(manuscrit)
        manuscrit.meeting = reunion

        let lignes = WorkshopTimelineModel.rows(for: reunion)
        #expect(lignes[0].footer == "Schéma — Planche 3")
        #expect(lignes[0].trailing == "—")
        #expect(lignes[1].footer == "Manuscrit — Notes de Patrice")
        #expect(lignes[1].trailing == "stylet")
        #expect(lignes[1].caption == "Manuscrit — 3 tracés")
        #expect(lignes[1].boardMode == .ink)
    }

    @Test("Une capture sans texte extrait porte son timecode et le dit")
    func captureWithoutOCRSaysSo() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier 4", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: reunion.date,
                                   imagePath: "/tmp/slides/c.png")
        capture.t = 90
        context.insert(capture)
        capture.attachment = lot

        let ligne = try #require(WorkshopTimelineModel.rows(for: reunion).first)
        #expect(ligne.title == "Capture 01:30")
        #expect(ligne.trailing == "sans texte extrait")
        #expect(ligne.caption.isEmpty)
    }

    @Test("L'en-tête énumère la séance, au singulier comme au pluriel")
    func headerSummaryReadsLikeTheCapture() {
        let date = Date(timeIntervalSince1970: 1_788_523_200)
        let resume = WorkshopTimelineModel.headerSummary(
            date: date, durationSeconds: 3_720, participantCount: 4, producedCount: 9)
        #expect(resume.contains("1 h 02"))
        #expect(resume.contains("4 participants"))
        #expect(resume.contains("9 éléments produits"))

        let seul = WorkshopTimelineModel.headerSummary(
            date: date, durationSeconds: 2_820, participantCount: 1, producedCount: 1)
        #expect(seul.contains("47 min"))
        #expect(seul.contains("1 participant"))
        #expect(seul.contains("1 élément produit"))
        #expect(!seul.contains("participants"))

        // Une séance sans durée connue n'affiche pas « 0 min ».
        let sansDuree = WorkshopTimelineModel.headerSummary(
            date: date, durationSeconds: 0, participantCount: 2, producedCount: 0)
        #expect(!sansDuree.contains("min"))
        #expect(sansDuree.contains("aucun élément produit"))
    }

    @Test("Un atelier sans élément produit porte une invite, jamais une zone vide")
    func emptyWorkshopHasAnInvite() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier vide", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        #expect(WorkshopTimelineModel.rows(for: reunion).isEmpty)
        #expect(WorkshopTimelineModel.producedCount(for: reunion) == 0)
        #expect(!WorkshopTimelineModel.emptyInvite.isEmpty)
    }

    @Test("Deux éléments au même timecode gardent un ordre stable")
    func sameTimecodeKeepsAStableOrder() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier 5", date: Date())
        reunion.kind = .workshop
        reunion.meetingDurationSeconds = 600
        context.insert(reunion)

        let planche = Board(index: 0, title: "Zeta", mode: .sketch, t: 300)
        context.insert(planche)
        planche.meeting = reunion
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: reunion.date,
                                   imagePath: "/tmp/slides/c.png")
        capture.t = 300
        context.insert(capture)
        capture.attachment = lot
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Alpha.pdf"), kind: "pdf")
        piece.scope = .meeting
        piece.pinnedAtT = 300
        context.insert(piece)
        piece.meeting = reunion

        let natures = WorkshopTimelineModel.rows(for: reunion).map(\.nature)
        #expect(natures == [.board, .capture, .attachment])
    }
}
