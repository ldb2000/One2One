import Foundation

/// Un outil de la palette verticale de l'écran 6a, dans l'ordre de la capture.
/// Les valeurs brutes sont les clés attendues par `window.oneToOneBoard.setTool`
/// (`Scripts/excalidraw-entry.jsx`) — ne pas les renommer sans régénérer le
/// bundle.
enum WhiteboardTool: String, CaseIterable, Identifiable, Sendable {
    case pencil    = "pencil"
    case rectangle = "rectangle"
    case ellipse   = "ellipse"
    case arrow     = "arrow"
    case line      = "line"
    case text      = "text"
    case image     = "image"
    case frame     = "frame"
    case eraser    = "eraser"

    var id: String { rawValue }

    /// Symbole SF de l'icône 32 × 32 de la palette.
    var symbol: String {
        switch self {
        case .pencil:    return "pencil"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .arrow:     return "arrow.up.right"
        case .line:      return "minus"
        case .text:      return "textformat"
        case .image:     return "photo"
        case .frame:     return "rectangle.split.2x1"
        case .eraser:    return "eraser"
        }
    }

    /// Info-bulle française.
    var label: String {
        switch self {
        case .pencil:    return "Crayon"
        case .rectangle: return "Rectangle"
        case .ellipse:   return "Ellipse"
        case .arrow:     return "Flèche"
        case .line:      return "Trait"
        case .text:      return "Texte"
        case .image:     return "Image"
        case .frame:     return "Colonnes"
        case .eraser:    return "Gomme"
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
    }

    private(set) var calls: [Call] = []

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
}
