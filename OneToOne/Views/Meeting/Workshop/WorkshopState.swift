import CoreGraphics
import Foundation
import SwiftData

/// État d'écran de l'atelier : la planche active, les réglages de la palette,
/// l'onglet du dock — et **le pont, donc l'unique `WKWebView` de la réunion**.
///
/// Pourquoi un seul `WKWebView` : la page inline 3,1 Mo de JavaScript que
/// WebKit réanalyse à chaque création. Une vue par planche multiplierait ce
/// coût par le nombre de planches (jusqu'à 40, spec §7.4). On garde donc une
/// page et on lui change sa scène (`load`).
///
/// La fabrique de pont est **injectable** : les tests passent
/// `WhiteboardBridgeDouble` et vérifient l'orchestration sans WebKit.
@MainActor
@Observable
final class WorkshopState {

    /// Les trois onglets du dock (spec §7.2). Depuis le lot 17, les trois
    /// portent du contenu ; l'invite ne s'affiche que pour une liste vide.
    enum DockTab: String, CaseIterable, Identifiable, Sendable {
        case boards
        case captures
        case attachments

        var id: String { rawValue }

        var label: String {
            switch self {
            case .boards:      return "Planches"
            case .captures:    return "Captures"
            case .attachments: return "Pièces"
            }
        }

        /// Invite affichée quand l'onglet n'a rien à montrer — jamais un onglet
        /// vide (règle du programme §2.1 : « pas d'onglet vide »).
        var invite: String? {
            switch self {
            case .boards:
                return nil
            case .captures:
                return "Aucune capture dans cette séance. Les captures prises pendant la réunion s'épinglent ici, prêtes à être posées sur la planche."
            case .attachments:
                return "Aucune pièce dans cette séance. Glissez un fichier ci-dessous : il est copié dans la réunion, puis posé verrouillé sur la planche."
            }
        }
    }

    // MARK: - Réglages de l'écran

    /// `stableID` de la planche affichée. `nil` avant la première ouverture.
    var activeBoardID: UUID?

    var tool: WhiteboardTool = .pencil
    var colorHex: String = WorkshopPalette.defaultHex
    var stroke: WhiteboardStroke = .moyen
    var dockTab: DockTab = .boards

    /// Zoom courant, en pourcentage (25–400, spec §7.2).
    var zoomPercent: Int = 100

    /// La page a chargé et le moteur est prêt.
    var isReady = false

    /// Message d'erreur non bloquant (bundle manquant, export refusé).
    var errorMessage: String?

    /// Dernière sauvegarde effective, pour le libellé de fraîcheur.
    var lastSavedAt: Date?

    /// Nombre d'objets de la planche active, remonté par la page. Sert la
    /// règle §7.1 (« sauf si la planche courante est vide ») sans relire le
    /// fichier à chaque clic.
    var activeElementCount: Int = 0

    // MARK: - Dépendances

    @ObservationIgnored let store: BoardStore
    @ObservationIgnored private let makeBridge: @MainActor (UUID) -> any WhiteboardBridge
    @ObservationIgnored private var cachedBridge: (meeting: UUID, bridge: any WhiteboardBridge)?

    /// Chargement demandé avant que la page ne soit prête. La page met une
    /// seconde à analyser 3,1 Mo de JavaScript ; l'écran, lui, s'affiche tout
    /// de suite et demande aussitôt sa planche. Sans cette file d'attente, le
    /// premier `load` échouait en « Le moteur de planches n'est pas encore
    /// prêt » et la planche restait vide jusqu'au clic suivant (constaté en
    /// recette le 2026-09-07).
    @ObservationIgnored private var pendingLoad: (@MainActor () async -> Void)?

    /// `store` est optionnel plutôt que défaut `.shared` : une valeur par
    /// défaut est évaluée **chez l'appelant**, qui n'est pas forcément isolé sur
    /// l'acteur principal (erreur en Swift 6).
    init(store: BoardStore? = nil,
         makeBridge: @escaping @MainActor (UUID) -> any WhiteboardBridge = { WhiteboardWebBridge(meetingStableID: $0) }) {
        self.store = store ?? .shared
        self.makeBridge = makeBridge
        configureStylus()
    }

    // MARK: - Pont

    /// Le pont de cette réunion, créé au premier appel puis réutilisé. Changer
    /// de réunion libère le précédent : deux pages vivantes voudraient dire
    /// 6 Mo de JavaScript en mémoire pour un seul écran visible.
    func bridge(for meetingStableID: UUID) -> any WhiteboardBridge {
        if let cachedBridge, cachedBridge.meeting == meetingStableID {
            return cachedBridge.bridge
        }
        let nouveau = makeBridge(meetingStableID)
        nouveau.onReady = { [weak self] in
            guard let self else { return }
            self.isReady = true
            guard let differe = self.pendingLoad else { return }
            self.pendingLoad = nil
            Task { await differe() }
        }
        cachedBridge = (meetingStableID, nouveau)
        return nouveau
    }

    /// Vrai si un pont est déjà vivant pour cette réunion.
    func hasBridge(for meetingStableID: UUID) -> Bool {
        cachedBridge?.meeting == meetingStableID
    }

    /// Libère la page. Appelé quand l'écran de réunion disparaît.
    func releaseBridge() {
        cachedBridge = nil
        isReady = false
        // Le moniteur de pression survivrait à la page : il écouterait tous les
        // événements du poste pour rien.
        stylus.stop()
    }

    // MARK: - Planches

    /// Les planches de la réunion, dans l'ordre du dock.
    func boards(of meeting: Meeting) -> [Board] {
        BoardOrdering.sorted(meeting.boards)
    }

    /// La planche active, ou la première, ou `nil` si la réunion n'en a aucune.
    func activeBoard(of meeting: Meeting) -> Board? {
        let liste = boards(of: meeting)
        if let activeBoardID, let trouvee = liste.first(where: { $0.stableID == activeBoardID }) {
            return trouvee
        }
        return liste.first
    }

    /// Ouvre la réunion : garantit une planche, la charge dans la page et
    /// applique les réglages courants.
    func open(meeting: Meeting, playheadT: Double, context: ModelContext) async {
        let planche = activeBoard(of: meeting) ?? createBoard(mode: .sketch,
                                                              meeting: meeting,
                                                              t: playheadT,
                                                              context: context)
        await select(planche, meeting: meeting, context: context)
    }

    /// Affiche une planche : sauvegarde la vignette de la précédente, charge la
    /// scène, réapplique mode, outil, couleur et épaisseur.
    func select(_ board: Board, meeting: Meeting, context: ModelContext) async {
        let reunion = meeting.ensuredStableID
        let pont = bridge(for: reunion)

        // Changement de planche : la spec §7.4 exige une vignette à jour.
        if let precedente = activeBoard(of: meeting), precedente !== board {
            await regenerateThumbnail(for: precedente, meeting: meeting, force: true)
        }

        activeBoardID = board.ensuredStableID
        let scene = store.loadScene(board: board, meeting: meeting) ?? BoardScene.empty
        activeElementCount = BoardScene.elementCount(scene)
        try? context.save()

        // La page n'est pas encore prête : on garde l'intention et `onReady`
        // la rejouera. Poser une erreur ici serait mentir — rien n'est cassé,
        // le moteur charge.
        guard pont.isReady else {
            pendingLoad = { [weak self] in
                await self?.pousse(scene: scene, mode: board.mode, meeting: meeting)
            }
            return
        }
        await pousse(scene: scene, mode: board.mode, meeting: meeting)
    }

    /// Envoie la scène et les réglages à la page. Séparé de `select` pour que
    /// `onReady` puisse rejouer exactement la même séquence.
    private func pousse(scene: String, mode: BoardMode, meeting: Meeting) async {
        let pont = bridge(for: meeting.ensuredStableID)
        annotations = BoardAnnotation.list(in: scene)
        do {
            try await pont.load(scene: scene)
            try await pousseMode(mode, meeting: meeting)
            try await pont.setColor(colorHex)
            try await pont.setStroke(stroke)
        } catch {
            errorMessage = "Planche illisible : \(error.localizedDescription)"
        }
    }

    /// Crée une planche à la suite de l'active et la retourne (sans la charger :
    /// l'appelant décide, la duplication a besoin de copier les fichiers avant).
    @discardableResult
    func createBoard(mode: BoardMode,
                     meeting: Meeting,
                     t: Double,
                     context: ModelContext) -> Board {
        let liste = boards(of: meeting)
        let index = liste.count
        let planche = Board(index: index,
                            title: BoardOrdering.defaultTitle(forIndex: index),
                            mode: mode,
                            t: t,
                            authorNames: authorName(for: meeting))
        context.insert(planche)
        planche.meeting = meeting
        _ = try? store.save(scene: BoardScene.empty, board: planche, meeting: meeting)
        BoardOrdering.reindex(BoardOrdering.sorted(meeting.boards))
        try? context.save()
        return planche
    }

    /// `＋ Planche` du dock.
    func addBoard(meeting: Meeting, t: Double, context: ModelContext) async {
        let mode = activeBoard(of: meeting)?.mode ?? .sketch
        let planche = createBoard(mode: mode, meeting: meeting, t: t, context: context)
        await select(planche, meeting: meeting, context: context)
    }

    /// `Dupliquer` du dock : même mode, même contenu, titre « … (copie) ».
    func duplicateActive(meeting: Meeting, t: Double, context: ModelContext) async {
        guard let source = activeBoard(of: meeting) else { return }
        // La scène en cours n'est peut-être pas encore sur disque : on la fige.
        await persistCurrentScene(board: source, meeting: meeting, context: context)

        let copie = BoardOrdering.duplicate(source, at: t)
        context.insert(copie)
        copie.meeting = meeting
        try? store.copyScene(from: source, to: copie, meeting: meeting)
        BoardOrdering.insert(copie, after: source.index, in: BoardOrdering.sorted(meeting.boards))
        try? context.save()
        await select(copie, meeting: meeting, context: context)
    }

    /// Réordonnancement par glisser dans le dock.
    func move(from offsets: IndexSet, to destination: Int, meeting: Meeting, context: ModelContext) {
        BoardOrdering.move(meeting.boards, from: offsets, to: destination)
        try? context.save()
    }

    /// Le sélecteur de mode, règle §7.1.
    func requestMode(_ mode: BoardMode, meeting: Meeting, t: Double, context: ModelContext) async {
        guard let courante = activeBoard(of: meeting) else {
            let planche = createBoard(mode: mode, meeting: meeting, t: t, context: context)
            await select(planche, meeting: meeting, context: context)
            return
        }
        switch BoardModeRule.outcome(currentMode: courante.mode,
                                     requested: mode,
                                     isCurrentEmpty: activeElementCount == 0) {
        case .unchanged:
            return
        case .convertInPlace:
            courante.mode = mode
            courante.updatedAt = Date()
            try? context.save()
            try? await pousseMode(mode, meeting: meeting)
        case .createNew:
            let planche = createBoard(mode: mode, meeting: meeting, t: t, context: context)
            await select(planche, meeting: meeting, context: context)
        }
    }

    // MARK: - Sauvegarde

    /// Une modification remontée par la page : la scène part sur disque, la
    /// vignette est régénérée au plus toutes les 5 s.
    func apply(_ change: WhiteboardChange, meeting: Meeting, context: ModelContext) async {
        guard let planche = activeBoard(of: meeting) else { return }
        activeElementCount = change.elementCount
        // La section `SUR CETTE PLANCHE` suit le dessin : annoter un objet doit
        // le faire apparaître dans le dock sans changer de planche.
        annotations = BoardAnnotation.list(in: change.scene)
        do {
            try store.save(scene: change.scene, board: planche, meeting: meeting)
            lastSavedAt = planche.updatedAt
            try? context.save()
        } catch {
            errorMessage = "Sauvegarde impossible : \(error.localizedDescription)"
            return
        }
        await regenerateThumbnail(for: planche, meeting: meeting, force: false)
    }

    /// Fige la scène affichée sur disque, hors amortissement — avant une
    /// duplication ou un export.
    func persistCurrentScene(board: Board, meeting: Meeting, context: ModelContext) async {
        let pont = bridge(for: meeting.ensuredStableID)
        guard pont.isReady, let scene = try? await pont.scene() else { return }
        _ = try? store.save(scene: scene, board: board, meeting: meeting)
        lastSavedAt = board.updatedAt
        try? context.save()
    }

    /// Régénère la vignette si l'amortissement l'autorise (ou si `force`).
    func regenerateThumbnail(for board: Board, meeting: Meeting, force: Bool) async {
        let identifiant = board.ensuredStableID
        guard store.shouldRegenerateThumbnail(boardStableID: identifiant, force: force) else { return }
        let pont = bridge(for: meeting.ensuredStableID)
        guard pont.isReady, let png = try? await pont.exportThumbnail() else { return }
        try? store.saveThumbnail(png, board: board, meeting: meeting)
    }

    // MARK: - Palette

    func apply(tool: WhiteboardTool, meeting: Meeting) async {
        self.tool = tool
        try? await bridge(for: meeting.ensuredStableID).setTool(tool)
    }

    func apply(colorHex hex: String, meeting: Meeting) async {
        self.colorHex = hex
        try? await bridge(for: meeting.ensuredStableID).setColor(hex)
    }

    func apply(stroke: WhiteboardStroke, meeting: Meeting) async {
        self.stroke = stroke
        try? await bridge(for: meeting.ensuredStableID).setStroke(stroke)
    }

    func undo(meeting: Meeting) async {
        try? await bridge(for: meeting.ensuredStableID).undo()
    }

    func redo(meeting: Meeting) async {
        try? await bridge(for: meeting.ensuredStableID).redo()
    }

    /// Zoom borné 25–400 %, molette et `⌘±`.
    func zoom(to percent: Int, meeting: Meeting) async {
        let borne = min(Self.zoomMaximum, max(Self.zoomMinimum, percent))
        zoomPercent = borne
        try? await bridge(for: meeting.ensuredStableID).zoom(toPercent: borne)
    }

    func fitToScreen(meeting: Meeting) async {
        try? await bridge(for: meeting.ensuredStableID).fitToScreen()
        zoomPercent = 100
    }

    static let zoomMinimum = 25
    static let zoomMaximum = 400

    /// Pas de zoom au clavier (`⌘+` / `⌘-`) et à la molette.
    static let zoomStep = 25

    // MARK: - Export

    func exportPNG(meeting: Meeting) async -> Data? {
        try? await bridge(for: meeting.ensuredStableID).exportPNG(maxDimension: nil)
    }

    func exportSVG(meeting: Meeting) async -> String? {
        try? await bridge(for: meeting.ensuredStableID).exportSVG()
    }

    // MARK: - Divers

    /// L'auteur d'une planche : l'app est mono-utilisateur (D11), c'est donc
    /// toujours le premier participant, à défaut « Moi ».
    private func authorName(for meeting: Meeting) -> String {
        meeting.participants.first?.name ?? "Moi"
    }

    // MARK: - Lot 17 : modes, annotations, pièces

    /// Les objets annotés `question` / `risque` de la planche affichée — la
    /// section `SUR CETTE PLANCHE` du dock (spec §7.2). Recalculée à chaque
    /// changement de scène : c'est une **vue** de la planche, pas un second
    /// magasin qui pourrait divergerd'elle.
    var annotations: [BoardAnnotation] = []

    /// Pression courante du stylet, `nil` quand aucune tablette ne dessine.
    /// Affichée nulle part : c'est la page qui l'applique. Publiée quand même,
    /// pour qu'une future jauge n'ait pas à rebrancher le moniteur.
    var pressure: Double?

    /// Le moniteur d'événements de pression. Un seul pour l'écran, démarré
    /// quand une planche `ink` s'affiche et arrêté sinon : écouter tous les
    /// événements du poste pour un mode qui n'est pas actif serait gratuit.
    @ObservationIgnored let stylus = StylusPressureMonitor()

    /// Branche le moniteur sur la page. Appelé une fois, à la construction.
    private func configureStylus() {
        stylus.onChange = { [weak self] valeur in
            guard let self else { return }
            self.pressure = valeur
            guard let cache = self.cachedBridge else { return }
            Task { try? await cache.bridge.setPressure(valeur) }
        }
    }

    /// Applique un mode à la page : ses réglages, sa bibliothèque de formes et
    /// l'outil par défaut de sa palette.
    ///
    /// Un mode qui garderait l'outil du précédent laisserait un crayon armé
    /// dans une palette qui n'en a pas (spec §7.1 : « chacun sa palette »).
    private func pousseMode(_ mode: BoardMode, meeting: Meeting) async throws {
        let pont = bridge(for: meeting.ensuredStableID)
        try await pont.setMode(mode)
        if mode == .diagram {
            try await pont.setLibrary(BoardShapeLibrary.libraryJSON())
        }
        let outil = WorkshopPalette.tools(for: mode).contains(tool)
            ? tool
            : WorkshopPalette.defaultTool(for: mode)
        tool = outil
        try await pont.setTool(outil)
        if mode == .ink { stylus.start() } else { stylus.stop() }
    }

    /// Dépose une forme de la bibliothèque sur la planche.
    func insert(shape: BoardShapeLibrary.Shape, meeting: Meeting) async {
        let elements = BoardShapeLibrary.elementsJSON(for: shape, at: Self.dropOrigin)
        do {
            try await bridge(for: meeting.ensuredStableID).insertShape(elements)
        } catch {
            errorMessage = "Forme non insérée : \(error.localizedDescription)"
        }
    }

    /// Aligne ou répartit la sélection. Sans assez d'objets sélectionnés, rien
    /// n'est envoyé : `BoardAlignment` rend un dictionnaire vide et le pont
    /// n'est pas dérangé.
    func align(_ operation: BoardAlignment.Operation, meeting: Meeting) async {
        let pont = bridge(for: meeting.ensuredStableID)
        do {
            let selection = try await pont.selection()
            guard selection.count >= operation.minimumSelection else { return }
            let scene = try await pont.scene()
            let positions = BoardAlignment.moves(scene: scene,
                                                 selectedIDs: selection,
                                                 operation: operation)
            guard !positions.isEmpty else { return }
            try await pont.moveElements(positions)
        } catch {
            errorMessage = "Alignement impossible : \(error.localizedDescription)"
        }
    }

    /// Annote la sélection depuis le menu contextuel de la toile.
    func annotateSelection(as kind: BoardAnnotation.Kind?, meeting: Meeting) async {
        do {
            try await bridge(for: meeting.ensuredStableID).setSelectionKind(kind)
        } catch {
            errorMessage = "Annotation impossible : \(error.localizedDescription)"
        }
    }

    /// Sélectionne l'objet annoté qu'on vient de cliquer dans le dock.
    func reveal(_ annotation: BoardAnnotation, meeting: Meeting) async {
        try? await bridge(for: meeting.ensuredStableID).select(elementIDs: [annotation.id])
    }

    // MARK: Action et épinglage

    /// `＋ Action depuis la sélection` (spec §7.2, critère n° 4).
    ///
    /// Passe par `MeetingScreenModel.requestAction` **puis** par
    /// `ActionComposerService.creer` : le rail d'actions n'est pas monté en
    /// atelier (le dock le remplace), donc personne ne consommerait le
    /// brouillon. L'action est donc créée tout de suite, avec le même service
    /// que le composeur du rail — une seconde implémentation divergerait sur
    /// l'ordre, le responsable et la charge.
    @discardableResult
    func createAction(title: String,
                      t: Double,
                      screen: MeetingScreenModel,
                      meeting: Meeting,
                      context: ModelContext) -> ActionTask? {
        let propre = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, let planche = activeBoard(of: meeting) else { return nil }
        let reference = SourceRef(kind: .board, stableID: planche.ensuredStableID, t: t)
        screen.requestAction(from: ActionDraft(title: propre, sourceRef: reference))
        return ActionComposerService.creer(from: screen, meeting: meeting, in: context)
    }

    /// `Épingler à mm:ss` : une note horodatée qui cite la planche, donc un
    /// repère sur la frise (`MeetingTimelineMarkers.boardMarkers`).
    @discardableResult
    func pinActiveBoard(t: Double,
                        meeting: Meeting,
                        context: ModelContext) -> MeetingNote? {
        guard let planche = activeBoard(of: meeting) else { return nil }
        let titre = planche.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let libelle = titre.isEmpty
            ? "◫ Planche \(planche.index + 1)"
            : "◫ Planche \(planche.index + 1) · \(titre)"
        let note = MeetingNote(t: t,
                               text: libelle,
                               kind: .note,
                               visibility: MeetingNoteStore.defaultVisibility(for: meeting.kind),
                               orderIndex: MeetingNoteStore.nextOrderIndex(at: t, in: meeting))
        context.insert(note)
        note.meeting = meeting
        note.sourceRef = SourceRef(kind: .board, stableID: planche.ensuredStableID, t: t)
        try? context.save()
        return note
    }

    // MARK: Pièces et captures

    /// `Insérer` : l'image est **copiée** dans la réunion, bornée à 2 048 px,
    /// puis posée verrouillée sur la planche (spec §7.2, §7.4, §8).
    ///
    /// - Returns: le chemin relatif de la copie, pour que la vue sache que la
    ///   pièce est désormais « Sur la planche ».
    @discardableResult
    func insertImage(from url: URL, meeting: Meeting, context: ModelContext) async -> String? {
        let reunion = meeting.ensuredStableID
        do {
            let copie = try BoardImageInsertion.copy(source: url,
                                                     meetingStableID: reunion,
                                                     store: store)
            let element = BoardImageInsertion.elementJSON(fileID: copie.fileID,
                                                          size: copie.size,
                                                          at: Self.dropOrigin)
            try await bridge(for: reunion).insertImage(dataURL: copie.dataURL,
                                                       fileID: copie.fileID,
                                                       elementJSON: element)
            insertedImages[url.lastPathComponent] = copie.fileID
            return copie.relativePath
        } catch {
            errorMessage = "Insertion impossible : \(error.localizedDescription)"
            return nil
        }
    }

    /// `Sur la planche` (spec §7.2) : les pièces déjà posées, par nom de
    /// fichier → identifiant de l'image dans la scène.
    ///
    /// État d'écran, non persisté : la vérité est dans la scène, et la relire à
    /// chaque rendu du dock coûterait un aller-retour de pont par ligne.
    var insertedImages: [String: String] = [:]

    /// Les noms des pièces déjà posées — ce que le dock consulte.
    var insertedFileNames: Set<String> { Set(insertedImages.keys) }

    /// `Sur la planche` : sélectionne l'image déjà posée plutôt que d'en
    /// insérer une seconde copie.
    func revealImage(named fileName: String, meeting: Meeting) async {
        guard let fileID = insertedImages[fileName] else { return }
        let identifiant = BoardImageInsertion.elementID(fileID: fileID)
        try? await bridge(for: meeting.ensuredStableID).select(elementIDs: [identifiant])
    }

    /// Point de dépôt d'une forme ou d'une image : un décalage constant depuis
    /// l'origine de la planche. Le centre exact de la vue demanderait de
    /// connaître le panoramique de la page ; ce n'est pas ce que la spec exige,
    /// et l'objet est déposé sélectionné, donc immédiatement déplaçable.
    static let dropOrigin = CGPoint(x: 120, y: 120)
}

extension BoardStore {

    /// Surcharges de commodité : les vues manipulent une `Meeting`, pas un
    /// `UUID`.
    @discardableResult
    func save(scene: String, board: Board, meeting: Meeting) throws -> URL {
        try save(scene: scene, board: board, meetingStableID: meeting.ensuredStableID)
    }

    func loadScene(board: Board, meeting: Meeting) -> String? {
        loadScene(board: board, meetingStableID: meeting.ensuredStableID)
    }

    func saveThumbnail(_ data: Data, board: Board, meeting: Meeting) throws {
        try saveThumbnail(data, board: board, meetingStableID: meeting.ensuredStableID)
    }

    func thumbnailData(board: Board, meeting: Meeting) -> Data? {
        thumbnailData(board: board, meetingStableID: meeting.ensuredStableID)
    }

    func copyScene(from source: Board, to destination: Board, meeting: Meeting) throws {
        try copyScene(from: source, to: destination, meetingStableID: meeting.ensuredStableID)
    }

    func deleteFiles(board: Board, meeting: Meeting) {
        deleteFiles(board: board, meetingStableID: meeting.ensuredStableID)
    }
}
