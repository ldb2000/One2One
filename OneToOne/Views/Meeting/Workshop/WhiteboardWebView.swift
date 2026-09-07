import AppKit
import SwiftUI
import WebKit

/// Erreurs du pont.
enum WhiteboardBridgeError: Error, LocalizedError {
    case notReady
    case unexpectedResult(String)
    case pageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Le moteur de planches n'est pas encore prêt"
        case .unexpectedResult(let quoi):
            return "Réponse inattendue du moteur de planches (\(quoi))"
        case .pageUnavailable(let raison):
            return raison
        }
    }
}

/// Implémentation réelle du pont : un `WKWebView` qui charge la page
/// `WhiteboardHTML.page()` et parle à `window.oneToOneBoard`.
///
/// Un objet par réunion, retenu par `WorkshopState` — cf. son doc-comment sur
/// le coût de réanalyse des 3,1 Mo de bundle.
///
/// Le gestionnaire de messages passe par un **proxy faible** :
/// `WKUserContentController.add(_:name:)` retient fortement son destinataire,
/// et comme la configuration est retenue par le `WKWebView` que nous retenons,
/// s'inscrire directement fabriquerait un cycle que rien ne casserait.
@MainActor
final class WhiteboardWebBridge: NSObject, WhiteboardBridge {

    /// Le nom du canal, côté JS comme côté Swift.
    static let messageHandlerName = "board"

    let webView: WKWebView

    private(set) var isReady = false
    var onReady: (@MainActor () -> Void)?
    var onChange: (@MainActor (WhiteboardChange) -> Void)?

    /// Erreur de chargement de la page, s'il y en a une (bundle manquant).
    private(set) var loadFailure: String?

    private let proxy = ScriptMessageProxy()

    init(meetingStableID: UUID) {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        proxy.target = self
        controller.add(proxy, name: Self.messageHandlerName)

        // Le zoom est celui du moteur (25–400 %, spec §7.2), pas celui de
        // WebKit : deux facteurs superposés rendraient le pourcentage affiché
        // par la barre d'outils faux.
        webView.allowsMagnification = false

        do {
            // `baseURL: nil` — la page n'a pas d'origine, c'est pourquoi tout
            // est inliné (même raison que `MermaidRenderer`).
            webView.loadHTMLString(try WhiteboardHTML.page(), baseURL: nil)
        } catch {
            loadFailure = error.localizedDescription
        }
    }

    // MARK: - Réception

    fileprivate func receive(_ body: Any) {
        guard let dictionnaire = body as? [String: Any],
              let type = dictionnaire["type"] as? String
        else { return }
        switch type {
        case "ready":
            isReady = true
            onReady?()
        case "change":
            let scene = dictionnaire["scene"] as? String ?? BoardScene.empty
            let compte = (dictionnaire["elementCount"] as? NSNumber)?.intValue
                ?? BoardScene.elementCount(scene)
            onChange?(WhiteboardChange(scene: scene, elementCount: compte))
        default:
            break
        }
    }

    // MARK: - Appels

    @discardableResult
    private func call(_ corps: String, arguments: [String: Any] = [:]) async throws -> Any? {
        if let loadFailure { throw WhiteboardBridgeError.pageUnavailable(loadFailure) }
        guard isReady else { throw WhiteboardBridgeError.notReady }
        return try await webView.callAsyncJavaScript(corps,
                                                     arguments: arguments,
                                                     in: nil,
                                                     contentWorld: .page)
    }

    func load(scene: String) async throws {
        try await call("return window.oneToOneBoard.load(scene);",
                       arguments: ["scene": scene.isEmpty ? BoardScene.empty : scene])
    }

    func scene() async throws -> String {
        let resultat = try await call("return window.oneToOneBoard.getScene();")
        guard let texte = resultat as? String else {
            throw WhiteboardBridgeError.unexpectedResult("getScene")
        }
        return texte
    }

    func exportPNG(maxDimension: Int?) async throws -> Data {
        // 0 vaut « pas de borne » : `callAsyncJavaScript` n'accepte pas `nil`
        // comme argument nommé.
        let resultat = try await call(
            "return await window.oneToOneBoard.exportPNG(borne > 0 ? borne : undefined);",
            arguments: ["borne": maxDimension ?? 0])
        guard let base64 = resultat as? String, let data = Data(base64Encoded: base64) else {
            throw WhiteboardBridgeError.unexpectedResult("exportPNG")
        }
        return data
    }

    func exportSVG() async throws -> String {
        let resultat = try await call("return await window.oneToOneBoard.exportSVG();")
        guard let texte = resultat as? String else {
            throw WhiteboardBridgeError.unexpectedResult("exportSVG")
        }
        return texte
    }

    func setTool(_ tool: WhiteboardTool) async throws {
        try await call("return window.oneToOneBoard.setTool(nom);",
                       arguments: ["nom": tool.rawValue])
    }

    func setColor(_ hex: String) async throws {
        try await call("return window.oneToOneBoard.setColor(hex);", arguments: ["hex": hex])
    }

    func setStroke(_ stroke: WhiteboardStroke) async throws {
        try await call("return window.oneToOneBoard.setStrokeWidth(largeur);",
                       arguments: ["largeur": stroke.rawValue])
    }

    func undo() async throws {
        try await call("return window.oneToOneBoard.undo();")
    }

    func redo() async throws {
        try await call("return window.oneToOneBoard.redo();")
    }

    func zoom(toPercent percent: Int) async throws {
        try await call("return window.oneToOneBoard.zoomTo(pourcent);",
                       arguments: ["pourcent": percent])
    }

    func fitToScreen() async throws {
        try await call("return window.oneToOneBoard.fitToScreen();")
    }

    func setMode(_ mode: BoardMode) async throws {
        try await call("return window.oneToOneBoard.setMode(mode);",
                       arguments: ["mode": mode.rawValue])
    }

    // MARK: - Appels du lot 17

    func setLibrary(_ libraryJSON: String) async throws {
        try await call("return await window.oneToOneBoard.setLibrary(bibliotheque);",
                       arguments: ["bibliotheque": libraryJSON])
    }

    func insertShape(_ elementsJSON: String) async throws {
        try await call("return window.oneToOneBoard.insertShape(elements);",
                       arguments: ["elements": elementsJSON])
    }

    func selection() async throws -> [String] {
        let resultat = try await call("return window.oneToOneBoard.getSelection();")
        // Une sélection vide remonte un tableau vide, jamais `nil` : c'est une
        // réponse valide, pas une erreur.
        guard let liste = resultat as? [Any] else {
            throw WhiteboardBridgeError.unexpectedResult("getSelection")
        }
        return liste.compactMap { $0 as? String }
    }

    func select(elementIDs: [String]) async throws {
        try await call("return window.oneToOneBoard.select(identifiants);",
                       arguments: ["identifiants": elementIDs])
    }

    func moveElements(_ moves: [String: BoardAlignment.Move]) async throws {
        guard !moves.isEmpty else { return }
        try await call("return window.oneToOneBoard.moveElements(positions);",
                       arguments: ["positions": BoardAlignment.json(moves)])
    }

    func setSelectionKind(_ kind: BoardAnnotation.Kind?) async throws {
        // `callAsyncJavaScript` n'accepte pas `nil` : la chaîne vide vaut
        // « retirer l'annotation ».
        try await call("return window.oneToOneBoard.setSelectionKind(nature || null);",
                       arguments: ["nature": kind?.rawValue ?? ""])
    }

    func insertImage(dataURL: String,
                     fileID: String,
                     width: Double,
                     height: Double) async throws {
        try await call(
            "return await window.oneToOneBoard.insertImage(donnee, identifiant, largeur, hauteur);",
            arguments: ["donnee": dataURL,
                        "identifiant": fileID,
                        "largeur": width,
                        "hauteur": height])
    }

    func setPressure(_ value: Double?) async throws {
        // -1 vaut « aucune pression » : la page retombe alors sur l'épaisseur
        // choisie dans la barre d'outils.
        try await call("return window.oneToOneBoard.setPressure(valeur);",
                       arguments: ["valeur": value ?? -1])
    }
}

/// Relais faible entre `WKUserContentController` et le pont.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WhiteboardWebBridge?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            target?.receive(message.body)
        }
    }
}

/// La toile : le `WKWebView` du pont, tel quel. Aucune logique — la vue ne fait
/// que présenter la page que `WorkshopState` possède déjà, pour qu'un
/// redémontage SwiftUI ne recharge pas 3,1 Mo de JavaScript.
struct WhiteboardWebView: NSViewRepresentable {
    let bridge: WhiteboardWebBridge

    func makeNSView(context: Context) -> WKWebView { bridge.webView }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
