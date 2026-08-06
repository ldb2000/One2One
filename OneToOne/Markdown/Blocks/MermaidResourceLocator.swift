import Foundation

/// Localise `mermaid.min.js`, embarqué dans les ressources du paquet
/// (`OneToOne/Resources/mermaid.min.js`, `resources: [.process("Resources")]`
/// dans `Package.swift`).
///
/// `Bundle.module` — l'accesseur généré par SwiftPM — résout correctement en
/// développement (`swift build`/`swift test` : l'exécutable et
/// `OneToOne_OneToOne.bundle` sont voisins dans `.build/<config>/`, et
/// `Bundle.module` cherche justement à côté de `Bundle.main.bundleURL`).
///
/// Dans le `.app` packagé par `Scripts/bump-and-build.sh` en revanche, ce
/// bundle de ressources est copié sous `Contents/Resources/` — un niveau plus
/// profond que ce que l'accesseur généré sait trouver, puisqu'il regarde
/// directement à la racine de `Bundle.main.bundleURL` (la racine du `.app`),
/// pas dans `Contents/Resources`. `packagedResourceURL` couvre ce second cas
/// explicitement.
enum MermaidResourceLocator {
    private static let resourceBundleName = "OneToOne_OneToOne.bundle"
    private static let resourceFileName = "mermaid.min.js"

    /// Cherche d'abord via `Bundle.module` (cas développement), puis dans la
    /// disposition du `.app` packagé.
    static func scriptURL() -> URL? {
        if let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js") {
            return url
        }
        return packagedResourceURL()
    }

    /// `resourceRoot/OneToOne_OneToOne.bundle/mermaid.min.js` — layout produit
    /// par `bump-and-build.sh`, qui copie le bundle de ressources SwiftPM en
    /// bloc sous `Contents/Resources`. `resourceRoot` par défaut à
    /// `Bundle.main.resourceURL` (donc `Contents/Resources` d'un `.app`
    /// réellement lancé) ; injectable pour les tests.
    static func packagedResourceURL(resourceRoot: URL? = Bundle.main.resourceURL) -> URL? {
        guard let resourceRoot else { return nil }
        let candidate = resourceRoot
            .appendingPathComponent(resourceBundleName, isDirectory: true)
            .appendingPathComponent(resourceFileName)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Contenu texte de `mermaid.min.js`, lu une seule fois pour tout le
    /// process (3,4 Mo) et réutilisé par `MermaidRenderer` à chaque rendu —
    /// embarqué tel quel dans le HTML chargé par le `WKWebView` hors écran
    /// (un `<script>` inline évite les restrictions d'accès aux fichiers
    /// locaux de WebKit sur les URL relatives/`file://`).
    static let scriptSource: String? = {
        guard let url = scriptURL(), let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }()
}
