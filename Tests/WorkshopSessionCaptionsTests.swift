import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les légendes pilotées par l'écran 6b : remplissage **calculé** à
/// l'ouverture, puis raffinement par l'assistant sur demande.
@Suite("Atelier — légendes pilotées par l'écran 6b")
@MainActor
struct WorkshopSessionCaptionsTests {

    private struct StubClient: AIClientProtocol {
        let response: String
        func send(prompt: String, settings: AppSettings) async throws -> String { response }
    }

    private func bac() throws -> (ModelContext, WorkshopState, Meeting, URL) {
        let conteneur = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(conteneur)
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("lot18-etat-\(UUID().uuidString)", isDirectory: true)
        let magasin = BoardStore(recordingsRoot: racine)
        let etat = WorkshopState(store: magasin, makeBridge: { _ in WhiteboardBridgeDouble() })

        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let planche = Board(index: 0, title: "Périmètre actuel", mode: .sketch, t: 495)
        context.insert(planche)
        planche.meeting = reunion
        try magasin.save(scene: BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60, text: "Runners GitLab"),
            .init(x: 300, y: 0, width: 200, height: 60, text: "Jenkins historique"),
        ]), board: planche, meetingStableID: reunion.ensuredStableID)
        return (context, etat, reunion, racine)
    }

    @Test("À l'ouverture, une planche sans légende en reçoit une, sans réseau")
    func missingCaptionsAreFilledOffline() throws {
        let (context, etat, reunion, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        #expect(etat.fillMissingCaptions(meeting: reunion, context: context) == 1)
        let planche = try #require(reunion.boards.first)
        #expect(planche.caption.hasPrefix("Croquis — "))
        #expect(planche.caption.contains("Runners GitLab"))
        // Idempotent : une légende déjà écrite n'est pas recouverte.
        #expect(etat.fillMissingCaptions(meeting: reunion, context: context) == 0)
    }

    @Test("Décrire les planches réécrit la légende, et se replie sans endpoint")
    func describeBoardsRefinesOrFallsBack() async throws {
        let (context, etat, reunion, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }

        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        await etat.describeBoards(
            meeting: reunion, settings: reglages, context: context,
            client: StubClient(
                response: #"{"caption":"Le périmètre CI/CD tel qu'il tourne aujourd'hui."}"#))
        #expect(reunion.boards.first?.caption == "Le périmètre CI/CD tel qu'il tourne aujourd'hui.")
        // Le drapeau d'occupation retombe : sinon les boutons resteraient gris.
        #expect(etat.isBusy == false)

        reglages.modelName = ""
        await etat.describeBoards(meeting: reunion, settings: reglages, context: context,
                                  client: StubClient(response: "jamais lu"))
        #expect(reunion.boards.first?.caption.hasPrefix("Croquis — ") == true)
    }
}
