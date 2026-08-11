import AppKit
import WebKit

/// Rend un diagramme Mermaid en `NSImage`. Le chemin principal est le moteur
/// Swift natif local (`NativeMermaidRenderer`) ; le `WKWebView` et
/// `mermaid.min.js` restent un secours pour les syntaxes non prises en charge
/// par BeautifulMermaidSwift.
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
    /// natif et le peuple avant de répondre. Une erreur native retombe sur
    /// le moteur Mermaid JavaScript pour préserver la compatibilité.
    static func render(source: String, isDark: Bool, completion: @escaping (RenderOutcome) -> Void) {
        let key = MermaidRenderCache.key(source: source, isDark: isDark)

        if let cachedData = MermaidRenderCache.cachedRenderData(forKey: key),
           let image = NSImage(data: cachedData) {
            completion(.success(image))
            return
        }

        Task {
            do {
                let image = try await NativeMermaidRenderer.render(source: source, isDark: isDark)
                if let data = pngData(for: image) {
                    MermaidRenderCache.store(data, forKey: key)
                }
                completion(.success(image))
            } catch {
                renderViaWebFallback(source: source, isDark: isDark, key: key, completion: completion)
            }
        }
    }

    private static func renderViaWebFallback(
        source: String,
        isDark: Bool,
        key: String,
        completion: @escaping (RenderOutcome) -> Void
    ) {
        guard let script = MermaidResourceLocator.scriptSource else {
            completion(.failure("Rendu natif impossible et mermaid.min.js introuvable dans le paquet"))
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

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
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
        let body = """
        try {
          const palette = isDark ? {
            background: '#1f2024', primaryColor: '#292c33', primaryTextColor: '#f5f5f7',
            primaryBorderColor: '#7d8592', lineColor: '#aab2bf', secondaryColor: '#263955',
            tertiaryColor: '#24262b', clusterBkg: '#24262b', clusterBorder: '#535a66',
            edgeLabelBackground: '#1f2024', noteBkgColor: '#3a3423', noteBorderColor: '#9b8648',
            noteTextColor: '#f5f5f7', actorBkg: '#292c33', actorBorder: '#7d8592',
            actorTextColor: '#f5f5f7', signalColor: '#aab2bf', signalTextColor: '#f5f5f7',
            labelBoxBkgColor: '#292c33', labelBoxBorderColor: '#7d8592', labelTextColor: '#f5f5f7'
          } : {
            background: '#ffffff', primaryColor: '#f5f7fb', primaryTextColor: '#1d1d1f',
            primaryBorderColor: '#98a2b3', lineColor: '#667085', secondaryColor: '#eef4ff',
            tertiaryColor: '#fafbfc', clusterBkg: '#f8fafc', clusterBorder: '#d0d5dd',
            edgeLabelBackground: '#ffffff', noteBkgColor: '#fff8e6', noteBorderColor: '#d8b85f',
            noteTextColor: '#344054', actorBkg: '#f5f7fb', actorBorder: '#98a2b3',
            actorTextColor: '#1d1d1f', signalColor: '#667085', signalTextColor: '#344054',
            labelBoxBkgColor: '#f5f7fb', labelBoxBorderColor: '#98a2b3', labelTextColor: '#1d1d1f'
          };
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: 'base',
            fontFamily: '-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif',
            themeVariables: palette,
            flowchart: { htmlLabels: false, curve: 'linear', nodeSpacing: 42, rankSpacing: 48, padding: 12 },
            sequence: { actorMargin: 48, messageMargin: 32, boxMargin: 8 }
          });
          const result = await mermaid.render('onetoone-mermaid-diagram', source);
          const document = new DOMParser().parseFromString(result.svg, 'image/svg+xml');
          const svg = document.documentElement;
          const namespace = 'http://www.w3.org/2000/svg';

          // NSImage ne peint pas le HTML des foreignObject Mermaid. Chaque
          // libellé est donc aplati en texte SVG natif avant de quitter WebKit.
          svg.querySelectorAll('foreignObject').forEach((foreignObject) => {
            const label = document.createElementNS(namespace, 'text');
            const width = Number.parseFloat(foreignObject.getAttribute('width') || '0');
            const height = Number.parseFloat(foreignObject.getAttribute('height') || '0');
            label.setAttribute('x', String(width / 2));
            label.setAttribute('y', String(height / 2));
            label.setAttribute('text-anchor', 'middle');
            label.setAttribute('dominant-baseline', 'central');
            label.setAttribute('font-size', '16');
            label.setAttribute('font-family', '-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif');
            label.setAttribute('font-weight', '500');
            label.setAttribute('fill', palette.primaryTextColor);
            label.textContent = (foreignObject.textContent || '').replace(/\\s+/g, ' ').trim();
            foreignObject.replaceWith(label);
          });

          // CoreGraphics surdimensionne les marker-end userSpaceOnUse de
          // Mermaid. Une pointe explicite au bout du chemin reste stable.
          svg.querySelectorAll('path[marker-end]').forEach((path) => {
            const length = path.getTotalLength();
            if (!Number.isFinite(length) || length <= 0) return;
            const end = path.getPointAtLength(length);
            const before = path.getPointAtLength(Math.max(0, length - 9));
            const angle = Math.atan2(end.y - before.y, end.x - before.x) * 180 / Math.PI;
            const arrow = document.createElementNS(namespace, 'polygon');
            arrow.setAttribute('points', '0,0 -7,-3.5 -7,3.5');
            arrow.setAttribute('transform', `translate(${end.x} ${end.y}) rotate(${angle})`);
            arrow.setAttribute('fill', palette.lineColor);
            arrow.setAttribute('stroke', 'none');
            arrow.setAttribute('class', 'onetoone-arrowhead');
            path.parentElement?.appendChild(arrow);
            path.removeAttribute('marker-end');
          });
          svg.querySelectorAll('path[data-edge="true"], path.flowchart-link').forEach((path) => {
            path.setAttribute('fill', 'none');
            path.setAttribute('stroke', palette.lineColor);
            path.setAttribute('stroke-width', '1.25');
          });
          svg.querySelectorAll('.node .label-container').forEach((shape) => {
            shape.setAttribute('fill', palette.primaryColor);
            shape.setAttribute('stroke', palette.primaryBorderColor);
            shape.setAttribute('stroke-width', '1.25');
          });
          svg.querySelectorAll('text').forEach((text) => {
            text.setAttribute('fill', palette.primaryTextColor);
          });

          return { ok: true, svg: new XMLSerializer().serializeToString(svg) };
        } catch (err) {
          return { ok: false, error: (err && err.message) ? String(err.message) : String(err) };
        }
        """
        webView.callAsyncJavaScript(
            body,
            arguments: ["source": source, "isDark": isDark],
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
