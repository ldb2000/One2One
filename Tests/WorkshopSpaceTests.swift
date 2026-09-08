import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// L'orchestration de l'écran 6a, testée **contre le double du pont** : créer
/// une planche, dessiner, sauvegarder, changer de mode, dupliquer. Aucun
/// `WKWebView` n'est instancié (plan §8).
@Suite("Écran 6a : orchestration de l'atelier")
@MainActor
struct WorkshopStateTests {

    /// Un bac à sable : store SwiftData en mémoire, `BoardStore` sur un dossier
    /// temporaire, pont doublé.
    private struct Bac {
        let container: ModelContainer
        let context: ModelContext
        let racine: URL
        let store: BoardStore
        let pont: WhiteboardBridgeDouble
        let state: WorkshopState
        let meeting: Meeting
    }

    private func bac() throws -> Bac {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("workshop-\(UUID().uuidString)", isDirectory: true)
        let store = BoardStore(recordingsRoot: racine)
        let pont = WhiteboardBridgeDouble()
        let state = WorkshopState(store: store, makeBridge: { _ in pont })

        let reunion = Meeting(title: "Atelier de test",
                              date: Date(timeIntervalSince1970: 1_788_523_200),
                              notes: "")
        reunion.kind = .workshop
        context.insert(reunion)
        try context.save()

        return Bac(container: container, context: context, racine: racine,
                   store: store, pont: pont, state: state, meeting: reunion)
    }

    @Test("Ouvrir une réunion sans planche en crée une et la charge")
    func openCreatesFirstBoard() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }

        #expect(b.meeting.boards.isEmpty)
        await b.state.open(meeting: b.meeting, playheadT: 495, context: b.context)

        #expect(b.meeting.boards.count == 1)
        let planche = try #require(b.state.activeBoard(of: b.meeting))
        #expect(planche.index == 0)
        #expect(planche.title == "Planche 1")
        #expect(planche.mode == .sketch)
        #expect(planche.t == 495)
        #expect(!planche.scenePath.isEmpty)
        #expect(b.state.activeBoardID == planche.stableID)
        // La page a reçu la scène, le mode et les trois réglages de palette.
        #expect(b.pont.calls.contains(.setMode(.sketch)))
        #expect(b.pont.calls.contains(.setTool(.pencil)))
        #expect(b.pont.calls.contains(.setColor(WorkshopPalette.defaultHex)))
        #expect(b.pont.calls.contains(.setStroke(.moyen)))
    }

    @Test("Ouvrir deux fois ne crée pas de seconde planche")
    func openIsIdempotent() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        #expect(b.meeting.boards.count == 1)
    }

    /// Critère d'acceptation n° 1 du chantier 6, bout à bout : la planche se
    /// crée, se dessine, se sauvegarde et se retrouve horodatée.
    @Test("Dessiner sauvegarde la scène et horodate la planche")
    func drawingIsPersistedAndTimestamped() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 2_060, context: b.context)
        let planche = try #require(b.state.activeBoard(of: b.meeting))
        let avant = planche.updatedAt

        let dessin = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60, text: "Runners GitLab"),
            .init(x: 0, y: 100, width: 200, height: 60, text: "Nexus"),
        ])
        await b.state.apply(WhiteboardChange(scene: dessin, elementCount: 4),
                            meeting: b.meeting, context: b.context)

        #expect(b.state.activeElementCount == 4)
        #expect(planche.updatedAt >= avant)
        let relue = try #require(b.store.loadScene(board: planche, meeting: b.meeting))
        #expect(relue == dessin)
        #expect(b.state.lastSavedAt == planche.updatedAt)
        // Une vignette a été demandée à la page et écrite à côté de la scène.
        #expect(b.pont.calls.contains(.exportPNG(240)))
        #expect(b.store.thumbnailData(board: planche, meeting: b.meeting) != nil)
        #expect(!planche.thumbPath.isEmpty)
    }

    @Test("`＋ Planche` ajoute une planche du même mode, à la suite")
    func addBoardAppends() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        await b.state.addBoard(meeting: b.meeting, t: 800, context: b.context)

        #expect(b.meeting.boards.count == 2)
        let liste = b.state.boards(of: b.meeting)
        #expect(liste.map(\.index) == [0, 1])
        #expect(liste[1].title == "Planche 2")
        #expect(liste[1].t == 800)
        #expect(b.state.activeBoardID == liste[1].stableID)
    }

    /// Critère n° 2 partiel : les trois modes sont sélectionnables, et changer
    /// de mode crée une planche **sauf si la courante est vide**.
    @Test("Changer de mode sur une planche vide la convertit sur place")
    func modeChangeOnEmptyBoardConverts() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        #expect(b.state.activeElementCount == 0)

        await b.state.requestMode(.diagram, meeting: b.meeting, t: 100, context: b.context)
        #expect(b.meeting.boards.count == 1)
        #expect(b.state.activeBoard(of: b.meeting)?.mode == .diagram)
        #expect(b.pont.calls.contains(.setMode(.diagram)))

        // Le troisième mode reste accessible du même clic.
        await b.state.requestMode(.ink, meeting: b.meeting, t: 100, context: b.context)
        #expect(b.meeting.boards.count == 1)
        #expect(b.state.activeBoard(of: b.meeting)?.mode == .ink)
    }

    @Test("Changer de mode sur une planche dessinée en ouvre une nouvelle")
    func modeChangeOnDrawnBoardCreatesNew() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        let premiere = try #require(b.state.activeBoard(of: b.meeting))

        let dessin = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 100, height: 40, text: "Nexus")
        ])
        await b.state.apply(WhiteboardChange(scene: dessin, elementCount: 2),
                            meeting: b.meeting, context: b.context)

        await b.state.requestMode(.ink, meeting: b.meeting, t: 1_685, context: b.context)
        #expect(b.meeting.boards.count == 2)
        // L'ancienne garde son mode **et** son contenu : rien n'est converti.
        #expect(premiere.mode == .sketch)
        #expect(b.store.loadScene(board: premiere, meeting: b.meeting) == dessin)
        let nouvelle = try #require(b.state.activeBoard(of: b.meeting))
        #expect(nouvelle.mode == .ink)
        #expect(nouvelle.index == 1)
        #expect(nouvelle.t == 1_685)
    }

    @Test("Redemander le mode courant ne crée rien")
    func sameModeIsANoOp() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        await b.state.requestMode(.sketch, meeting: b.meeting, t: 0, context: b.context)
        #expect(b.meeting.boards.count == 1)
    }

    @Test("Dupliquer copie le contenu et place la copie juste après")
    func duplicateInsertsAfterSource() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        await b.state.addBoard(meeting: b.meeting, t: 500, context: b.context)

        // On revient sur la première et on la dessine.
        let premiere = b.state.boards(of: b.meeting)[0]
        await b.state.select(premiere, meeting: b.meeting, context: b.context)
        let dessin = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 100, height: 40, text: "DMZ")
        ])
        b.pont.currentScene = dessin
        await b.state.apply(WhiteboardChange(scene: dessin, elementCount: 2),
                            meeting: b.meeting, context: b.context)

        await b.state.duplicateActive(meeting: b.meeting, t: 900, context: b.context)

        #expect(b.meeting.boards.count == 3)
        let liste = b.state.boards(of: b.meeting)
        #expect(liste.map(\.index) == [0, 1, 2])
        #expect(liste[1].title == "Planche 1 (copie)")
        #expect(b.store.loadScene(board: liste[1], meeting: b.meeting) == dessin)
        #expect(liste[1].scenePath != liste[0].scenePath)
        #expect(b.state.activeBoardID == liste[1].stableID)
    }

    @Test("Le glisser du dock renumérote les planches")
    func moveReindexes() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        await b.state.addBoard(meeting: b.meeting, t: 100, context: b.context)
        await b.state.addBoard(meeting: b.meeting, t: 200, context: b.context)

        b.state.move(from: IndexSet(integer: 2), to: 0, meeting: b.meeting, context: b.context)
        let liste = b.state.boards(of: b.meeting)
        #expect(liste.map(\.title) == ["Planche 3", "Planche 1", "Planche 2"])
        #expect(liste.map(\.index) == [0, 1, 2])
    }

    /// Défaut constaté en recette le 2026-09-07 : l'écran demandait sa planche
    /// avant que la page n'ait fini d'analyser 3,1 Mo de JavaScript, le `load`
    /// échouait, un bandeau « Le moteur de planches n'est pas encore prêt »
    /// s'affichait et la toile restait vide jusqu'au clic suivant.
    @Test("Une planche demandée avant que la page soit prête est chargée à `ready`")
    func selectionIsDeferredUntilReady() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        b.pont.isReady = false

        await b.state.open(meeting: b.meeting, playheadT: 495, context: b.context)

        // Rien n'a été poussé, et **aucune erreur** n'a été posée : le moteur
        // charge, il n'est pas cassé.
        #expect(!b.pont.calls.contains { if case .load = $0 { return true } else { return false } })
        #expect(b.state.errorMessage == nil)
        // La planche existe déjà et elle est l'active.
        let planche = try #require(b.state.activeBoard(of: b.meeting))
        #expect(b.state.activeBoardID == planche.stableID)

        b.pont.simulateReady()
        // Le rejeu passe par un `Task` : on lui laisse un tour de boucle.
        try await Task.sleep(for: .milliseconds(80))

        #expect(b.state.isReady)
        #expect(b.pont.calls.contains { if case .load = $0 { return true } else { return false } })
        #expect(b.pont.calls.contains(.setMode(.sketch)))
        #expect(b.pont.calls.contains(.setStroke(.moyen)))
        #expect(b.state.errorMessage == nil)
    }

    @Test("Un seul pont — donc un seul WKWebView — par réunion")
    func bridgeIsCachedPerMeeting() throws {
        var creations = 0
        let state = WorkshopState(store: BoardStore(recordingsRoot: FileManager.default.temporaryDirectory),
                                  makeBridge: { _ in
            creations += 1
            return WhiteboardBridgeDouble()
        })
        let reunion = UUID()
        let a = state.bridge(for: reunion)
        let b = state.bridge(for: reunion)
        #expect(creations == 1)
        #expect(a === b)
        #expect(state.hasBridge(for: reunion))

        // Une autre réunion remplace la page ; l'ancienne est libérée.
        _ = state.bridge(for: UUID())
        #expect(creations == 2)
        #expect(!state.hasBridge(for: reunion))

        state.releaseBridge()
        #expect(!state.isReady)
    }

    @Test("Le pont signale sa disponibilité à l'état")
    func readySignalReachesState() throws {
        let pont = WhiteboardBridgeDouble()
        pont.isReady = false
        let state = WorkshopState(store: BoardStore(recordingsRoot: FileManager.default.temporaryDirectory),
                                  makeBridge: { _ in pont })
        _ = state.bridge(for: UUID())
        #expect(!state.isReady)
        pont.simulateReady()
        #expect(state.isReady)
    }

    @Test("Le zoom reste dans 25–400 %")
    func zoomIsClamped() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.zoom(to: 5_000, meeting: b.meeting)
        #expect(b.state.zoomPercent == WorkshopState.zoomMaximum)
        await b.state.zoom(to: 1, meeting: b.meeting)
        #expect(b.state.zoomPercent == WorkshopState.zoomMinimum)
        await b.state.zoom(to: 150, meeting: b.meeting)
        #expect(b.state.zoomPercent == 150)
        #expect(b.pont.calls.contains(.zoom(150)))

        await b.state.fitToScreen(meeting: b.meeting)
        #expect(b.state.zoomPercent == 100)
        #expect(b.pont.calls.contains(.fitToScreen))
    }

    @Test("Une sauvegarde impossible pose un message, sans perdre la séance")
    func saveFailureIsReported() async throws {
        let b = try bac()
        defer { try? FileManager.default.removeItem(at: b.racine) }
        await b.state.open(meeting: b.meeting, playheadT: 0, context: b.context)
        // Une racine qui n'est pas un dossier : l'écriture échoue.
        let fichier = b.racine.appendingPathComponent("bloqueur")
        try? FileManager.default.createDirectory(at: b.racine, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: fichier)
        let bloque = BoardStore(recordingsRoot: fichier)
        let etat = WorkshopState(store: bloque, makeBridge: { _ in b.pont })
        etat.activeBoardID = b.state.activeBoardID
        await etat.apply(WhiteboardChange(scene: BoardScene.empty, elementCount: 0),
                         meeting: b.meeting, context: b.context)
        #expect(etat.errorMessage != nil)
    }
}

/// La palette de couleurs et les outils de la capture.
@Suite("Palette et outils de l'atelier")
struct WorkshopPaletteTests {

    @Test("Cinq couleurs, dans l'ordre de la capture, toutes issues des jetons")
    func fiveColorsFromTokens() {
        #expect(WorkshopPalette.entries.count == 5)
        #expect(WorkshopPalette.entries.map(\.hex) == [
            "#1a1a1a",  // ink/1
            "#2563d9",  // accent/action
            "#b8544c",  // accent/report
            "#2f9e5f",  // accent/ok
            "#d98324",  // accent/warn
        ])
        // La couleur par défaut est l'encre, active sur la capture.
        #expect(WorkshopPalette.defaultHex == "#1a1a1a")
    }

    @Test("Les hexadécimaux sont dérivés des jetons, pas recopiés")
    func hexMatchesTokens() {
        #expect(WorkshopPalette.hexString(One2OneToken.ink1) == WorkshopPalette.entries[0].hex)
        #expect(WorkshopPalette.hexString(One2OneToken.action) == WorkshopPalette.entries[1].hex)
        #expect(WorkshopPalette.hexString(One2OneToken.report) == WorkshopPalette.entries[2].hex)
        #expect(WorkshopPalette.hexString(One2OneToken.ok) == WorkshopPalette.entries[3].hex)
        #expect(WorkshopPalette.hexString(One2OneToken.warn) == WorkshopPalette.entries[4].hex)
        #expect(WorkshopPalette.hexString(One2OneToken.workshop) == "#1f6b6b")
    }

    @Test("Une couleur se retrouve par son hexadécimal, sans souci de casse")
    func lookupIsCaseInsensitive() {
        #expect(WorkshopPalette.entry(forHex: "#2563D9")?.label == "Action")
        #expect(WorkshopPalette.entry(forHex: "#123456") == nil)
    }

    @Test("Neuf outils en Croquis, dans l'ordre de la palette verticale")
    func nineTools() {
        // Le catalogue porte les outils des trois modes depuis le lot 17 ;
        // c'est `WorkshopPalette.tools(for:)` qui décide de la palette
        // affichée, et `WorkshopModePaletteTests` l'assène mode par mode.
        #expect(WorkshopPalette.tools(for: .sketch).map(\.rawValue) == [
            "pencil", "rectangle", "ellipse", "arrow", "line",
            "text", "note", "image", "eraser",
        ])
        // Chaque outil a un libellé français et un symbole.
        for outil in WhiteboardTool.allCases {
            #expect(!outil.label.isEmpty)
            #expect(!outil.symbol.isEmpty)
        }
    }

    @Test("Trois épaisseurs : Fin, Moyen, Épais")
    func threeStrokes() {
        #expect(WhiteboardStroke.allCases.map(\.label) == ["Fin", "Moyen", "Épais"])
        #expect(WhiteboardStroke.allCases.map(\.rawValue) == [1, 2, 4])
    }

    @Test("Les trois onglets du dock portent un libellé, et aucun n'est vide")
    func dockTabsAreNeverEmpty() {
        let onglets = WorkshopState.DockTab.allCases
        #expect(onglets.map(\.label) == ["Planches", "Captures", "Pièces"])
        // Un onglet sans contenu porte une invite, pas un vide (règle du
        // programme §2.1 : « pas d'onglet vide »).
        #expect(WorkshopState.DockTab.boards.invite == nil)
        for onglet in [WorkshopState.DockTab.captures, .attachments] {
            let invite = onglet.invite ?? ""
            #expect(invite.count >= 20)
            #expect(invite.hasPrefix("Aucune"))
        }
    }

    @Test("Le nom de fichier d'export est utilisable tel quel")
    func exportFileNames() {
        let planche = Board(index: 2, title: "Cible d'architecture")
        #expect(WorkshopExport.fileName(board: planche, extension: "png")
                == "Cible d'architecture.png")
        let sansTitre = Board(index: 2, title: "   ")
        #expect(WorkshopExport.fileName(board: sansTitre, extension: "svg") == "Planche 3.svg")
        // Un `/` dans le titre casserait l'enregistrement sans message.
        let fautif = Board(index: 0, title: "Flux réseau / DMZ")
        #expect(WorkshopExport.fileName(board: fautif, extension: "png")
                == "Flux réseau - DMZ.png")
        #expect(WorkshopExport.sanitized("//") == "Planche")
        #expect(WorkshopExport.sanitized("A//B") == "A-B")
    }
}

/// Le jeu de démonstration de l'écran 6a.
@Suite("Jeu de démonstration de l'atelier")
@MainActor
struct RefonteDemoSeedWorkshopTests {

    private func bac() throws -> (ModelContext, BoardStore, URL) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-atelier-\(UUID().uuidString)", isDirectory: true)
        return (ModelContext(container), BoardStore(recordingsRoot: racine), racine)
    }

    @Test("La réunion reproduit les chiffres de la capture")
    func meetingMatchesCapture() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }
        let reunion = RefonteDemoSeed.seedWorkshop(in: context, store: store)

        #expect(reunion.title == "Cible d'architecture GitLab — séance de travail")
        #expect(reunion.kind == .workshop)
        #expect(reunion.meetingDurationSeconds == 3_720)   // 62:00
        #expect(reunion.participants.count == 4)
        #expect(reunion.project?.name == "S/D — Modernisation CI/CD")
    }

    @Test("Quatre planches, dans l'ordre et aux timecodes de la capture")
    func fourBoards() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }
        let reunion = RefonteDemoSeed.seedWorkshop(in: context, store: store)
        let planches = BoardOrdering.sorted(reunion.boards)

        #expect(planches.count == 4)
        #expect(planches.map(\.title) == ["Périmètre actuel", "Flux réseau",
                                          "Cible d'architecture", "Notes de Patrice"])
        #expect(planches.map(\.mode) == [.sketch, .diagram, .sketch, .ink])
        #expect(planches.map { MeetingPlayhead.mmss($0.t) } == ["08:15", "19:40", "34:20", "28:05"])
        #expect(planches.map(\.authorNames) == ["Yann", "Claire-Amélie", "en cours", "stylet"])
        #expect(planches.map(\.index) == [0, 1, 2, 3])
        // La planche active de la capture est la troisième.
        #expect(BoardOrdering.counterLabel(index: 2, total: 4) == "Planche 3 sur 4")
    }

    @Test("Chaque planche a sa scène sur disque, et aucune n'est vide")
    func scenesAreOnDisk() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }
        let reunion = RefonteDemoSeed.seedWorkshop(in: context, store: store)

        for planche in BoardOrdering.sorted(reunion.boards) {
            #expect(planche.scenePath.hasPrefix("boards/"))
            let scene = try #require(store.loadScene(board: planche, meeting: reunion))
            #expect(!BoardScene.isEmpty(scene))
        }
    }

    @Test("La planche active porte les boîtes de la capture")
    func targetSceneMatchesCapture() throws {
        let scene = RefonteDemoSeed.workshopTargetScene()
        for etiquette in ["Runners GitLab", "Nexus", "GitLab auto-hébergé",
                          "PostgreSQL dédiée", "à décommissionner",
                          "Question ouverte", "à valider"] {
            #expect(scene.contains(etiquette), "manque « \(etiquette) »")
        }
        // 7 boîtes ; celle du manuscrit est un texte libre, donc sans
        // rectangle : 6 × 2 + 1 = 13 objets.
        #expect(BoardScene.elementCount(scene) == 13)
        // La base est bleue, Jenkins en brique pointillée.
        #expect(scene.contains("#2563d9"))
        #expect(scene.contains("#b8544c"))
        #expect(scene.contains("dashed"))
    }

    @Test("Semer l'atelier arme le drapeau des reglages")
    func seedArmsTheFlag() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }
        #expect((try context.fetch(FetchDescriptor<AppSettings>())).isEmpty)
        RefonteDemoSeed.seedWorkshop(in: context, store: store)
        let reglages = try #require((try context.fetch(FetchDescriptor<AppSettings>())).canonicalSettings)
        #expect(reglages.workshopEnabled)
    }

    @Test("Semer deux fois ne duplique rien")
    func seedingIsIdempotent() throws {
        let (context, store, racine) = try bac()
        defer { try? FileManager.default.removeItem(at: racine) }
        let a = RefonteDemoSeed.seedWorkshop(in: context, store: store)
        let b = RefonteDemoSeed.seedWorkshop(in: context, store: store)
        #expect(a === b)
        #expect((try context.fetch(FetchDescriptor<Meeting>())).count == 1)
        #expect(a.boards.count == 4)
    }
}

/// Le drapeau de fonctionnalité et l'aiguillage de l'espace Réunion.
@Suite("Type Atelier : drapeau et aiguillage")
@MainActor
struct WorkshopRoutingTests {

    @Test("Le drapeau `workshopEnabled` est éteint par défaut")
    func flagIsOffByDefault() {
        #expect(AppSettings().workshopEnabled == false)
    }

    @Test("Le type Atelier existe avec son libellé et son espace Réunion")
    func workshopKindIsWired() {
        #expect(MeetingKind.workshop.label == "Atelier")
        // L'atelier garde les trois espaces et les trois modes : l'écran 6a est
        // la **disposition** du mode En séance, pas un quatrième espace.
        #expect(MeetingSpaceRouting.spaces(for: .workshop) == [.meeting, .report, .resources])
        #expect(MeetingSpaceRouting.modes(for: .workshop) == [.prepare, .live, .review])
    }

    @Test("Le dock de l'atelier fait 314 px et la palette 52 px")
    func fixedWidthsMatchSpec() {
        #expect(WorkshopDock.width == 314)
        #expect(One2OneToken.toolPaletteWidth == 52)
        #expect(WorkshopToolbar.height == 32)
        #expect(WorkshopToolPalette.itemSize == 32)
    }

    @Test("Le badge et le fond de l'atelier sont les jetons `accent/workshop`")
    func workshopTokens() {
        #expect(WorkshopPalette.hexString(One2OneToken.workshop) == "#1f6b6b")
        #expect(WorkshopPalette.hexString(One2OneToken.workshopBg) == "#f2f8f7")
    }
}
