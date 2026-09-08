import SwiftUI
import AppKit
import WebKit

/// NSViewRepresentable autour de WKWebView pour afficher le HTML du rapport
/// stylé. Recharge le HTML quand la prop change.
struct MeetingReportPreview: NSViewRepresentable {

    /// Document HTML complet (avec ses propres styles CSS inline) à afficher.
    let html: String

    /// Appelée quand le lecteur clique un timecode `onetoone://` (lot 15).
    /// Défaut vide : l'aperçu reste utilisable là où aucune tête de lecture
    /// n'est branchée — le lien est alors inerte plutôt que cassé.
    var onCitation: (URL) -> Void = { _ in }

    /// Crée la WKWebView et désactive `drawsBackground` pour rendre le fond de la vue
    /// transparent : le HTML s'intègre au fond crème de l'app au lieu d'imposer un blanc opaque.
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onCitation = onCitation
        nsView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCitation: onCitation) }

    /// Intercepte les liens du rapport. Deux cas seulement, et aucun ne
    /// navigue **dans** l'aperçu : cette WKWebView n'a ni barre d'adresse ni
    /// bouton retour, on n'y quitterait donc jamais la page où on est arrivé.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {

        var onCitation: (URL) -> Void

        init(onCitation: @escaping (URL) -> Void) {
            self.onCitation = onCitation
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "onetoone" {
                onCitation(url)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // `loadHTMLString` passe par ici avec `about:blank` : laisser
            // charger, sinon l'aperçu reste vide.
            decisionHandler(.allow)
        }
    }
}
