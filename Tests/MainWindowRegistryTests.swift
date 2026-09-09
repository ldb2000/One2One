import Testing
import Foundation
@testable import OneToOne

/// Le registre de la fenêtre principale : la règle qui décide quelle fenêtre un
/// raccourci remonte.
///
/// Ce qui se teste sans fenêtre : `estLaFenetrePrincipale`, la seule règle du
/// fichier. Le reste (`remonter`) appelle AppKit et ne se joue pas hors session
/// graphique — son branchement est vérifié par lecture des sources, comme celui
/// de la garde de sélection.
@Suite("Registre de la fenêtre principale")
@MainActor
struct MainWindowRegistryTests {

    private static var racineDuDepot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racineDuDepot.appendingPathComponent(chemin),
                     encoding: .utf8)) ?? ""
    }

    // MARK: - La règle

    /// La fenêtre principale est le `WindowGroup` **sans** identifiant : AppKit
    /// lui en fabrique un dérivé du type de son contenu, qu'on ne peut pas
    /// épeler. La règle est donc négative.
    @Test("Une fenêtre sans identifiant, ou avec un identifiant inconnu, peut être la principale")
    func fenetrePrincipaleReconnue() {
        #expect(MainWindowRegistry.estLaFenetrePrincipale(identifiant: nil))
        #expect(MainWindowRegistry.estLaFenetrePrincipale(identifiant: "SwiftUI.ContentView-1-AppWindow-1"))
        #expect(MainWindowRegistry.estLaFenetrePrincipale(identifiant: ""))
    }

    /// Le repli ne doit **jamais** remonter une fenêtre de réunion : c'est
    /// justement celle qui masque la principale quand `⌘K` est frappé.
    @Test("Les fenêtres secondaires sont exclues, y compris par sous-chaîne")
    func fenetresSecondairesExclues() {
        for identifiant in MainWindowRegistry.identifiantsSecondaires {
            #expect(!MainWindowRegistry.estLaFenetrePrincipale(identifiant: identifiant),
                    "\(identifiant) est une fenêtre secondaire")
            // AppKit suffixe : « 1to1-meeting-AppWindow-1 », observé au
            // diagnostic du 2026-09-09.
            #expect(!MainWindowRegistry.estLaFenetrePrincipale(identifiant: "\(identifiant)-AppWindow-1"))
        }
        #expect(MainWindowRegistry.identifiantsSecondaires == ["1to1-meeting", "prep-standalone"])
    }

    /// La liste doit rester celle qu'`OneToOneApp` déclare : un
    /// `WindowGroup(id:)` de plus, oublié ici, se ferait remonter à la place de
    /// la fenêtre principale.
    @Test("La liste des fenêtres secondaires est celle qu'OneToOneApp déclare")
    func listeAJour() {
        let app = Self.source("OneToOne/OneToOneApp.swift")
        #expect(!app.isEmpty, "OneToOneApp.swift introuvable")
        let declares = app.components(separatedBy: "WindowGroup(id: \"")
            .dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first }
        #expect(Set(declares) == Set(MainWindowRegistry.identifiantsSecondaires),
                "fenêtres déclarées : \(Set(declares)) — mettre à jour identifiantsSecondaires")
    }

    // MARK: - Le branchement

    @Test("La fenêtre principale s'enregistre là où SwiftUI la donne")
    func enregistrementBranche() {
        let app = Self.source("OneToOne/OneToOneApp.swift")
        #expect(app.contains("MainWindowRegistry.enregistrer(window)"),
                "MainWindowFrameRestorer est le seul endroit qui reçoive la fenêtre principale")
    }

    /// Les deux points d'entrée qui posaient un état sans remonter la fenêtre.
    @Test("La palette et la recherche du menu système remontent la fenêtre avant d'écrire")
    func remonteeAvantEcriture() throws {
        let menus = Self.source("OneToOne/Views/Menus/MeetingCommands.swift")
        let palette = try #require(menus.range(of: "MainWindowRegistry.remonter()"))
        let ouverture = try #require(menus.range(of: "MainRouter.shared.ouvrirPalette()"))
        #expect(palette.lowerBound < ouverture.lowerBound,
                "remonter la fenêtre avant de poser l'état, sinon la palette s'ouvre dans le vide")

        let barre = Self.source("OneToOne/Services/MenuBarController.swift")
        let remontee = try #require(barre.range(of: "MainWindowRegistry.remonter()"))
        let route = try #require(barre.range(of: "MainRouter.shared.openProject(project)"))
        #expect(remontee.lowerBound < route.lowerBound)
        // `NSApp.activate` seul ne suffisait pas : il ramène l'application, pas
        // la fenêtre principale devant celle d'une réunion.
        #expect(!barre.contains("""
                        NSApp.activate(ignoringOtherApps: true)
                        MainRouter.shared.openProject(project)
                        """))
    }
}
