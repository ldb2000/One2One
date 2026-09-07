import Testing
import Foundation
@testable import OneToOne

/// Critère d'acceptation n° 1 du chantier 6 (spec §7) : « Une planche se crée,
/// se dessine et se retrouve horodatée **sans aucun accès réseau** (test en mode
/// avion) ».
///
/// La moitié « sans accès réseau » se vérifie ici, sur le texte de la page : la
/// CSP interdit tout, aucune ressource n'est référencée par URL, les fontes sont
/// inlinées, et aucune des bases interrogeables du moteur ne subsiste. On ne
/// charge **pas** de `WKWebView` : `swift test` ne touche pas WebKit (plan §8).
@Suite("Page de la planche : aucune requête réseau possible")
struct WhiteboardHTMLTests {

    @Test("La politique de sécurité de contenu interdit tout le réseau")
    func cspIsPresentAndStrict() {
        let page = WhiteboardHTML.page(script: "void 0;", style: "body{}")
        #expect(page.contains("<meta http-equiv=\"Content-Security-Policy\""))
        #expect(page.contains(WhiteboardHTML.contentSecurityPolicy))
        // Les directives, une à une : une CSP qui aurait perdu `default-src`
        // laisserait passer `connect-src`.
        #expect(WhiteboardHTML.contentSecurityPolicy.contains("default-src 'none'"))
        #expect(WhiteboardHTML.contentSecurityPolicy.contains("script-src 'unsafe-inline'"))
        #expect(WhiteboardHTML.contentSecurityPolicy.contains("style-src 'unsafe-inline'"))
        #expect(WhiteboardHTML.contentSecurityPolicy.contains("img-src data: blob:"))
        #expect(WhiteboardHTML.contentSecurityPolicy.contains("font-src data:"))
        #expect(!WhiteboardHTML.contentSecurityPolicy.contains("connect-src"))
    }

    @Test("Le script et le style sont inlinés, jamais référencés par URL")
    func scriptAndStyleAreInlined() {
        let page = WhiteboardHTML.page(script: "window.marqueur = 42;", style: ".marqueur{}")
        #expect(page.contains("window.marqueur = 42;"))
        #expect(page.contains(".marqueur{}"))
        let audit = WhiteboardHTML.audit(page)
        #expect(audit.externalReferences.isEmpty)
        #expect(audit.isClean)
    }

    @Test("Un `<script src>` ou un `<link href>` est détecté par l'audit")
    func auditCatchesExternalReferences() {
        let fautif = WhiteboardHTML.page(script: "void 0;", style: "body{}")
            .replacingOccurrences(of: "<div id=\"root\"></div>",
                                  with: "<script src=\"https://cdn.example/x.js\"></script>")
        let audit = WhiteboardHTML.audit(fautif)
        #expect(!audit.externalReferences.isEmpty)
        #expect(!audit.isClean)
    }

    @Test("Une fonte non inlinée est détectée par l'audit")
    func auditCatchesNetworkFonts() {
        let fautif = WhiteboardHTML.page(script: "var f=\"./fonts/Excalifont-Regular.woff2\";",
                                         style: "body{}")
        #expect(!WhiteboardHTML.audit(fautif).networkFonts.isEmpty)
    }

    @Test("Une base réseau du moteur laissée en place est détectée")
    func auditCatchesReachableBases() {
        let fautif = WhiteboardHTML.page(script: "var b=\"https://esm.sh/@excalidraw/excalidraw\";",
                                         style: "body{}")
        #expect(WhiteboardHTML.audit(fautif).reachableBases == ["https://esm.sh/"])
    }

    @Test("Le bundle réellement embarqué passe l'audit")
    func embeddedBundleIsClean() throws {
        // Si cette assertion tombe, le bundle manque du paquet : relancer
        // `Scripts/build-excalidraw-bundle.sh`.
        let page = try WhiteboardHTML.page()
        let audit = WhiteboardHTML.audit(page)
        #expect(audit.hasPolicy)
        #expect(audit.externalReferences.isEmpty, "références externes : \(audit.externalReferences)")
        #expect(audit.networkFonts.isEmpty, "fontes réseau : \(audit.networkFonts)")
        #expect(audit.reachableBases.isEmpty, "bases interrogeables : \(audit.reachableBases)")
        #expect(audit.isClean)
        // Le pont attendu par Swift est bien celui qu'expose la page.
        #expect(page.contains("oneToOneBoard"))
    }

    @Test("Le bundle est localisé dans le paquet de ressources")
    func bundleIsLocatable() {
        #expect(WhiteboardResourceLocator.scriptURL() != nil)
        #expect(WhiteboardResourceLocator.styleURL() != nil)
        #expect(WhiteboardResourceLocator.scriptSource?.isEmpty == false)
        #expect(WhiteboardResourceLocator.styleSource?.isEmpty == false)
    }

    @Test("La disposition du `.app` packagé est couverte")
    func packagedLayoutIsResolved() throws {
        // `.process(\"Resources\")` aplatit l'arborescence : le fichier vit à la
        // racine du bundle de ressources, pas dans `Whiteboard/`.
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("whiteboard-locator-\(UUID().uuidString)", isDirectory: true)
        let paquet = racine.appendingPathComponent("OneToOne_OneToOne.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: paquet, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: racine) }

        #expect(WhiteboardResourceLocator.packagedResourceURL(
            fileName: WhiteboardResourceLocator.scriptFileName, resourceRoot: racine) == nil)

        try Data("void 0;".utf8).write(
            to: paquet.appendingPathComponent(WhiteboardResourceLocator.scriptFileName))
        let trouve = WhiteboardResourceLocator.packagedResourceURL(
            fileName: WhiteboardResourceLocator.scriptFileName, resourceRoot: racine)
        #expect(trouve?.lastPathComponent == "excalidraw.bundle.js")
    }
}
