import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// `Tout exporter` de l'encart de clôture de 6b (spec §7.3 : « Exports
/// proposés : PNG, SVG, `.excalidraw` — en secours seulement, le format de
/// référence reste la réunion »).
///
/// Tout se passe sur un **dossier temporaire** : ce lot n'ouvre aucune session
/// graphique et ne touche pas au `recordings/` de production.
@Suite("Atelier — Tout exporter")
@MainActor
struct WorkshopExportAllTests {

    private func bac() throws -> (ModelContext, BoardStore, URL) {
        let conteneur = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("lot18-export-\(UUID().uuidString)", isDirectory: true)
        return (ModelContext(conteneur), BoardStore(recordingsRoot: racine), racine)
    }

    /// Un PNG minuscule mais valide : l'export en copie les octets tels quels.
    private var pngMinimal: Data {
        Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
        """) ?? Data()
    }

    @Test("Le dossier porte une image, une scène et un index par planche")
    func bundleCarriesImagesScenesAndIndex() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Cible d'architecture GitLab",
                              date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        reunion.meetingDurationSeconds = 3_720
        context.insert(reunion)

        for (index, couple) in [("Périmètre actuel", 495.0),
                                ("Flux réseau", 1_180.0)].enumerated() {
            let planche = Board(index: index, title: couple.0, mode: .sketch,
                                t: couple.1, authorNames: "Yann")
            planche.caption = "Croquis — 2 boîtes"
            context.insert(planche)
            planche.meeting = reunion
            try magasin.save(scene: BoardScene.scene(boxes: [
                .init(x: 0, y: 0, width: 100, height: 40, text: couple.0)]),
                             board: planche, meetingStableID: reunion.ensuredStableID)
            try magasin.saveThumbnail(pngMinimal, board: planche,
                                      meetingStableID: reunion.ensuredStableID)
            magasin.resetThumbnailClock()
        }

        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        #expect(bilan.imageCount == 2)
        #expect(bilan.sceneCount == 2)

        let contenu = try FileManager.default.contentsOfDirectory(atPath: bilan.folder.path)
        #expect(contenu.contains("index.md"))
        #expect(contenu.filter { $0.hasSuffix(".png") }.count == 2)
        #expect(contenu.filter { $0.hasSuffix(".excalidraw.json") }.count == 2)
        // Les noms sont numérotés : le dossier se lit dans l'ordre du temps.
        #expect(contenu.contains { $0.hasPrefix("01-") })
        #expect(contenu.contains { $0.hasPrefix("02-") })

        let index = try String(contentsOf: bilan.indexPath, encoding: .utf8)
        let posPerimetre = try #require(index.range(of: "Périmètre actuel")).lowerBound
        let posFlux = try #require(index.range(of: "Flux réseau")).lowerBound
        #expect(posPerimetre < posFlux)             // critère chantier 6 n° 5
        #expect(index.contains("08:15"))
        #expect(index.contains("Croquis — 2 boîtes"))
        #expect(index.contains("![Périmètre actuel](01-"))
        // `.drawio` est hors v1 (décision D6) : il n'apparaît nulle part.
        #expect(!index.localizedCaseInsensitiveContains("drawio"))
    }

    @Test("Les captures et les pièces de la séance sont citées dans l'index")
    func indexAlsoListsCapturesAndPieces() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Atelier", date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        reunion.meetingDurationSeconds = 3_720
        context.insert(reunion)

        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: reunion.date,
                                   imagePath: "/tmp/slides/c.png")
        capture.t = 1_270
        capture.ocrText = "partage de Cléva — schéma réseau partagé"
        context.insert(capture)
        capture.attachment = lot

        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        let index = try String(contentsOf: bilan.indexPath, encoding: .utf8)
        #expect(index.contains("21:10"))
        #expect(index.contains("Capture — partage de Cléva"))
        #expect(bilan.imageCount == 0)
        #expect(bilan.sceneCount == 0)
    }

    @Test("Une planche sans vignette n'empêche pas l'export")
    func missingThumbnailDoesNotBreakTheExport() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let planche = Board(index: 0, title: "Sans vignette", mode: .ink, t: 0)
        context.insert(planche)
        planche.meeting = reunion

        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        #expect(bilan.imageCount == 0)
        // Une planche jamais dessinée exporte tout de même une scène vide :
        // le dossier doit refléter la séance, trous compris.
        #expect(bilan.sceneCount == 1)
        let index = try String(contentsOf: bilan.indexPath, encoding: .utf8)
        #expect(index.contains("Sans vignette"))
        #expect(!index.contains("!["))
    }

    @Test("Un titre de planche impossible à écrire sur disque est assaini")
    func unsafeTitlesAreSanitized() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Flux / DMZ : cible", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let planche = Board(index: 0, title: "Flux / DMZ", mode: .diagram, t: 0)
        context.insert(planche)
        planche.meeting = reunion
        try magasin.save(scene: BoardScene.empty, board: planche,
                         meetingStableID: reunion.ensuredStableID)

        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        #expect(!bilan.folder.lastPathComponent.contains("/"))
        #expect(!bilan.folder.lastPathComponent.contains(":"))
        let contenu = try FileManager.default.contentsOfDirectory(atPath: bilan.folder.path)
        #expect(contenu.contains("01-Flux - DMZ.excalidraw.json"))
    }

    @Test("Le nom du dossier porte le titre de la réunion et sa date")
    func folderNameCarriesTitleAndDate() {
        let nom = WorkshopExport.folderName(
            meetingTitle: "Cible d'architecture GitLab",
            date: Date(timeIntervalSince1970: 1_788_523_200))
        #expect(nom.hasPrefix("Cible d'architecture GitLab"))
        #expect(nom.contains("2026-09-04"))
        #expect(WorkshopExport.folderName(meetingTitle: "   ", date: Date())
                .hasPrefix("Atelier"))
    }
}
