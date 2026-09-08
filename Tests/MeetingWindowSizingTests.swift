import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// L'enveloppe de taille de la fenêtre `1to1-meeting`.
///
/// Ces tests gardent un **crash**, pas une préférence esthétique : sans
/// enveloppe déclarée, le `NSHostingView` racine de la fenêtre déduit
/// `contentMinSize`/`contentMaxSize` en mesurant tout l'écran de réunion
/// pendant la passe Auto Layout de la fenêtre, la passe se relance sans fin et
/// AppKit lève `NSGenericException` (« more Update Constraints in Window passes
/// than there are views in the window »). Reproduit en bundle release à chaque
/// ouverture de la fenêtre dédiée depuis le commit 6cc892b (barre du haut sur
/// une ligne), corrigé en déclarant l'enveloppe.
///
/// Ce que `swift test` peut vérifier : que les constantes tiennent le contrat
/// de mise en page, et que la fenêtre les applique toujours. Ce qu'il ne peut
/// pas : la passe Auto Layout elle-même, qui exige un bundle `.app` — d'où le
/// test de fumée consigné dans `STATUS.md`.
@Suite("Enveloppe de la fenêtre de réunion")
struct MeetingWindowSizingTests {

    @Test("Le plancher de largeur garde le rail d'actions affiché")
    func minWidthKeepsRail() {
        // Sous `fluidMinimum + actionsRailWidth`, `MeetingSpaceLayout` sacrifie
        // le rail — que la spec §1.1 veut permanent. Le plancher de la fenêtre
        // doit donc rester au-dessus.
        #expect(MeetingWindowSizing.minWidth
                >= MeetingSpaceLayout.fluidMinimum + One2OneToken.actionsRailWidth)
        #expect(MeetingSpaceLayout.showsRail(totalWidth: MeetingWindowSizing.minWidth))

        let colonnes = MeetingSpaceLayout.columns(
            totalWidth: MeetingWindowSizing.minWidth,
            rail: One2OneToken.actionsRailWidth,
            sideNav: nil
        )
        #expect(colonnes.rail == One2OneToken.actionsRailWidth)
        #expect(colonnes.fluid >= MeetingSpaceLayout.fluidMinimum)
    }

    @Test("Le plancher de hauteur laisse la place aux deux barres et aux colonnes")
    func minHeightLeavesRoom() {
        let barres = MeetingTopChromeBar.height + MeetingSpacesBar.height
        #expect(MeetingWindowSizing.minHeight > barres)
        // Ce qui reste doit rester utilisable : au moins l'en-tête de la carte
        // « Notes & transcription » et une hauteur de lecture réelle.
        #expect(MeetingWindowSizing.minHeight - barres >= 400)
    }

    @Test("La taille d'ouverture ne descend pas sous le plancher")
    func idealAboveMinimum() {
        #expect(MeetingWindowSizing.idealWidth >= MeetingWindowSizing.minWidth)
        #expect(MeetingWindowSizing.idealHeight >= MeetingWindowSizing.minHeight)
    }

    /// Garde de non-régression du correctif lui-même : la fenêtre doit
    /// **appliquer** l'enveloppe. Une enveloppe déclarée mais non branchée
    /// laisserait le crash revenir sans qu'aucun autre test ne bronche, et la
    /// passe Auto Layout n'est pas observable depuis `swift test`.
    @Test("La fenêtre 1to1-meeting applique l'enveloppe à son contenu racine")
    func windowContentAppliesEnvelope() throws {
        let racine = URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // racine du paquet
        let source = try String(contentsOf: racine.appending(path: "OneToOne/OneToOneApp.swift"),
                                encoding: .utf8)

        let debut = try #require(source.range(of: "struct OneToOneMeetingWindowContent"))
        let corps = source[debut.lowerBound...]
        let fin = corps.range(of: "\n}\n") ?? corps.range(of: "\n}")
        let contenu = fin.map { String(corps[..<$0.lowerBound]) } ?? String(corps)

        #expect(contenu.contains("MeetingWindowSizing.minWidth"))
        #expect(contenu.contains("MeetingWindowSizing.minHeight"))
    }
}

/// La taille de la **fenêtre principale**, et la règle qui la sépare de celle
/// de la fenêtre de réunion (retour d'usage du 2026-09-08, défaut n° 1).
///
/// La fenêtre s'ouvrait à ~1 660 × 540, barre latérale écrasée, au lieu de
/// rouvrir à sa taille sauvegardée. Cause : l'hôte du mode séance
/// (`sessionFullscreenHost`, correctif #42) enveloppait le contenu dans un
/// `ZStack`. Le `NavigationSplitView` de `ContentView` cessait d'être la racine
/// de la fenêtre, qui prenait dès lors la taille **idéale mesurée** de son
/// contenu — le tableau de bord et sa carte de 52 semaines, large et courte.
///
/// Trois choses à garder, et aucune n'est observable depuis un modèle : que
/// l'hôte ne pose pas de conteneur, que la scène principale ne reçoive pas
/// l'enveloppe de la réunion, et qu'elle déclare une taille de premier
/// lancement confortable. D'où la lecture des sources, comme
/// `windowContentAppliesEnvelope` juste au-dessus.
@Suite("Taille de la fenêtre principale")
struct MainWindowSizingTests {

    private var racine: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // racine du paquet
    }

    private func source(_ chemin: String) throws -> String {
        try String(contentsOf: racine.appending(path: chemin), encoding: .utf8)
    }

    /// Le corps de la scène principale : de `var body: some Scene` à la
    /// déclaration de la fenêtre suivante.
    private func scenePrincipale() throws -> String {
        let app = try source("OneToOne/OneToOneApp.swift")
        let debut = try #require(app.range(of: "var body: some Scene"))
        let apres = app[debut.upperBound...]
        let fin = try #require(apres.range(of: "WindowGroup(id: \"1to1-meeting\""))
        return String(apres[..<fin.lowerBound])
    }

    /// La cause **première** du défaut, et la seule qu'un test puisse tenir.
    ///
    /// SwiftUI dérive le nom d'enregistrement de cadre du type de la vue racine.
    /// Le correctif #42 a inséré dans cette chaîne un type `private` — le
    /// modificateur de l'hôte du mode séance — dont le nom manglé n'est pas
    /// symbolique : il porte l'**adresse** de son contexte, que l'ASLR change à
    /// chaque lancement. Deux clés pour la même chaîne de vues ont été relevées
    /// dans le même fichier de préférences, différant par cette seule adresse :
    ///
    /// ```
    /// …OneToOne.(unknown context at $1030392a8).SessionFullscreenHostModifier>-1-AppWindow-1
    /// …OneToOne.(unknown context at $1031c9bd8).SessionFullscreenHostModifier>-1-AppWindow-1
    /// ```
    ///
    /// Chaque lancement cherchait donc son cadre sous une clé que le précédent
    /// n'avait pas écrite.
    ///
    /// Le remède **n'est pas** `setFrameAutosaveName` : la recette a montré que
    /// SwiftUI repose son propre nom après le passage de `viewDidMoveToWindow`,
    /// donc que la clé instable revient et que rien n'est restauré. Le cadre est
    /// lu et écrit à la main, sous une clé constante.
    @Test("Le cadre est enregistré sous une clé constante, pas sous celle de SwiftUI")
    func frameKeyIsHandWritten() throws {
        let app = try source("OneToOne/OneToOneApp.swift")
        // Une constante littérale, sans interpolation ni type de vue : c'est ce
        // qui la rend stable d'un lancement à l'autre.
        #expect(MainWindowSizing.frameKey == "OneToOne.mainWindowFrame")
        #expect(!MainWindowSizing.frameKey.contains("<"))
        // Se disputer le nom d'enregistrement avec SwiftUI n'a pas de vainqueur
        // prévisible : on ne l'écrit plus du tout.
        #expect(!app.contains("setFrameAutosaveName"))
        // Lecture au moment où la vue rejoint sa fenêtre, écriture aux deux
        // notifications qui changent le cadre.
        #expect(app.contains("MainWindowSizing.frameKey"))
        #expect(app.contains("NSWindow.didResizeNotification"))
        #expect(app.contains("NSWindow.didMoveNotification"))
        // Le plein écran n'est jamais enregistré : le cadre y est celui de
        // l'écran, et le restaurer rouvrirait l'application sans barre de titre.
        #expect(app.contains("styleMask.contains(.fullScreen)"))
    }

    @Test("La taille de premier lancement reste confortable")
    func defaultSizeIsComfortable() {
        // 1 280 × 800 : la taille des captures de la spec. Sous cela, la barre
        // latérale de 190 px et le tableau de bord ne tiennent pas ensemble —
        // c'est exactement ce que montre la capture du défaut.
        #expect(MainWindowSizing.defaultWidth >= 1_280)
        #expect(MainWindowSizing.defaultHeight >= 800)
        #expect(!MainWindowSizing.frameKey.isEmpty)
    }

    @Test("La scène principale déclare sa taille par défaut et son enregistrement de cadre")
    func mainSceneDeclaresItsSize() throws {
        let scene = try scenePrincipale()
        #expect(scene.contains("MainWindowSizing.defaultWidth"))
        #expect(scene.contains("MainWindowSizing.defaultHeight"))
        // Le restaurateur de cadre : c'est lui qui fait rouvrir la fenêtre à la
        // taille laissée par l'utilisateur.
        #expect(scene.contains("MainWindowFrameRestorer()"))
    }

    @Test("La scène principale ne reçoit pas l'enveloppe de la fenêtre de réunion")
    func mainSceneRefusesTheMeetingEnvelope() throws {
        let scene = try scenePrincipale()
        // Le plancher de 960 × 640 est fait pour un écran de réunion dont les
        // extrema doivent être constants ; l'imposer ici empêcherait la fenêtre
        // principale de rouvrir plus petite que 960 × 640, et surtout
        // ramènerait une taille mesurée là où on veut une taille restaurée.
        #expect(!scene.contains("MeetingWindowSizing"))
    }

    @Test("L'hôte du mode séance ne pose aucun conteneur autour du contenu")
    func sessionHostDoesNotWrapItsContent() throws {
        let hote = try source("OneToOne/Views/Meeting/Session/SessionFullscreenHost.swift")
        let debut = try #require(hote.range(of: "func body(content: Content) -> some View"))
        let corps = String(hote[debut.upperBound...].prefix(600))
        // `ZStack { content … }` = la fenêtre se dimensionne sur la taille
        // mesurée du contenu. `.overlay` = le contenu garde la sienne.
        #expect(!corps.contains("ZStack"))
        #expect(!corps.contains("VStack"))
        #expect(corps.contains(".overlay"))
    }
}
