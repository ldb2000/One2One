import Foundation

/// Construit la page chargée par le `WKWebView` de l'atelier.
///
/// Le script et la feuille de style sont **inlinés** : une page chargée par
/// `loadHTMLString(_:baseURL: nil)` n'a pas d'origine, et WebKit refuse alors
/// toute URL relative ou `file://`. C'est déjà la stratégie de
/// `MermaidRenderer` pour `mermaid.min.js`.
///
/// La politique de sécurité de contenu interdit **tout** accès réseau
/// (`default-src 'none'`) : les images ne viennent que de `data:`/`blob:`
/// (Excalidraw fabrique ses aperçus en `blob:`), les fontes uniquement de
/// `data:` (le script de construction les a inlinées). Vérifié par
/// `WhiteboardHTMLTests`.
enum WhiteboardHTML {

    /// La politique attendue, écrite une seule fois pour que la vue et le test
    /// parlent de la même chaîne.
    static let contentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:"

    /// Bases réseau qu'Excalidraw sait interroger et que le script de
    /// construction réécrit. Leur présence dans la page serait une régression
    /// silencieuse : la CSP les bloquerait, mais l'intention « aucun réseau »
    /// ne se lit plus dans le fichier.
    static let forbiddenNetworkBases = [
        "https://esm.sh/",
        "https://unpkg.com/",
        "https://json.excalidraw.com",
        "cloudfunctions.net",
        "firebaseio.com",
        "https://oss-ai.excalidraw.com",
        "https://oss-collab.excalidraw.com",
    ]

    enum PageError: Error, LocalizedError {
        case missingScript
        case missingStyle

        var errorDescription: String? {
            switch self {
            case .missingScript:
                return "excalidraw.bundle.js introuvable dans le paquet — relancer Scripts/build-excalidraw-bundle.sh"
            case .missingStyle:
                return "excalidraw.bundle.css introuvable dans le paquet — relancer Scripts/build-excalidraw-bundle.sh"
            }
        }
    }

    /// La page complète, script et style compris.
    static func page() throws -> String {
        guard let script = WhiteboardResourceLocator.scriptSource else { throw PageError.missingScript }
        guard let style = WhiteboardResourceLocator.styleSource else { throw PageError.missingStyle }
        return page(script: script, style: style)
    }

    /// Variante injectable : les tests l'appellent avec un script de
    /// substitution pour vérifier l'enveloppe sans relire 3 Mo.
    static func page(script: String, style: String) -> String {
        """
        <!doctype html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <title>Planche</title>
        <style>\(style)</style>
        </head>
        <body>
        <div id="root"></div>
        <script>\(script)</script>
        </body>
        </html>
        """
    }

    /// Diagnostic de la page : ce que `WhiteboardHTMLTests` vérifie, exposé
    /// pour que la recette puisse le rejouer sur la page réellement chargée.
    struct NetworkAudit: Equatable {
        /// La CSP attendue est-elle présente, à la lettre ?
        var hasPolicy: Bool
        /// Un `<script src=…>` ou un `<link href=…>` réseau ?
        var externalReferences: [String]
        /// Une URL de fonte qui ne soit pas une `data:` URL ?
        var networkFonts: [String]
        /// Une base interrogeable non neutralisée ?
        var reachableBases: [String]

        var isClean: Bool {
            hasPolicy && externalReferences.isEmpty && networkFonts.isEmpty && reachableBases.isEmpty
        }
    }

    /// Le balisage de la page, **corps des `<script>` et `<style>` retiré**.
    ///
    /// Sans ce découpage, chercher `<script src=` dans la page entière tombe
    /// sur les chaînes de caractères du bundle lui-même : Excalidraw fabrique
    /// des `iframe` d'intégration (YouTube, Twitter) dont le gabarit contient
    /// ce texte. Ce qui compte est ce que **le navigateur** va charger, donc le
    /// balisage.
    static func markup(of html: String) -> String {
        var reste = html
        for balise in ["script", "style"] {
            var sortie = ""
            var curseur = reste.startIndex
            while let ouvrant = reste.range(of: "<\(balise)", range: curseur..<reste.endIndex),
                  let finOuvrant = reste.range(of: ">", range: ouvrant.upperBound..<reste.endIndex),
                  let fermant = reste.range(of: "</\(balise)>", range: finOuvrant.upperBound..<reste.endIndex) {
                // On garde la balise ouvrante (ses attributs sont justement ce
                // qu'on veut inspecter) et on jette son contenu.
                sortie += reste[curseur..<finOuvrant.upperBound]
                curseur = fermant.lowerBound
            }
            sortie += reste[curseur..<reste.endIndex]
            reste = sortie
        }
        return reste
    }

    /// Audite une page. Pur : aucune requête n'est émise, on lit le texte.
    static func audit(_ html: String) -> NetworkAudit {
        let balisage = markup(of: html)
        var references: [String] = []
        for motif in ["<script src=", "<script  src=", "<link href=", "<link rel=\"stylesheet\" href="] {
            if balisage.contains(motif) { references.append(motif) }
        }
        // `@import` d'une feuille distante : même effet qu'un `<link>`. Celui-là
        // se cherche dans le CSS, donc dans la page entière.
        if html.contains("@import url(http") { references.append("@import url(http") }
        // Le balisage ne doit porter **aucune** adresse réseau, quelle que soit
        // la balise (`<img>`, `<iframe>`, `<base>`…).
        if balisage.contains("http://") || balisage.contains("https://") {
            references.append("adresse réseau dans le balisage")
        }

        // Une fonte non inlinée laisse forcément une extension `.woff` ou
        // `.woff2` précédée d'autre chose qu'un `data:` — on cherche donc les
        // occurrences de `.woff` qui ne sont pas dans une `data:` URL.
        var networkFonts: [String] = []
        for suffixe in [".woff2\"", ".woff\"", ".woff2'", ".woff'"] {
            if html.contains(suffixe) { networkFonts.append(suffixe) }
        }

        let reachable = forbiddenNetworkBases.filter { html.contains($0) }

        return NetworkAudit(hasPolicy: html.contains(contentSecurityPolicy),
                            externalReferences: references,
                            networkFonts: networkFonts,
                            reachableBases: reachable)
    }
}
