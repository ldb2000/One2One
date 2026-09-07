import Testing
import AppKit
import Foundation
import SwiftData
@testable import OneToOne

/// Le dock de l'écran 6a complété par le lot 17 : le mode poussé à la page, la
/// section `SUR CETTE PLANCHE` (annotation, action, épinglage) et
/// `PIÈCES & CAPTURES` (copie locale verrouillée).
///
/// Tout contre `WhiteboardBridgeDouble` : aucun `WKWebView` (plan §8).
@Suite("Dock de l'atelier : modes, annotations, actions, pièces")
@MainActor
struct WorkshopDockTests {

    private struct Bac {
        let container: ModelContainer
        let context: ModelContext
        let racine: URL
        let store: BoardStore
        let pont: WhiteboardBridgeDouble
        let screen: MeetingScreenModel
        let state: WorkshopState
        let meeting: Meeting
    }

    private func bac() throws -> Bac {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-17-\(UUID().uuidString)", isDirectory: true)
        let store = BoardStore(recordingsRoot: racine)
        let pont = WhiteboardBridgeDouble()

        let suite = "atelier-17-\(UUID().uuidString)"
        let screen = MeetingScreenModel(defaults: UserDefaults(suiteName: suite)!)
        let state = WorkshopState(store: store, makeBridge: { _ in pont })
        screen.workshop = state

        let reunion = Meeting(title: "Atelier de test",
                              date: Date(timeIntervalSince1970: 1_788_523_200),
                              notes: "")
        reunion.kind = .workshop
        context.insert(reunion)
        try context.save()

        return Bac(container: container, context: context, racine: racine,
                   store: store, pont: pont, screen: screen, state: state,
                   meeting: reunion)
    }

    // MARK: - Modes

    @Test("Passer en Schéma charge la bibliothèque de formes, juste après le mode")
    func diagramLoadsTheLibrary() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        await b.state.requestMode(.diagram, meeting: b.meeting, t: 100, context: b.context)

        let modes = b.pont.calls.firstIndex(of: .setMode(.diagram))
        let bibliotheque = b.pont.calls.firstIndex {
            if case .setLibrary = $0 { return true } else { return false }
        }
        let indexMode = try #require(modes)
        let indexBibliotheque = try #require(bibliotheque)
        #expect(indexMode < indexBibliotheque)

        // Et c'est bien la bibliothèque des cinq formes.
        if case .setLibrary(let json)? = b.pont.calls.first(where: {
            if case .setLibrary = $0 { return true } else { return false }
        }) {
            #expect(json.contains("excalidrawlib"))
            for forme in BoardShapeLibrary.Shape.allCases {
                #expect(json.contains(forme.label))
            }
        }
    }

    @Test("Les modes Croquis et Manuscrit ne chargent aucune bibliothèque")
    func otherModesLoadNoLibrary() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        await b.state.requestMode(.ink, meeting: b.meeting, t: 100, context: b.context)

        #expect(!b.pont.calls.contains {
            if case .setLibrary = $0 { return true } else { return false }
        })
    }

    @Test("Changer de mode arme l'outil par défaut de la nouvelle palette")
    func modeChangeResetsTool() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        #expect(b.state.tool == .pencil)

        // Un crayon n'existe pas dans la palette du Schéma : l'outil retombe
        // sur la sélection (spec §7.1 « chacun sa palette »).
        await b.state.requestMode(.diagram, meeting: b.meeting, t: 100, context: b.context)
        #expect(b.state.tool == .selection)

        await b.state.requestMode(.ink, meeting: b.meeting, t: 200, context: b.context)
        #expect(b.state.tool == .pen)
    }

    @Test("Déposer une forme envoie ses éléments à la page")
    func insertShapeReachesThePage() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        await b.state.insert(shape: .server, meeting: b.meeting)
        let appel = b.pont.calls.last { if case .insertShape = $0 { return true } else { return false } }
        let elements = try #require(appel)
        if case .insertShape(let json) = elements {
            #expect(json.contains("Serveur"))
            #expect(json.contains("\"type\":\"rectangle\""))
        }
    }

    @Test("Aligner lit la sélection puis déplace — et se tait si elle est trop courte")
    func alignReadsSelectionFirst() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        b.pont.currentScene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 100, height: 40, text: "A"),
            .init(x: 300, y: 0, width: 100, height: 40, text: "B"),
        ])
        // Les identifiants sont ceux que `BoardScene` fabrique.
        b.pont.selectionIDs = ["one2one-1-0", "one2one-1-1"]

        await b.state.align(.left, meeting: b.meeting)
        #expect(b.pont.calls.contains(.selection))
        let deplacement = b.pont.calls.last {
            if case .moveElements = $0 { return true } else { return false }
        }
        if case .moveElements(let positions)? = deplacement {
            #expect(positions.count == 2)
            #expect(positions.values.allSatisfy { $0.x == 0 })
        } else {
            Issue.record("aucun déplacement envoyé")
        }

        // Un seul objet sélectionné : rien ne part.
        b.pont.selectionIDs = ["one2one-1-0"]
        let avant = b.pont.calls.count
        await b.state.align(.right, meeting: b.meeting)
        #expect(b.pont.calls.count == avant + 1)  // la lecture de sélection seule
    }

    // MARK: - Annotations

    @Test("Annoter la sélection passe la nature au moteur, et `nil` la retire")
    func annotateSelection() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        await b.state.annotateSelection(as: .risk, meeting: b.meeting)
        await b.state.annotateSelection(as: nil, meeting: b.meeting)
        #expect(b.pont.calls.contains(.setSelectionKind(.risk)))
        #expect(b.pont.calls.contains(.setSelectionKind(nil)))
    }

    @Test("Dessiner un objet annoté le fait apparaître dans le dock")
    func annotationsFollowTheScene() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        #expect(b.state.annotations.isEmpty)

        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60,
                  text: "Jenkins à décommissionner", annotation: .risk),
        ])
        await b.state.apply(WhiteboardChange(scene: scene, elementCount: 2),
                            meeting: b.meeting,
                            context: b.context)
        #expect(b.state.annotations.count == 1)
        #expect(b.state.annotations[0].kind == .risk)

        // Et une planche rouverte les retrouve depuis le disque.
        let planche = try #require(b.state.activeBoard(of: b.meeting))
        b.state.annotations = []
        await b.state.select(planche, meeting: b.meeting, context: b.context)
        #expect(b.state.annotations.count == 1)
    }

    @Test("Cliquer une ligne du dock sélectionne l'objet sur la toile")
    func revealSelectsTheElement() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        let annotation = BoardAnnotation(id: "abc", kind: .question, text: "Qui porte ?")
        await b.state.reveal(annotation, meeting: b.meeting)
        #expect(b.pont.calls.contains(.select(["abc"])))
    }

    // MARK: - Action et épinglage (critère n° 4)

    @Test("Une sélection devient une action portant `sourceRef` de type `board`")
    func actionFromSelection() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 495, context: b.context)
        let planche = try #require(b.state.activeBoard(of: b.meeting))

        let action = try #require(b.state.createAction(
            title: "  Jenkins à décommissionner  ",
            t: 2_060,
            screen: b.screen,
            meeting: b.meeting,
            context: b.context))

        // L'action existe dans la réunion — donc dans le rail — **alors
        // qu'aucun rail n'est monté en atelier** : le dock le remplace.
        #expect(b.meeting.tasks.count == 1)
        #expect(b.meeting.tasks.first === action)
        #expect(action.title == "Jenkins à décommissionner")
        let reference = try #require(action.sourceRef)
        #expect(reference.kind == .board)
        #expect(reference.stableID == planche.ensuredStableID)
        #expect(reference.t == 2_060)
        // Le brouillon est consommé : le composeur du rail ne le rejouera pas.
        #expect(b.screen.pendingActionDraft == nil)
    }

    @Test("Une sélection vide ne crée pas d'action")
    func emptySelectionCreatesNothing() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        #expect(b.state.createAction(title: "   ",
                                     t: 10,
                                     screen: b.screen,
                                     meeting: b.meeting,
                                     context: b.context) == nil)
        #expect(b.meeting.tasks.isEmpty)
    }

    @Test("Épingler pose une note horodatée qui cite la planche")
    func pinningCreatesATimedNote() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 495, context: b.context)
        let planche = try #require(b.state.activeBoard(of: b.meeting))
        planche.title = "Cible d'architecture"
        try b.context.save()

        let note = try #require(b.state.pinActiveBoard(t: 2_060,
                                                        meeting: b.meeting,
                                                        context: b.context))
        #expect(note.t == 2_060)
        #expect(note.text == "◫ Planche 1 · Cible d'architecture")
        #expect(note.sourceRef?.kind == .board)
        #expect(note.sourceRef?.stableID == planche.ensuredStableID)

        // Et la frise porte un repère carré, pas deux repères superposés.
        let repères = MeetingTimelineMarkers.boardMarkers(for: b.meeting)
        #expect(repères.count == 1)
        #expect(repères[0].t == 2_060)
        #expect(repères[0].kind == .capture)
        let tous = MeetingTimelineMarkers.allMarkersIncludingBoards(for: b.meeting)
        #expect(tous.count == 1)
        #expect(tous[0].kind == .capture)
    }

    // MARK: - Pièces et captures (critère n° 3)

    /// Un PNG de test, écrit dans un dossier temporaire.
    private func ecritPNG(largeur: Int, hauteur: Int, dans dossier: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        // Un `NSBitmapImageRep` explicite plutôt qu'un `lockFocus` : celui-ci
        // rend une représentation d'écran (`NSCGImageSnapshotRep`) dont la
        // taille suit le facteur d'échelle du poste, ce qui rendrait le test
        // dépendant du Mac qui l'exécute.
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: largeur,
                                                pixelsHigh: hauteur,
                                                bitsPerSample: 8,
                                                samplesPerPixel: 4,
                                                hasAlpha: true,
                                                isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0,
                                                bitsPerPixel: 0))
        rep.size = NSSize(width: largeur, height: hauteur)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: largeur, height: hauteur).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = dossier.appendingPathComponent("piece.png")
        try data.write(to: url)
        return url
    }

    @Test("Le grand côté est borné à 2 048 px, une petite image n'est pas agrandie")
    func imageIsCappedNeverUpscaled() {
        #expect(BoardImageInsertion.fittedSize(CGSize(width: 3_000, height: 1_500))
                == CGSize(width: 2_048, height: 1_024))
        #expect(BoardImageInsertion.fittedSize(CGSize(width: 800, height: 4_096))
                == CGSize(width: 400, height: 2_048))
        // Déjà dans la borne : inchangée.
        #expect(BoardImageInsertion.fittedSize(CGSize(width: 640, height: 480))
                == CGSize(width: 640, height: 480))
        #expect(BoardImageInsertion.maxDimension == 2_048)
    }

    @Test("Insérer copie l'image dans la réunion : supprimer l'original ne casse rien")
    func insertedImageIsACopy() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        let ailleurs = FileManager.default.temporaryDirectory
            .appendingPathComponent("hors-reunion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: ailleurs) }

        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        let source = try ecritPNG(largeur: 3_000, hauteur: 1_200, dans: ailleurs)

        let relatif = try #require(await b.state.insertImage(from: source,
                                                              meeting: b.meeting,
                                                              context: b.context))
        #expect(relatif.hasPrefix("boards/assets/"))
        let copie = b.store.url(meetingStableID: b.meeting.ensuredStableID,
                                relativePath: relatif)
        #expect(FileManager.default.fileExists(atPath: copie.path))

        // Le critère n° 3 : l'original disparaît, la planche tient.
        try FileManager.default.removeItem(at: source)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let relue = try #require(NSImage(contentsOf: copie))
        #expect(relue.size.width == 2_048)

        // La scène ne porte **aucun chemin de disque** : que la donnée.
        let donnee = try #require(b.pont.lastInsertedDataURL)
        #expect(donnee.hasPrefix("data:image/png;base64,"))
        #expect(!donnee.contains(ailleurs.path))
    }

    @Test("L'élément inséré est verrouillé et pointe un fichier local")
    func insertedElementIsLocked() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        let ailleurs = FileManager.default.temporaryDirectory
            .appendingPathComponent("hors-reunion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: ailleurs) }

        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        let source = try ecritPNG(largeur: 400, hauteur: 300, dans: ailleurs)
        _ = await b.state.insertImage(from: source, meeting: b.meeting, context: b.context)

        let json = try #require(b.pont.lastInsertedElementJSON)
        let data = try #require(json.data(using: .utf8))
        let elements = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let element = try #require(elements.first)
        #expect(element["type"] as? String == "image")
        #expect(element["locked"] as? Bool == true)
        let fileID = try #require(element["fileId"] as? String)
        #expect(!fileID.isEmpty)
        #expect(!fileID.contains("/"))
        // La pièce est marquée « sur la planche ».
        #expect(b.state.insertedFileNames.contains("piece.png"))
    }

    @Test("Une image illisible pose un message, sans perdre la séance")
    func unreadableImageIsReported() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)

        let fantome = b.racine.appendingPathComponent("absente.png")
        #expect(await b.state.insertImage(from: fantome,
                                          meeting: b.meeting,
                                          context: b.context) == nil)
        #expect(b.state.errorMessage != nil)
        #expect(b.state.insertedFileNames.isEmpty)
    }
}
