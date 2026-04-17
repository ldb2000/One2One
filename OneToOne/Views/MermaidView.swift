import SwiftUI
import WebKit

struct MermaidView: View {
    let diagram: String

    var body: some View {
        MermaidWebView(diagram: diagram)
    }
}

struct MermaidWebView: NSViewRepresentable {
    let diagram: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        // Empêcher la WKWebView de capturer le focus clavier
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.lastDiagram = diagram
        loadDiagram(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Ne recharger que si le diagramme a réellement changé
        guard context.coordinator.lastDiagram != diagram else { return }
        context.coordinator.lastDiagram = diagram
        loadDiagram(in: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadDiagram(in webView: WKWebView) {
        let htmlContent = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
            <script>mermaid.initialize({startOnLoad:true});</script>
            <style>
                body { margin: 0; pointer-events: none; user-select: none; }
            </style>
        </head>
        <body>
            <div class="mermaid">
                \(diagram)
            </div>
        </body>
        </html>
        """
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    class Coordinator {
        var lastDiagram: String = ""
    }
}
