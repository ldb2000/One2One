import XCTest
@testable import OneToOne

/// `packagedResourceURL(resourceRoot:)` couvre le point de vigilance mesuré
/// sur cette branche : `Scripts/bump-and-build.sh` copie le bundle de
/// ressources SwiftPM sous `Contents/Resources/OneToOne_OneToOne.bundle`, un
/// niveau plus profond que ce que l'accesseur `Bundle.module` généré par
/// SwiftPM sait trouver (il ne regarde qu'à la racine de
/// `Bundle.main.bundleURL`). Ces tests vérifient la logique de repli sans
/// dépendre d'un vrai `.app` packagé — `resourceRoot` est injectable.
final class MermaidResourceLocatorTests: XCTestCase {

    private func makeTempResourceRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-mermaid-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func test_packagedResourceURL_findsScriptUnderResourceBundleLayout() throws {
        let root = try makeTempResourceRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundleDir = root.appendingPathComponent("OneToOne_OneToOne.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let scriptURL = bundleDir.appendingPathComponent("mermaid.min.js")
        try Data("// mermaid".utf8).write(to: scriptURL)

        let found = MermaidResourceLocator.packagedResourceURL(resourceRoot: root)
        XCTAssertEqual(found?.standardizedFileURL, scriptURL.standardizedFileURL)
    }

    func test_packagedResourceURL_missingScript_returnsNil() throws {
        let root = try makeTempResourceRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // `root` existe mais ne contient pas `OneToOne_OneToOne.bundle/mermaid.min.js`.

        XCTAssertNil(MermaidResourceLocator.packagedResourceURL(resourceRoot: root))
    }

    func test_packagedResourceURL_nilResourceRoot_returnsNil() {
        XCTAssertNil(MermaidResourceLocator.packagedResourceURL(resourceRoot: nil))
    }

    /// Exerce le chemin par défaut (`resourceRoot = Bundle.main.resourceURL`,
    /// donc `Contents/Resources` du bundle réel) sans argument explicite —
    /// n'affirme rien de plus qu'« aucun crash », le bundle de tests n'ayant
    /// pas la disposition `.app` packagée. La vérification de la disposition
    /// réelle du `.app` reste celle du palier 1 (copie mesurée dans
    /// `Contents/Resources/OneToOne_OneToOne.bundle`), pas un test ici.
    func test_packagedResourceURL_defaultResourceRoot_doesNotCrash() {
        _ = MermaidResourceLocator.packagedResourceURL()
    }

    /// Vérifie l'aller-retour réel avec la ressource embarquée dans ce paquet
    /// (`OneToOne/Resources/mermaid.min.js`, palier 1) : construite en
    /// pointant `resourceRoot` directement sur le bundle SwiftPM généré par
    /// `swift build` pour ce test target (`Bundle.module` lui-même, dont on
    /// prend le dossier parent comme "Contents/Resources" simulé).
    func test_scriptSource_isNonEmpty_whenBuiltLocally() {
        // `Bundle.module` résout en contexte `swift test` (voir doc de
        // `MermaidResourceLocator.scriptURL()`) — ce test constate que le
        // fichier réellement embarqué au palier 1 est bien lisible et non
        // vide, pas seulement que le mécanisme de repli fonctionne en
        // isolation (couvert par les tests ci-dessus).
        XCTAssertNotNil(MermaidResourceLocator.scriptSource)
        XCTAssertGreaterThan(MermaidResourceLocator.scriptSource?.count ?? 0, 1_000_000)
    }
}
