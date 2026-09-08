import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le jeu de démonstration complet de l'écran 6a : ce que le lot 17 y ajoute.
@Suite("Jeu de démonstration de l'atelier, version lot 17")
@MainActor
struct WorkshopSeedLot17Tests {

    private func bac() throws -> (ModelContext, BoardStore, URL) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("semis-17-\(UUID().uuidString)", isDirectory: true)
        return (ModelContext(container), BoardStore(recordingsRoot: racine), racine)
    }

    @Test("La planche active porte les deux objets annotés de la capture")
    func annotatedBoard() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopComplete(in: context, store: store)
        let planches = BoardOrdering.sorted(reunion.boards)
        let active = try #require(planches.first { $0.index == 2 })
        let scene = try #require(store.loadScene(board: active, meetingStableID: reunion.ensuredStableID))

        let annotations = BoardAnnotation.list(in: scene)
        #expect(annotations.count == 2)
        let risque = try #require(annotations.first { $0.kind == .risk })
        #expect(risque.text.hasPrefix("Jenkins à décommissionner"))
        let question = try #require(annotations.first { $0.kind == .question })
        #expect(question.text.hasPrefix("Qui porte la bascule ?"))
    }

    @Test("`Flux réseau` est un vrai Schéma : deux boîtes bleues et des connecteurs liés")
    func diagramBoardHasBoundConnectors() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopComplete(in: context, store: store)
        let planche = try #require(BoardOrdering.sorted(reunion.boards).first { $0.index == 1 })
        #expect(planche.mode == .diagram)
        #expect(planche.title == "Flux réseau")

        let scene = try #require(store.loadScene(board: planche,
                                                  meetingStableID: reunion.ensuredStableID))
        let data = try #require(scene.data(using: .utf8))
        let objet = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(objet["elements"] as? [[String: Any]])

        let fleches = elements.filter { ($0["type"] as? String) == "arrow" }
        #expect(fleches.count == 2)
        for fleche in fleches {
            #expect(fleche["startBinding"] as? [String: Any] != nil)
            #expect(fleche["endBinding"] as? [String: Any] != nil)
        }
        // Les boîtes bleues de la capture : le bleu vient de la palette.
        let bleu = WorkshopPalette.entries[1].hex
        #expect(elements.filter { ($0["strokeColor"] as? String) == bleu }.count >= 2)
    }

    @Test("`Notes de Patrice` est un Manuscrit : des tracés, avec leurs pressions")
    func inkBoardHasPressures() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopComplete(in: context, store: store)
        let planche = try #require(BoardOrdering.sorted(reunion.boards).first { $0.index == 3 })
        #expect(planche.mode == .ink)

        let scene = try #require(store.loadScene(board: planche,
                                                  meetingStableID: reunion.ensuredStableID))
        let data = try #require(scene.data(using: .utf8))
        let objet = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(objet["elements"] as? [[String: Any]])

        let traces = elements.filter { ($0["type"] as? String) == "freedraw" }
        #expect(traces.count == 3)
        for trace in traces {
            let points = try #require(trace["points"] as? [[Double]])
            let pressions = try #require(trace["pressures"] as? [Double])
            // Autant de pressions que de points, sinon le moteur ignore la
            // série entière.
            #expect(pressions.count == points.count)
            #expect(trace["simulatePressure"] as? Bool == false)
            #expect(pressions.allSatisfy { $0 > 0 && $0 <= 1 })
        }
    }

    @Test("La section « Pièces & captures » porte les deux lignes de la capture")
    func resourcesMatchTheCapture() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reunion = RefonteDemoSeed.seedWorkshopComplete(in: context, store: store)
        let lignes = ResourceItem.workshopRows(for: reunion)
        #expect(lignes.count == 2)

        let piece = try #require(lignes.first)
        #expect(piece.name == "Archi_cible_Cléva.pdf")
        #expect(piece.workshopBadge(in: reunion) == "PDF")
        #expect(piece.workshopSubtitle(in: reunion) == "déposé par Yann")
        // Le fichier est écrit : la ligne n'est pas orpheline dans le dock.
        #expect(!piece.isOrphan)
        #expect(piece.isBoardInsertable)

        let capture = try #require(lignes.last)
        #expect(capture.nature == .capture)
        #expect(capture.workshopTitle() == "Capture 21:10")
        #expect(capture.workshopBadge(in: reunion) == "TEAMS")
        #expect(capture.workshopSubtitle(in: reunion) == "schéma réseau partagé")
        #expect(capture.isBoardInsertable)
    }

    @Test("Semer deux fois ne duplique ni pièce ni capture")
    func seedingIsIdempotent() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        RefonteDemoSeed.seedWorkshopComplete(in: context, store: store)
        RefonteDemoSeed.seedWorkshopComplete(in: context, store: store)

        let reunions = try context.fetch(FetchDescriptor<Meeting>())
        #expect(reunions.count == 1)
        #expect(ResourceItem.workshopRows(for: reunions[0]).count == 2)
        #expect(reunions[0].boards.count == 4)
    }
}
