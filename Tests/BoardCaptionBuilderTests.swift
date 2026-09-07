import Testing
import Foundation
@testable import OneToOne

/// Client factice : aucun test de ce lot ne touche le réseau, MLX ou une
/// session graphique (programme §8).
private struct StubCaptionClient: AIClientProtocol {
    let response: String
    let throwError: Bool
    /// Vrai dès qu'une requête a été envoyée : sert à prouver qu'un endpoint
    /// non configuré n'appelle rien.
    final class Journal: @unchecked Sendable { var appels = 0 }
    let journal = Journal()

    init(_ response: String, throwError: Bool = false) {
        self.response = response
        self.throwError = throwError
    }

    func send(prompt: String, settings: AppSettings) async throws -> String {
        journal.appels += 1
        if throwError {
            throw NSError(domain: "stub", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "stub"])
        }
        return response
    }
}

/// La légende d'une planche (spec §7.2 : « l'assistant peut décrire les
/// planches dans le rapport » — « génère une légende textuelle à partir des
/// libellés d'objets »).
///
/// Deux étages, testés séparément : la légende **pure**, qui n'a besoin de
/// rien, et son raffinement par l'assistant, qui doit **toujours** retomber sur
/// la première.
@Suite("Atelier — légende d'une planche")
@MainActor
struct BoardCaptionBuilderTests {

    // MARK: - Légende pure

    @Test("Croquis : des boîtes, des liaisons, une question et un risque")
    func sketchCaptionCountsEverything() {
        let scene = RefonteDemoSeed.workshopAnnotatedTargetScene()
        let legende = BoardCaptionBuilder.caption(mode: .sketch, scene: scene)
        #expect(legende.hasPrefix("Croquis — "))
        #expect(legende.contains("6 boîtes"))
        #expect(legende.contains("Runners GitLab"))
        #expect(legende.contains("2 liaisons"))
        #expect(legende.contains("1 question ouverte"))
        #expect(legende.contains("1 risque"))
    }

    @Test("Schéma : les connecteurs liés comptent comme des liaisons")
    func diagramCaptionCountsBoundConnectors() {
        let legende = BoardCaptionBuilder.caption(mode: .diagram,
                                                  scene: RefonteDemoSeed.workshopDiagramScene())
        #expect(legende.hasPrefix("Schéma — "))
        #expect(legende.contains("3 boîtes"))
        #expect(legende.contains("2 liaisons"))
        #expect(legende.contains("DMZ"))
        #expect(!legende.contains("question"))
        #expect(!legende.contains("risque"))
    }

    @Test("Manuscrit : des tracés, pas des boîtes")
    func inkCaptionCountsStrokes() {
        let legende = BoardCaptionBuilder.caption(mode: .ink,
                                                  scene: RefonteDemoSeed.workshopInkScene())
        #expect(legende.hasPrefix("Manuscrit — "))
        #expect(legende.contains("3 tracés"))
        #expect(!legende.contains("boîte"))
    }

    @Test("Les notes libres sont comptées et citées")
    func freeTextsAreCountedAndQuoted() {
        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 40,
                  text: "3 runners → autoscale ?", freeText: true),
            .init(x: 0, y: 80, width: 200, height: 40,
                  text: "+ VPN April à vérifier", freeText: true),
        ], seed: 9)
        let legende = BoardCaptionBuilder.caption(mode: .ink, scene: scene)
        #expect(legende.contains("2 notes"))
        #expect(legende.contains("3 runners → autoscale ?"))
        #expect(legende.contains("+ VPN April à vérifier"))
    }

    @Test("Le singulier est respecté")
    func singularsAreRespected() {
        let scene = BoardScene.scene(
            boxes: [.init(x: 0, y: 0, width: 100, height: 40, text: "Nexus"),
                    .init(x: 300, y: 0, width: 100, height: 40, text: "Jenkins",
                          annotation: .risk)],
            connectors: [.init(from: 0, to: 1)],
            seed: 7)
        let legende = BoardCaptionBuilder.caption(mode: .sketch, scene: scene)
        #expect(legende.contains("2 boîtes"))
        #expect(legende.contains("1 liaison,") || legende.hasSuffix("1 liaison"))
        #expect(!legende.contains("1 liaisons"))
        #expect(legende.contains("1 risque"))
        #expect(!legende.contains("1 risques"))
    }

    @Test("Au-delà de trois libellés, l'énumération s'arrête sur une ellipse")
    func labelListIsCappedAtThree() {
        let scene = BoardScene.scene(boxes: (0..<5).map { rang in
            BoardScene.Box(x: Double(rang) * 200, y: 0, width: 150, height: 40,
                           text: "Boîte \(rang)")
        }, seed: 11)
        let legende = BoardCaptionBuilder.caption(mode: .diagram, scene: scene)
        #expect(legende.contains("5 boîtes"))
        #expect(legende.contains("Boîte 0, Boîte 1, Boîte 2, …"))
        #expect(!legende.contains("Boîte 3"))
    }

    @Test("Une scène vide ou illisible ne lève jamais")
    func emptyOrBrokenSceneNeverThrows() {
        #expect(BoardCaptionBuilder.caption(mode: .sketch, scene: BoardScene.empty)
                == "Croquis — planche vide")
        #expect(BoardCaptionBuilder.caption(mode: .ink, scene: "{ pas du json")
                == "Manuscrit — planche vide")
        #expect(BoardCaptionBuilder.caption(mode: .diagram, scene: "")
                == "Schéma — planche vide")
    }

    @Test("Un objet supprimé ne compte pas")
    func deletedElementsAreIgnored() {
        let scene = """
        {"type":"excalidraw","version":2,"source":"OneToOne","elements":[
        {"id":"a","type":"rectangle","isDeleted":true},
        {"id":"b","type":"rectangle","isDeleted":false}
        ],"appState":{},"files":{}}
        """
        #expect(BoardCaptionBuilder.inventory(scene: scene).boxes == 1)
    }

    // MARK: - Raffinement par l'assistant

    @Test("L'assistant raffine la légende quand il répond du JSON strict")
    func assistantRefinesTheCaption() async {
        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        let client = StubCaptionClient(
            #"{"caption":"Croquis du périmètre GitLab actuel : trois runners partagés et Jenkins en dette."}"#)
        let legende = await BoardCaptionBuilder.refined(
            mode: .sketch, scene: RefonteDemoSeed.workshopAnnotatedTargetScene(),
            settings: reglages, client: client)
        #expect(legende.contains("Jenkins en dette"))
        #expect(client.journal.appels == 1)
    }

    @Test("Un bloc de code markdown autour du JSON est toléré")
    func markdownFenceIsTolerated() async {
        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        let client = StubCaptionClient("```json\n{\"caption\":\"Schéma des trois zones réseau.\"}\n```")
        let legende = await BoardCaptionBuilder.refined(
            mode: .diagram, scene: RefonteDemoSeed.workshopDiagramScene(),
            settings: reglages, client: client)
        #expect(legende == "Schéma des trois zones réseau.")
    }

    @Test("L'échec de l'assistant rend la légende pure, sans exception")
    func failureFallsBackOnThePureCaption() async {
        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        let scene = RefonteDemoSeed.workshopDiagramScene()
        let pure = BoardCaptionBuilder.caption(mode: .diagram, scene: scene)

        let enPanne = StubCaptionClient("", throwError: true)
        let repli = await BoardCaptionBuilder.refined(
            mode: .diagram, scene: scene, settings: reglages, client: enPanne)
        #expect(repli == pure)

        let illisible = StubCaptionClient("désolé, je ne peux pas")
        #expect(await BoardCaptionBuilder.refined(
            mode: .diagram, scene: scene, settings: reglages, client: illisible) == pure)

        let vide = StubCaptionClient(#"{"caption":"   "}"#)
        #expect(await BoardCaptionBuilder.refined(
            mode: .diagram, scene: scene, settings: reglages, client: vide) == pure)

        let bavard = StubCaptionClient(#"{"caption":"\#(String(repeating: "x", count: 400))"}"#)
        #expect(await BoardCaptionBuilder.refined(
            mode: .diagram, scene: scene, settings: reglages, client: bavard) == pure)
    }

    @Test("Sans endpoint configuré, rien n'est demandé")
    func withoutEndpointNothingIsRequested() async {
        let reglages = AppSettings()
        reglages.modelName = ""
        let client = StubCaptionClient(#"{"caption":"jamais lu"}"#)
        let legende = await BoardCaptionBuilder.refined(
            mode: .ink, scene: RefonteDemoSeed.workshopInkScene(),
            settings: reglages, client: client)
        #expect(client.journal.appels == 0)
        #expect(legende.hasPrefix("Manuscrit — "))
    }

    @Test("Le prompt porte la légende pure et les libellés, jamais la scène")
    func promptCarriesLabelsNotTheWholeScene() {
        let scene = RefonteDemoSeed.workshopAnnotatedTargetScene()
        let inventaire = BoardCaptionBuilder.inventory(scene: scene)
        let prompt = BoardCaptionBuilder.buildPrompt(
            mode: .sketch,
            pure: BoardCaptionBuilder.caption(mode: .sketch, scene: scene),
            labels: inventaire.labels)
        #expect(prompt.contains("caption"))
        #expect(prompt.contains("Runners GitLab"))
        #expect(!prompt.contains("versionNonce"))
        #expect(prompt.count < 2_000)
    }

    // MARK: - Colonnes

    @Test("Les deux colonnes de Board ont un défaut")
    func boardColumnsHaveDefaults() {
        let planche = Board(index: 0, title: "P", mode: .sketch, t: 0)
        #expect(planche.includeInReport == false)
        #expect(planche.caption.isEmpty)
    }
}
