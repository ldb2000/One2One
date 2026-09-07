import Testing
import Foundation
@testable import OneToOne

/// Critère d'acceptation n° 1 du chantier 6, moitié « se dessine, se sauvegarde
/// et se retrouve horodatée » : on dessine via le **double du pont**, on écrit
/// sur un dossier temporaire, on relit.
///
/// Rien ici ne touche le store de production ni WebKit : `BoardStore` reçoit sa
/// racine et son horloge.
@Suite("Planches sur disque : chemins, amortissement, ordre")
@MainActor
struct BoardStoreTests {

    /// Racine jetable, supprimée par l'appelant.
    private func racineTemporaire() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("boardstore-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Les chemins relatifs suivent recordings/<uuid>/boards/<stableID>")
    func relativePathsFollowTheSpec() {
        let planche = UUID(uuidString: "1F6B6B00-0000-4000-8000-000000000001")!
        #expect(BoardStore.relativeScenePath(boardStableID: planche)
                == "boards/1F6B6B00-0000-4000-8000-000000000001.excalidraw.json")
        #expect(BoardStore.relativeThumbPath(boardStableID: planche)
                == "boards/1F6B6B00-0000-4000-8000-000000000001.png")
    }

    @Test("La scène s'écrit, la ligne est horodatée, la relecture rend le même texte")
    func sceneRoundTrip() async throws {
        let racine = racineTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let instant = Date(timeIntervalSince1970: 1_788_506_100)
        let store = BoardStore(recordingsRoot: racine, now: { instant })
        let reunion = UUID()

        let planche = Board(index: 0, title: "Cible d'architecture", mode: .sketch, t: 2_060)
        #expect(planche.scenePath.isEmpty)

        // On « dessine » : le double du pont pose une scène, la page la poste.
        let pont = WhiteboardBridgeDouble()
        var recue: WhiteboardChange?
        pont.onChange = { recue = $0 }
        let dessin = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60, text: "Runners GitLab")
        ])
        pont.simulateDrawing(scene: dessin)
        let change = try #require(recue)
        #expect(change.elementCount == 2)   // le rectangle et son texte lié

        let url = try store.save(scene: change.scene, board: planche, meetingStableID: reunion)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(planche.scenePath == BoardStore.relativeScenePath(boardStableID: planche.ensuredStableID))
        #expect(planche.updatedAt == instant)

        let relue = try #require(store.loadScene(board: planche, meetingStableID: reunion))
        #expect(relue == change.scene)
        #expect(BoardScene.elementCount(relue) == 2)
        #expect(!BoardScene.isEmpty(relue))
    }

    @Test("Une scène absente rend nil sans faire échouer l'écran")
    func missingSceneReadsAsNil() {
        let racine = racineTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = BoardStore(recordingsRoot: racine)
        #expect(store.loadScene(board: Board(), meetingStableID: UUID()) == nil)
    }

    @Test("La vignette est régénérée au plus toutes les 5 s, et à la demande")
    func thumbnailIsDebounced() throws {
        let racine = racineTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        var instant = Date(timeIntervalSince1970: 1_788_506_100)
        let store = BoardStore(recordingsRoot: racine, now: { instant })
        let reunion = UUID()
        let planche = Board()
        let identifiant = planche.ensuredStableID

        // Première fois : rien n'a encore été écrit.
        #expect(store.shouldRegenerateThumbnail(boardStableID: identifiant))
        try store.saveThumbnail(Data([0x89, 0x50]), board: planche, meetingStableID: reunion)
        #expect(planche.thumbPath == BoardStore.relativeThumbPath(boardStableID: identifiant))
        #expect(store.thumbnailData(board: planche, meetingStableID: reunion) == Data([0x89, 0x50]))

        // Aussitôt après : non.
        #expect(!store.shouldRegenerateThumbnail(boardStableID: identifiant))
        instant = instant.addingTimeInterval(4.9)
        #expect(!store.shouldRegenerateThumbnail(boardStableID: identifiant))
        // …mais le changement de planche force.
        #expect(store.shouldRegenerateThumbnail(boardStableID: identifiant, force: true))

        instant = instant.addingTimeInterval(0.2)   // 5,1 s
        #expect(store.shouldRegenerateThumbnail(boardStableID: identifiant))
        #expect(BoardStore.thumbnailInterval == 5)
        #expect(BoardStore.sceneIdleInterval == 0.4)
    }

    @Test("Dupliquer copie la scène et la vignette sous un nouvel identifiant")
    func duplicationCopiesFiles() throws {
        let racine = racineTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = BoardStore(recordingsRoot: racine)
        let reunion = UUID()

        let source = Board(index: 2, title: "Cible d'architecture", mode: .sketch, t: 2_060,
                           authorNames: "Yann")
        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60, text: "Nexus")
        ])
        try store.save(scene: scene, board: source, meetingStableID: reunion)
        try store.saveThumbnail(Data([0x89]), board: source, meetingStableID: reunion)

        let copie = BoardOrdering.duplicate(source, at: 2_100)
        #expect(copie.title == "Cible d'architecture (copie)")
        #expect(copie.index == 3)
        #expect(copie.mode == .sketch)
        #expect(copie.t == 2_100)
        #expect(copie.authorNames == "Yann")
        #expect(copie.ensuredStableID != source.ensuredStableID)

        try store.copyScene(from: source, to: copie, meetingStableID: reunion)
        #expect(store.loadScene(board: copie, meetingStableID: reunion) == scene)
        #expect(copie.scenePath != source.scenePath)
        #expect(store.thumbnailData(board: copie, meetingStableID: reunion) == Data([0x89]))
    }

    @Test("Supprimer une planche retire ses fichiers")
    func deletingRemovesFiles() throws {
        let racine = racineTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = BoardStore(recordingsRoot: racine)
        let reunion = UUID()
        let planche = Board()
        let url = try store.save(scene: BoardScene.empty, board: planche, meetingStableID: reunion)
        try store.saveThumbnail(Data([0x89]), board: planche, meetingStableID: reunion)
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.deleteFiles(board: planche, meetingStableID: reunion)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.thumbnailData(board: planche, meetingStableID: reunion) == nil)
    }

    @Test("Le dossier boards/ est créé avant toute écriture")
    func directoryIsCreatedUpFront() throws {
        let racine = racineTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = BoardStore(recordingsRoot: racine)
        let reunion = UUID()
        #expect(!FileManager.default.fileExists(atPath: store.boardsDirectory(meetingStableID: reunion).path))
        let dossier = try store.createBoardsDirectory(meetingStableID: reunion)
        #expect(FileManager.default.fileExists(atPath: dossier.path))
        #expect(dossier.lastPathComponent == "boards")
        #expect(dossier.deletingLastPathComponent().lastPathComponent == reunion.uuidString)
    }
}

/// L'ordre des planches et les libellés qu'en tire la barre d'outils.
@Suite("Ordre des planches et libellés du compteur")
@MainActor
struct BoardOrderingTests {

    private func planches(_ n: Int) -> [Board] {
        (0..<n).map { Board(index: $0, title: "Planche \($0 + 1)", t: Double($0) * 100) }
    }

    @Test("Glisser une planche renumérote les index de 0 à n-1")
    func moveReindexes() {
        let liste = planches(4)
        let apres = BoardOrdering.move(liste, from: IndexSet(integer: 3), to: 1)
        #expect(apres.map(\.index) == [0, 1, 2, 3])
        #expect(apres.map(\.title) == ["Planche 1", "Planche 4", "Planche 2", "Planche 3"])
    }

    @Test("Supprimer laisse des index contigus")
    func removalKeepsIndicesContiguous() {
        let liste = planches(4)
        let apres = BoardOrdering.removing(liste[1], from: liste)
        #expect(apres.count == 3)
        #expect(apres.map(\.index) == [0, 1, 2])
        #expect(apres.map(\.title) == ["Planche 1", "Planche 3", "Planche 4"])
    }

    @Test("Insérer une copie la place juste après son original")
    func insertPlacesCopyAfterOriginal() {
        let liste = planches(4)
        let copie = BoardOrdering.duplicate(liste[1], at: 999)
        let apres = BoardOrdering.insert(copie, after: liste[1].index, in: liste + [copie])
        #expect(apres.map(\.index) == [0, 1, 2, 3, 4])
        #expect(apres[2] === copie)
    }

    @Test("Deux planches au même index gardent un ordre stable par timecode")
    func sortIsStableOnEqualIndices() {
        let a = Board(index: 0, title: "A", t: 200)
        let b = Board(index: 0, title: "B", t: 100)
        #expect(BoardOrdering.sorted([a, b]).map(\.title) == ["B", "A"])
    }

    @Test("Le compteur de la barre d'outils dit « Planche 3 sur 4 »")
    func counterLabelMatchesCapture() {
        #expect(BoardOrdering.counterLabel(index: 2, total: 4) == "Planche 3 sur 4")
        // Un total incohérent ne produit jamais « Planche 5 sur 4 ».
        #expect(BoardOrdering.counterLabel(index: 4, total: 4) == "Planche 5 sur 5")
    }

    @Test("La fraîcheur dit « il y a 12 s » comme la capture")
    func freshnessLabelMatchesCapture() {
        let base = Date(timeIntervalSince1970: 1_788_506_100)
        #expect(BoardOrdering.freshnessLabel(updatedAt: base, now: base.addingTimeInterval(12))
                == "dernière modif. il y a 12 s")
        #expect(BoardOrdering.freshnessLabel(updatedAt: base, now: base.addingTimeInterval(125))
                == "dernière modif. il y a 2 min")
        #expect(BoardOrdering.freshnessLabel(updatedAt: base, now: base.addingTimeInterval(7_400))
                == "dernière modif. il y a 2 h")
        // Une horloge qui recule ne produit pas de négatif.
        #expect(BoardOrdering.freshnessLabel(updatedAt: base, now: base.addingTimeInterval(-30))
                == "dernière modif. il y a 0 s")
    }

    @Test("Le titre par défaut et le titre de copie")
    func titles() {
        #expect(BoardOrdering.defaultTitle(forIndex: 0) == "Planche 1")
        #expect(BoardOrdering.defaultTitle(forIndex: 3) == "Planche 4")
        #expect(BoardOrdering.copyTitle(of: "  Flux réseau ") == "Flux réseau (copie)")
        #expect(BoardOrdering.copyTitle(of: "") == "Planche (copie)")
    }
}

/// Critère d'acceptation n° 2 du chantier 6, partie livrée au lot 16 : « Les
/// trois modes sont accessibles en un clic » et la règle §7.1 « changer de mode
/// crée une nouvelle planche, sauf si la courante est vide ».
@Suite("Règle du sélecteur de mode")
struct BoardModeRuleTests {

    @Test("Les trois modes de la spec existent, avec leurs libellés français")
    func threeModes() {
        #expect(BoardMode.allCases == [.sketch, .diagram, .ink])
        #expect(BoardMode.allCases.map(\.label) == ["Croquis", "Schéma", "Manuscrit"])
        // Les valeurs brutes sont persistées **et** passées au moteur.
        #expect(BoardMode.allCases.map(\.rawValue) == ["sketch", "diagram", "ink"])
    }

    @Test("Le même mode ne fait rien")
    func sameModeIsUnchanged() {
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .sketch,
                                      isCurrentEmpty: false) == .unchanged)
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .sketch,
                                      isCurrentEmpty: true) == .unchanged)
    }

    @Test("Une planche vide change de mode sur place")
    func emptyBoardConvertsInPlace() {
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .diagram,
                                      isCurrentEmpty: true) == .convertInPlace)
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .ink,
                                      scene: BoardScene.empty) == .convertInPlace)
        #expect(BoardModeRule.outcome(currentMode: .diagram, requested: .sketch,
                                      scene: "") == .convertInPlace)
    }

    @Test("Une planche dessinée n'est jamais convertie : le mode ouvre une planche")
    func drawnBoardCreatesNew() {
        let dessin = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 100, height: 40, text: "Nexus")
        ])
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .diagram,
                                      scene: dessin) == .createNew)
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .diagram,
                                      isCurrentEmpty: false) == .createNew)
    }

    @Test("Une scène dont tous les objets sont supprimés compte comme vide")
    func deletedElementsCountAsEmpty() {
        let scene = """
        {"type":"excalidraw","elements":[{"id":"a","isDeleted":true}],"appState":{}}
        """
        #expect(BoardScene.isEmpty(scene))
        #expect(BoardModeRule.outcome(currentMode: .sketch, requested: .ink,
                                      scene: scene) == .convertInPlace)
    }

    @Test("Une scène illisible est traitée comme vide, sans exception")
    func brokenSceneIsEmpty() {
        #expect(BoardScene.elementCount("ceci n'est pas du JSON") == 0)
        #expect(BoardScene.isEmpty("{}"))
    }
}
