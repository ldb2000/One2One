import AppKit
import WebKit

/// Rend un diagramme Mermaid en `NSImage`, via un `WKWebView` hors écran qui
/// exécute `mermaid.min.js` (`MermaidResourceLocator`) et appelle son API
/// `mermaid.render()`. Le SVG produit est converti en `NSImage` — support
/// natif AppKit depuis macOS 12 (`public.svg-image`).
///
/// Un `WKWebView` frais est créé à chaque rendu non trouvé en cache — même
/// stratégie que `ExportService.exportMeetingPDF` : pas d'état partagé entre
/// rendus, délégué de navigation retenu via `objc_setAssociatedObject` le
/// temps du chargement pour qu'ARC ne le libère pas avant `didFinish`. Le
/// script (3,4 Mo) est réanalysé par WebKit à chaque appel — accepté pour ce
/// chantier : `MermaidRenderCache` évite de refaire ce travail pour un même
/// diagramme déjà rendu sous la même apparence.
@MainActor
enum MermaidRenderer {

    enum RenderOutcome {
        case success(NSImage)
        case failure(String)
    }

    /// `Result<Data, String>` n'est pas exprimable — `String` ne conforme pas
    /// à `Error`. Ce petit type interne porte la sortie brute (SVG) du
    /// `WKWebView` avant conversion en `NSImage`.
    enum WebViewOutcome {
        case success(Data)
        case failure(String)
    }

    /// Rend `source` (corps mermaid, sans les fences) sous l'apparence
    /// `isDark`. Sert d'abord le cache disque/mémoire ; sinon lance un rendu
    /// web et le peuple avant de répondre.
    static func render(source: String, isDark: Bool, completion: @escaping (RenderOutcome) -> Void) {
        let key = MermaidRenderCache.key(source: source, isDark: isDark)

        if let cachedSVG = MermaidRenderCache.cachedSVGData(forKey: key), let image = NSImage(data: cachedSVG) {
            completion(.success(image))
            return
        }

        guard let script = MermaidResourceLocator.scriptSource else {
            completion(.failure("mermaid.min.js introuvable dans le paquet"))
            return
        }

        renderViaWebView(source: source, isDark: isDark, script: script) { outcome in
            switch outcome {
            case .success(let svgData):
                MermaidRenderCache.store(svgData, forKey: key)
                if let image = NSImage(data: svgData) {
                    completion(.success(image))
                } else {
                    completion(.failure("SVG produit illisible"))
                }
            case .failure(let message):
                completion(.failure(message))
            }
        }
    }

    private static func renderViaWebView(
        source: String,
        isDark: Bool,
        script: String,
        completion: @escaping (MermaidRenderer.WebViewOutcome) -> Void
    ) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        <script>\(script)</script>
        </body></html>
        """

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let delegate = MermaidRenderDelegate(source: source, isDark: isDark, completion: completion)
        webView.navigationDelegate = delegate
        // Ancre forte le temps du chargement — même mécanisme que
        // `PDFExportDelegate` dans `ExportService` : sans ça, ARC libère
        // `webView`/`delegate` dès que cette fonction retourne et le rendu
        // n'a jamais lieu.
        objc_setAssociatedObject(webView, &MermaidRenderDelegate.assocKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        delegate.ownedWebView = webView
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// Attend la fin du chargement de la page (mermaid.min.js exécuté), puis
/// appelle `mermaid.render()` via `callAsyncJavaScript` — l'API mermaid est
/// asynchrone (Promise), cette variante de `WKWebView` attend sa résolution
/// avant de rendre la main au completion handler AppKit. Le corps JS attrape
/// lui-même les erreurs de syntaxe mermaid (plutôt que de laisser la
/// promesse rejeter) pour renvoyer un message exploitable côté Swift sans
/// dépendre du mapping WKError/NSError d'une exception JS.
@MainActor
private final class MermaidRenderDelegate: NSObject, WKNavigationDelegate {
    nonisolated(unsafe) static var assocKey: UInt8 = 0
    var ownedWebView: WKWebView?

    private let source: String
    private let isDark: Bool
    private let completion: (MermaidRenderer.WebViewOutcome) -> Void
    private var didComplete = false

    init(source: String, isDark: Bool, completion: @escaping (MermaidRenderer.WebViewOutcome) -> Void) {
        self.source = source
        self.isDark = isDark
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let theme = isDark ? "dark" : "default"
        let body = """
        try {
          mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: theme });
          const result = await mermaid.render('onetoone-mermaid-diagram', source);
          return { ok: true, svg: result.svg };
        } catch (err) {
          return { ok: false, error: (err && err.message) ? String(err.message) : String(err) };
        }
        """
        webView.callAsyncJavaScript(
            body,
            arguments: ["source": source, "theme": theme],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            self.finish(with: result)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithLoadFailure(error)
    }

    private func finish(with jsResult: Result<Any, Error>) {
        guard !didComplete else { return }
        didComplete = true
        defer { ownedWebView = nil }

        switch jsResult {
        case .success(let value):
            guard let dict = value as? [String: Any] else {
                completion(.failure("Réponse de rendu inattendue"))
                return
            }
            if let ok = dict["ok"] as? Bool, ok, let svgString = dict["svg"] as? String,
               let data = svgString.data(using: .utf8) {
                completion(.success(data))
            } else {
                let message = dict["error"] as? String ?? "Rendu mermaid invalide"
                completion(.failure(message))
            }
        case .failure(let error):
            completion(.failure("Rendu impossible : \(error.localizedDescription)"))
        }
    }

    private func finishWithLoadFailure(_ error: Error) {
        guard !didComplete else { return }
        didComplete = true
        completion(.failure("Chargement de la page de rendu impossible : \(error.localizedDescription)"))
        ownedWebView = nil
    }
}
