import Foundation

/// Un outil de palette de l'atelier. Les trois modes n'offrent pas les mêmes
/// (spec §7.1) : `WorkshopPalette.tools(for:)` tient la table, cette énumération
/// tient le catalogue.
///
/// Les valeurs brutes sont les clés attendues par `window.oneToOneBoard.setTool`
/// (`Scripts/excalidraw-entry.jsx`) — ne pas les renommer sans régénérer le
/// bundle.
enum WhiteboardTool: String, CaseIterable, Identifiable, Sendable {

    // Croquis (spec §7.1 : « Crayon, rectangle, ellipse, flèche, ligne, texte,
    // post-it, image, gomme »).
    case pencil    = "pencil"
    case rectangle = "rectangle"
    case ellipse   = "ellipse"
    case arrow     = "arrow"
    case line      = "line"
    case text      = "text"
    /// Rectangle préréglé en jaune post-it.
    case note      = "note"
    case image     = "image"
    case eraser    = "eraser"

    // Schéma.
    case selection = "selection"
    /// Flèche à liaison active : posée sur une forme, elle gagne
    /// `startBinding` / `endBinding` et suit la forme qu'on déplace.
    case connector = "connector"

    // Manuscrit.
    /// Tracé libre honorant la pression du stylet.
    case pen         = "pen"
    /// Tracé libre large à 40 % d'opacité.
    case highlighter = "highlighter"
    /// Trait contraint à l'horizontale ou à la verticale (`⇧`).
    case ruler       = "ruler"
    /// Sélection libre. Excalidraw 0.18.1 n'offre pas de lasso : c'est une
    /// sélection rectangulaire (écart consigné dans `STATUS.md`).
    case lasso       = "lasso"

    var id: String { rawValue }

    /// Symbole SF de l'icône 32 × 32 de la palette.
    var symbol: String {
        switch self {
        case .pencil:      return "pencil"
        case .rectangle:   return "rectangle"
        case .ellipse:     return "circle"
        case .arrow:       return "arrow.up.right"
        case .line:        return "minus"
        case .text:        return "textformat"
        case .note:        return "note.text"
        case .image:       return "photo"
        case .eraser:      return "eraser"
        case .selection:   return "cursorarrow"
        case .connector:   return "arrow.triangle.branch"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .ruler:       return "ruler"
        case .lasso:       return "lasso"
        }
    }

    /// Info-bulle française.
    var label: String {
        switch self {
        case .pencil:      return "Crayon"
        case .rectangle:   return "Rectangle"
        case .ellipse:     return "Ellipse"
        case .arrow:       return "Flèche"
        case .line:        return "Trait"
        case .text:        return "Texte"
        case .note:        return "Post-it"
        case .image:       return "Image"
        case .eraser:      return "Gomme"
        case .selection:   return "Sélection"
        case .connector:   return "Connecteur"
        case .pen:         return "Stylo"
        case .highlighter: return "Surligneur"
        case .ruler:       return "Règle"
        case .lasso:       return "Lasso"
        }
    }
}

/// Les trois épaisseurs de la barre d'outils (`Fin`, `Moyen`, `Épais`). La
/// valeur brute est l'épaisseur de trait passée au moteur.
enum WhiteboardStroke: Int, CaseIterable, Identifiable, Sendable {
    case fin   = 1
    case moyen = 2
    case epais = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fin:   return "Fin"
        case .moyen: return "Moyen"
        case .epais: return "Épais"
        }
    }
}

/// Ce que la page remonte quand la scène a changé (debounce 400 ms côté JS).
struct WhiteboardChange: Equatable, Sendable {
    var scene: String
    var elementCount: Int
}

/// Le pont vers la page. **Un protocole**, pas une classe : la règle métier et
/// `BoardStore` se testent contre `WhiteboardBridgeDouble`, jamais contre un
/// `WKWebView` (parade du plan §8 — `swift test` ne touche pas WebKit).
@MainActor
protocol WhiteboardBridge: AnyObject {

    /// La page a-t-elle fini de charger et posté `ready` ?
    var isReady: Bool { get }

    /// Appelé quand la page signale que le moteur est prêt.
    var onReady: (@MainActor () -> Void)? { get set }

    /// Appelé à chaque modification de scène, déjà amortie côté page.
    var onChange: (@MainActor (WhiteboardChange) -> Void)? { get set }

    /// Charge une scène (JSON `.excalidraw`). Une chaîne vide charge une
    /// planche vierge.
    func load(scene: String) async throws

    /// La scène courante, sérialisée.
    func scene() async throws -> String

    /// Export PNG. `maxDimension` borne le grand côté (vignette).
    func exportPNG(maxDimension: Int?) async throws -> Data

    /// Export SVG, en texte.
    func exportSVG() async throws -> String

    func setTool(_ tool: WhiteboardTool) async throws
    func setColor(_ hex: String) async throws
    func setStroke(_ stroke: WhiteboardStroke) async throws
    func undo() async throws
    func redo() async throws

    /// Zoom en pourcentage, borné 25–400 par la page.
    func zoom(toPercent percent: Int) async throws

    func fitToScreen() async throws

    /// Applique les réglages du mode (rugosité, fonte, outil par défaut).
    func setMode(_ mode: BoardMode) async throws

    // MARK: - Lot 17

    /// Charge la bibliothèque de formes du mode Schéma
    /// (`BoardShapeLibrary.libraryJSON()`).
    func setLibrary(_ libraryJSON: String) async throws

    /// Ajoute à la scène courante les éléments d'une forme
    /// (`BoardShapeLibrary.elementsJSON(for:at:)`) et les sélectionne.
    func insertShape(_ elementsJSON: String) async throws

    /// Les identifiants des objets sélectionnés, dans l'ordre de la scène.
    func selection() async throws -> [String]

    /// Sélectionne des objets par identifiant : cliquer une ligne de la section
    /// `SUR CETTE PLANCHE` doit désigner l'objet sur la toile.
    func select(elementIDs: [String]) async throws

    /// Repositionne des objets — c'est ainsi que l'alignement et la
    /// répartition s'appliquent, `BoardAlignment` ayant calculé les positions.
    func moveElements(_ moves: [String: BoardAlignment.Move]) async throws

    /// Annote la sélection (`customData.one2oneKind`). `nil` retire
    /// l'annotation.
    func setSelectionKind(_ kind: BoardAnnotation.Kind?) async throws

    /// Insère une image **verrouillée** depuis une donnée locale (`data:` URL).
    /// Jamais une référence au fichier d'origine (spec §8).
    func insertImage(dataURL: String,
                     fileID: String,
                     width: Double,
                     height: Double) async throws

    /// La pression courante du stylet, poussée dans la page pour qu'elle la
    /// pose sur le tracé (`simulatePressure = false`). `nil` = épaisseur fixe.
    func setPressure(_ value: Double?) async throws
}

extension WhiteboardBridge {
    /// Vignette du dock : 240 px sur le grand côté suffisent pour un rendu
    /// 60 × 40 en Retina.
    func exportThumbnail() async throws -> Data {
        try await exportPNG(maxDimension: 240)
    }
}

// MARK: - Double de test

/// Double du pont : enregistre les appels, rend une scène programmable.
/// Sert les tests de `BoardStore`, de la règle de mode et du critère « une
/// planche se dessine et se sauvegarde sans accès réseau ».
@MainActor
final class WhiteboardBridgeDouble: WhiteboardBridge {

    enum Call: Equatable {
        case load(String)
        case scene
        case exportPNG(Int?)
        case exportSVG
        case setTool(WhiteboardTool)
        case setColor(String)
        case setStroke(WhiteboardStroke)
        case undo
        case redo
        case zoom(Int)
        case fitToScreen
        case setMode(BoardMode)
        case setLibrary(String)
        case insertShape(String)
        case selection
        case select([String])
        case moveElements([String: BoardAlignment.Move])
        case setSelectionKind(BoardAnnotation.Kind?)
        case insertImage(fileID: String, width: Double, height: Double)
        case setPressure(Double?)
    }

    private(set) var calls: [Call] = []

    /// Sélection rendue par `selection()`. Les tests l'écrivent pour simuler un
    /// clic sur des objets.
    var selectionIDs: [String] = []

    var isReady: Bool = true
    var onReady: (@MainActor () -> Void)?
    var onChange: (@MainActor (WhiteboardChange) -> Void)?

    /// Scène rendue par `scene()`. Les tests l'écrivent pour simuler un dessin.
    var currentScene: String = BoardScene.empty

    /// Données rendues par `exportPNG` (un PNG minuscule par défaut).
    var pngData: Data = Data([0x89, 0x50, 0x4E, 0x47])
    var svgText: String = "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"

    /// Erreur à lever au prochain appel, pour tester les chemins d'échec.
    var nextError: Error?

    init() {}

    private func check() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    /// Simule un dessin : la scène change et la page poste sa notification.
    func simulateDrawing(scene: String) {
        currentScene = scene
        onChange?(WhiteboardChange(scene: scene, elementCount: BoardScene.elementCount(scene)))
    }

    /// Simule la fin du chargement de la page.
    func simulateReady() {
        isReady = true
        onReady?()
    }

    func load(scene: String) async throws {
        try check()
        calls.append(.load(scene))
        currentScene = scene.isEmpty ? BoardScene.empty : scene
    }

    func scene() async throws -> String {
        try check()
        calls.append(.scene)
        return currentScene
    }

    func exportPNG(maxDimension: Int?) async throws -> Data {
        try check()
        calls.append(.exportPNG(maxDimension))
        return pngData
    }

    func exportSVG() async throws -> String {
        try check()
        calls.append(.exportSVG)
        return svgText
    }

    func setTool(_ tool: WhiteboardTool) async throws {
        try check()
        calls.append(.setTool(tool))
    }

    func setColor(_ hex: String) async throws {
        try check()
        calls.append(.setColor(hex))
    }

    func setStroke(_ stroke: WhiteboardStroke) async throws {
        try check()
        calls.append(.setStroke(stroke))
    }

    func undo() async throws {
        try check()
        calls.append(.undo)
    }

    func redo() async throws {
        try check()
        calls.append(.redo)
    }

    func zoom(toPercent percent: Int) async throws {
        try check()
        calls.append(.zoom(percent))
    }

    func fitToScreen() async throws {
        try check()
        calls.append(.fitToScreen)
    }

    func setMode(_ mode: BoardMode) async throws {
        try check()
        calls.append(.setMode(mode))
    }

    // MARK: Lot 17

    func setLibrary(_ libraryJSON: String) async throws {
        try check()
        calls.append(.setLibrary(libraryJSON))
    }

    func insertShape(_ elementsJSON: String) async throws {
        try check()
        calls.append(.insertShape(elementsJSON))
    }

    func selection() async throws -> [String] {
        try check()
        calls.append(.selection)
        return selectionIDs
    }

    func select(elementIDs: [String]) async throws {
        try check()
        calls.append(.select(elementIDs))
    }

    func moveElements(_ moves: [String: BoardAlignment.Move]) async throws {
        try check()
        calls.append(.moveElements(moves))
    }

    func setSelectionKind(_ kind: BoardAnnotation.Kind?) async throws {
        try check()
        calls.append(.setSelectionKind(kind))
    }

    func insertImage(dataURL: String,
                     fileID: String,
                     width: Double,
                     height: Double) async throws {
        try check()
        // La donnée elle-même n'entre pas dans `Call` : une image de 2 048 px
        // en base64 rendrait l'échec d'un test illisible.
        calls.append(.insertImage(fileID: fileID, width: width, height: height))
        lastInsertedDataURL = dataURL
    }

    func setPressure(_ value: Double?) async throws {
        try check()
        calls.append(.setPressure(value))
    }

    /// La dernière `data:` URL reçue, pour qu'un test vérifie que l'image est
    /// bien **copiée** dans la planche et non référencée.
    private(set) var lastInsertedDataURL: String?
}
