import SwiftUI
import WebKit

/// NSViewRepresentable autour de WKWebView pour afficher le HTML du rapport
/// stylé. Recharge le HTML quand la prop change.
struct MeetingReportPreview: NSViewRepresentable {

    /// Document HTML complet (avec ses propres styles CSS inline) à afficher.
    let html: String

    /// Crée la WKWebView et désactive `drawsBackground` pour rendre le fond de la vue
    /// transparent : le HTML s'intègre au fond crème de l'app au lieu d'imposer un blanc opaque.
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
