import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Critère n° 5 du chantier 6 : « le rapport d'atelier contient les planches
/// dans l'ordre du temps ». Le lot 15 avait posé le bloc et la variable
/// `{{planches}}` ; le lot 18 y **ajoute** la légende et l'image, et fait
/// joindre les PNG des planches cochées.
@Suite("Atelier — les planches dans le rapport")
@MainActor
struct WorkshopReportBoardsTests {

    private func bac() throws -> (ModelContext, BoardStore, URL) {
        let conteneur = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("lot18-rapport-\(UUID().uuidString)", isDirectory: true)
        return (ModelContext(conteneur), BoardStore(recordingsRoot: racine), racine)
    }

    private var pngMinimal: Data {
        Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
        """) ?? Data()
    }

    @Test("La légende accompagne chaque planche, dans l'ordre du temps")
    func captionsTravelWithTheBoards() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Cible d'architecture GitLab",
                              date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        context.insert(reunion)

        let tardive = Board(index: 0, title: "Flux réseau", mode: .diagram,
                            t: 1_180, authorNames: "Claire-Amélie")
        tardive.caption = "Schéma — 3 boîtes (DMZ, Zone applicative, Zone données), 2 liaisons"
        context.insert(tardive)
        tardive.meeting = reunion

        let precoce = Board(index: 1, title: "Périmètre actuel", mode: .sketch,
                            t: 495, authorNames: "Yann")
        precoce.caption = "Croquis — 2 boîtes (Runners partagés, Jenkins historique)"
        context.insert(precoce)
        precoce.meeting = reunion

        let entrees = ReportOptionalBlocks.boards(of: reunion, store: magasin)
        #expect(entrees.map(\.title) == ["Périmètre actuel", "Flux réseau"])
        #expect(entrees[0].caption.hasPrefix("Croquis — "))

        let md = ReportOptionalBlocks.boardsMarkdown(entrees)
        let posPerimetre = try #require(md.range(of: "Périmètre actuel")).lowerBound
        let posFlux = try #require(md.range(of: "Flux réseau")).lowerBound
        #expect(posPerimetre < posFlux)
        #expect(md.contains("08:15"))
        #expect(md.contains("Runners partagés"))
        #expect(md.contains("Zone applicative"))
    }

    @Test("L'image n'entre en annexe que pour une planche cochée")
    func onlyCheckedBoardsEmbedTheirImage() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)

        let cochee = Board(index: 0, title: "Cochée", mode: .sketch, t: 100)
        cochee.includeInReport = true
        context.insert(cochee)
        cochee.meeting = reunion
        try magasin.saveThumbnail(pngMinimal, board: cochee,
                                  meetingStableID: reunion.ensuredStableID)
        magasin.resetThumbnailClock()

        let libre = Board(index: 1, title: "Non cochée", mode: .sketch, t: 200)
        context.insert(libre)
        libre.meeting = reunion
        try magasin.saveThumbnail(pngMinimal, board: libre,
                                  meetingStableID: reunion.ensuredStableID)

        let entrees = ReportOptionalBlocks.boards(of: reunion, store: magasin)
        #expect(entrees.count == 2)
        // Le bloc cite les deux planches — c'est ce que la séance a produit.
        let html = ReportOptionalBlocks.boardsHTML(entrees, embedImages: true)
        #expect(html.contains("Cochée"))
        #expect(html.contains("Non cochée"))
        // Une seule image : la case décide de l'annexe, pas de la citation.
        #expect(html.components(separatedBy: "data:image/png;base64,").count - 1 == 1)
        // Sans `embedImages`, aucune image — c'est le cas de l'export mail.
        #expect(!ReportOptionalBlocks.boardsHTML(entrees, embedImages: false)
                .contains("data:image/png;base64,"))
    }

    @Test("Les PNG des planches cochées partent en annexe du rapport")
    func checkedBoardImagesAreAttached() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let cochee = Board(index: 0, title: "Cochée", mode: .sketch, t: 100)
        cochee.includeInReport = true
        context.insert(cochee)
        cochee.meeting = reunion
        try magasin.saveThumbnail(pngMinimal, board: cochee,
                                  meetingStableID: reunion.ensuredStableID)
        magasin.resetThumbnailClock()
        let libre = Board(index: 1, title: "Non cochée", mode: .ink, t: 200)
        context.insert(libre)
        libre.meeting = reunion
        try magasin.saveThumbnail(pngMinimal, board: libre,
                                  meetingStableID: reunion.ensuredStableID)

        let chemins = ReportSendPreparation.boardImagePaths(for: reunion, store: magasin)
        #expect(chemins.count == 1)
        #expect(chemins[0].hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: chemins[0]))
    }

    @Test("La variable {{planches}} rend la légende")
    func variableRendersTheCaption() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let planche = Board(index: 0, title: "Périmètre actuel", mode: .sketch,
                            t: 495, authorNames: "Yann")
        planche.caption = "Croquis — 2 boîtes (Runners partagés, Jenkins historique)"
        context.insert(planche)
        planche.meeting = reunion
        _ = magasin

        let rendu = try #require(RefonteReportVariables.resolve(
            name: "planches", meeting: reunion, context: context, audience: .projectTeam))
        #expect(rendu.contains("08:15"))
        #expect(rendu.contains("Périmètre actuel"))
        #expect(rendu.contains("Runners partagés"))
    }

    @Test("Une planche sans légende ne laisse pas de ligne vide")
    func boardWithoutCaptionLeavesNoEmptyLine() throws {
        let (context, magasin, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let planche = Board(index: 0, title: "Sans légende", mode: .sketch, t: 60)
        context.insert(planche)
        planche.meeting = reunion

        let md = ReportOptionalBlocks.boardsMarkdown(
            ReportOptionalBlocks.boards(of: reunion, store: magasin))
        #expect(md.contains("Sans légende"))
        #expect(!md.contains("\n\n"))
        #expect(!md.hasSuffix("\n"))
    }
}
