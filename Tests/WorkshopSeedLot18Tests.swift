import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le jeu de démonstration de l'écran 6b : ce que le lot 18 ajoute.
@Suite("Jeu de démonstration de l'atelier, version lot 18")
@MainActor
struct WorkshopSeedLot18Tests {

    private func bac() throws -> (ModelContext, BoardStore, URL) {
        let conteneur = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("semis-18-\(UUID().uuidString)", isDirectory: true)
        return (ModelContext(conteneur), BoardStore(recordingsRoot: racine), racine)
    }

    @Test("Le semis est idempotent et porte les éléments de la capture 6b")
    func seedIsIdempotentAndCarriesTheCapture() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        let seconde = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        #expect(reunion.ensuredStableID == seconde.ensuredStableID)
        #expect(reunion.boards.count == 4)
        #expect(reunion.participants.count == 4)

        // Le manuscrit porte ses deux lignes lisibles **et** ses tracés.
        let manuscrit = try #require(reunion.boards.first { $0.mode == .ink })
        let scene = try #require(magasin.loadScene(board: manuscrit,
                                                   meetingStableID: reunion.ensuredStableID))
        for ligne in RefonteDemoSeed.workshopInkLines { #expect(scene.contains(ligne)) }
        let inventaire = BoardCaptionBuilder.inventory(scene: scene)
        #expect(inventaire.strokes == 3)
        #expect(inventaire.notes == 2)

        // La capture Teams porte son texte extrait.
        let capture = try #require(reunion.attachments.flatMap(\.slides).first)
        #expect(capture.ocrText == RefonteDemoSeed.workshopCaptureOCR)

        // La pièce de Yann est épinglée dans la séance.
        let piece = try #require(reunion.attachments
            .first { $0.fileName == RefonteDemoSeed.workshopPieceName })
        #expect(piece.pinnedAtT == RefonteDemoSeed.workshopPiecePinnedAtT)
    }

    @Test("Chaque planche porte une légende calculée")
    func everyBoardCarriesACaption() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        for planche in BoardOrdering.sorted(reunion.boards) {
            #expect(planche.caption.hasPrefix("\(planche.mode.label) — "))
            #expect(!planche.caption.contains("planche vide"))
        }
        let manuscrit = try #require(reunion.boards.first { $0.mode == .ink })
        #expect(manuscrit.caption.contains("3 tracés"))
        #expect(manuscrit.caption.contains("3 runners → autoscale ?"))
    }

    @Test("La frise de 6b compte planches, capture et pièce, dans l'ordre du temps")
    func timelineCountsEverythingInTimeOrder() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        let lignes = WorkshopTimelineModel.rows(for: reunion)
        // 4 planches + 1 capture + 1 pièce.
        #expect(lignes.count == 6)
        #expect(WorkshopTimelineModel.producedCount(for: reunion) == 6)
        #expect(lignes.map(\.t) == lignes.map(\.t).sorted())
        let pieds = lignes.map(\.footer)
        #expect(pieds.allSatisfy { !$0.isEmpty })
        #expect(pieds.contains("Croquis — Périmètre actuel"))
        #expect(pieds.contains("Schéma — Flux réseau"))
        #expect(pieds.contains("Manuscrit — Notes de Patrice"))
        #expect(pieds.contains("Capture — partage de Cléva"))
        #expect(pieds.contains("Pièce — \(RefonteDemoSeed.workshopPieceName)"))

        // Le pied du manuscrit dit `stylet`, comme sur la capture.
        let manuscrit = try #require(lignes.first { $0.footer.hasPrefix("Manuscrit") })
        #expect(manuscrit.trailing == "stylet")
        let capture = try #require(lignes.first { $0.nature == .capture })
        #expect(capture.trailing == "texte extrait")
        #expect(MeetingPlayhead.mmss(capture.t) == "21:10")
    }

    @Test("Joindre au rapport coche les six lignes de la séance semée")
    func attachingCoversTheSeededSession() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        // 4 planches + 1 capture : la pièce n'a pas de case, elle suit celle du
        // tiroir Ressources (`attachPinned`).
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 5)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion))
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 0)

        // Et le bloc de rapport cite les quatre planches, dans l'ordre du temps.
        let entrees = ReportOptionalBlocks.boards(of: reunion, store: magasin)
        #expect(entrees.count == 4)
        #expect(entrees.map(\.t) == entrees.map(\.t).sorted())
        let md = ReportOptionalBlocks.boardsMarkdown(entrees)
        #expect(md.contains("08:15"))
        #expect(md.contains("Croquis"))
    }

    @Test("Tout exporter écrit quatre scènes et un index pour la séance semée")
    func exportAllCoversTheSeededSession() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        #expect(bilan.sceneCount == 4)
        let index = try String(contentsOf: bilan.indexPath, encoding: .utf8)
        #expect(index.contains("Périmètre actuel"))
        #expect(index.contains("3 runners → autoscale ?"))
        #expect(!index.localizedCaseInsensitiveContains("drawio"))
    }
}
