import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Où se trouve la fenêtre principale, et comment la remonter.
///
/// ## Le défaut qu'il corrige
///
/// Deux points d'entrée posent un état **sur le routeur de la fenêtre
/// principale** depuis l'extérieur de cette fenêtre : l'item de menu
/// « Palette… » (`⌘K`, décision **D1**), qui appelle
/// `MainRouter.ouvrirPalette`, et la recherche de la barre de menus
/// (`MenuBarController.showSearch`), dont « choisir un projet » appelle
/// `MainRouter.openProject`. Tous deux sont atteignables alors que la fenêtre
/// principale est **derrière** une autre application, réduite, ou masquée
/// derrière une fenêtre de réunion.
///
/// L'état était alors posé dans le vide : la palette s'ouvrait, le projet
/// devenait la route courante, et rien ne se voyait — jusqu'à ce que
/// l'utilisateur retrouve la fenêtre par lui-même. `NSApp.activate` seul n'y
/// suffit pas : il ramène l'**application** au premier plan, pas la fenêtre
/// principale devant la fenêtre de réunion.
///
/// ## Comment
///
/// Une référence **faible** à la fenêtre principale, posée par
/// `MainWindowFrameRestorer` — le `NSViewRepresentable` que `ContentView` monte
/// déjà en fond, et qui reçoit la fenêtre dans `viewDidMoveToWindow`. Faible :
/// ce registre ne doit pas garder une fenêtre fermée en vie.
///
/// Le repli par identifiant existe pour le cas où le registre serait vide
/// (fenêtre pas encore montée, ordre d'initialisation) ; il ne doit **jamais**
/// remonter une fenêtre de réunion, d'où `estLaFenetrePrincipale`.
@MainActor
enum MainWindowRegistry {

    /// Les identifiants de fenêtre qui ne sont **pas** la fenêtre principale.
    ///
    /// Ce sont les `WindowGroup(id:)` déclarés par `OneToOneApp`. La fenêtre
    /// principale, elle, est le `WindowGroup` **sans** identifiant : AppKit lui
    /// en fabrique un dérivé du type de son contenu, qu'on ne peut pas épeler.
    /// La règle est donc négative — tout ce qui n'est pas une fenêtre
    /// secondaire connue peut être la principale.
    static let identifiantsSecondaires = ["1to1-meeting", "prep-standalone"]

    /// Un identifiant de fenêtre peut-il être celui de la fenêtre principale ?
    ///
    /// Fonction pure, testée : c'est la seule règle de ce fichier, et elle
    /// décide si un raccourci remonte la bonne fenêtre ou une réunion.
    static func estLaFenetrePrincipale(identifiant: String?) -> Bool {
        guard let identifiant else { return true }
        return !identifiantsSecondaires.contains { identifiant.contains($0) }
    }

    #if canImport(AppKit)
    private weak static var fenetre: NSWindow?

    /// Retenue par `MainWindowFrameRestorer`, qui la reçoit de SwiftUI.
    static func enregistrer(_ fenetre: NSWindow) {
        Self.fenetre = fenetre
    }

    /// Active l'application **et** remonte la fenêtre principale.
    ///
    /// Rend `false` si aucune fenêtre principale n'a pu être trouvée — au
    /// démarrage, ou si l'utilisateur l'a fermée. L'appelant pose son état
    /// quand même : la fenêtre le lira à sa réouverture.
    @discardableResult
    static func remonter(_ application: NSApplication = .shared) -> Bool {
        application.activate(ignoringOtherApps: true)
        if let fenetre {
            fenetre.makeKeyAndOrderFront(nil)
            return true
        }
        guard let secours = application.windows.first(where: {
            $0.isVisible && estLaFenetrePrincipale(identifiant: $0.identifier?.rawValue)
        }) else { return false }
        secours.makeKeyAndOrderFront(nil)
        return true
    }
    #endif
}
