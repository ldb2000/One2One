import Foundation

/// Localise le bundle Excalidraw embarqué (`excalidraw.bundle.js` et
/// `excalidraw.bundle.css`), construit par `Scripts/build-excalidraw-bundle.sh`
/// et commité dans `OneToOne/Resources/Whiteboard/`.
///
/// Même structure que `MermaidResourceLocator`, et pour les mêmes raisons.
/// `resources: [.process("Resources")]` **aplatit** l'arborescence : le fichier
/// vit dans `Resources/Whiteboard/` dans le dépôt, mais à la racine du bundle
/// de ressources une fois construit — d'où `forResource: "excalidraw.bundle"`
/// sans composante de dossier.
///
/// `Bundle.module` résout en développement (`swift build`/`swift test` :
/// l'exécutable et `OneToOne_OneToOne.bundle` sont voisins). Dans le `.app`
/// packagé par `Scripts/bump-and-build.sh`, ce bundle est copié un niveau plus
/// bas, sous `Contents/Resources/` — cas couvert par `packagedResourceURL`.
enum WhiteboardResourceLocator {
    private static let resourceBundleName = "OneToOne_OneToOne.bundle"

    static let scriptFileName = "excalidraw.bundle.js"
    static let styleFileName = "excalidraw.bundle.css"

    /// URL du script, cas développement puis cas `.app` packagé.
    static func scriptURL() -> URL? {
        url(forResource: "excalidraw.bundle", extension: "js", fileName: scriptFileName)
    }

    /// URL de la feuille de style.
    static func styleURL() -> URL? {
        url(forResource: "excalidraw.bundle", extension: "css", fileName: styleFileName)
    }

    private static func url(forResource name: String, extension ext: String, fileName: String) -> URL? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
        return packagedResourceURL(fileName: fileName)
    }

    /// `resourceRoot/OneToOne_OneToOne.bundle/<fichier>` — disposition produite
    /// par `bump-and-build.sh`. `resourceRoot` par défaut à
    /// `Bundle.main.resourceURL` ; injectable pour les tests.
    static func packagedResourceURL(fileName: String,
                                    resourceRoot: URL? = Bundle.main.resourceURL) -> URL? {
        guard let resourceRoot else { return nil }
        let candidate = resourceRoot
            .appendingPathComponent(resourceBundleName, isDirectory: true)
            .appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Contenu du bundle JS, lu **une seule fois** pour tout le process
    /// (3,1 Mo) : la page est reconstruite à chaque ouverture de réunion, pas
    /// le fichier.
    static let scriptSource: String? = {
        guard let url = scriptURL(), let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }()

    /// Contenu de la feuille de style, lu une seule fois (248 Ko).
    static let styleSource: String? = {
        guard let url = styleURL(), let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }()
}
