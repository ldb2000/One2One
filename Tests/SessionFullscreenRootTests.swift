import Testing
import Foundation
import AppKit
import SwiftUI
@testable import OneToOne

/// La **racine de la fenêtre** en mode séance (spec §2.6, correctif du
/// 2026-09-08).
///
/// Ce qui a manqué au lot 4 : sa bascule demandait le plein écran à AppKit
/// **et** substituait le `contentView` de la fenêtre. Or cette substitution
/// détache la vue qui l'a commandée, SwiftUI fait aussitôt partir son
/// `onDisappear`, et le `sortir()` de celui-ci restaure le cockpit avant même
/// que `toggleFullScreen` ne soit appelé — la fenêtre partait en plein écran
/// sur le cockpit clair et l'écran 1b n'était jamais visible (recette du
/// 2026-09-07, écart n° 1). Reproduit hors application : une affectation de
/// `NSWindow.contentView` fait partir le `onDisappear` de l'ancienne racine
/// **synchroniquement**, dans l'affectation elle-même.
///
/// La règle est désormais qu'un état — et non AppKit — décide de ce qui est à
/// l'écran. Ces tests la tiennent.
@Suite("La racine de la fenêtre en mode séance")
@MainActor
struct SessionFullscreenRootTests {

    // MARK: - La machine d'état

    @Test("La bascule du mode choisit la racine, et rien d'autre ne la choisit")
    func stateDrivesRoot() {
        let seance = SessionFullscreenState()

        // Au repos : la fenêtre ordinaire.
        #expect(SessionFullscreenRoot.pour(seanceAffichee: seance.isPresented) == .fenetre)

        seance.enter()
        #expect(seance.isPresented)
        #expect(SessionFullscreenRoot.pour(seanceAffichee: seance.isPresented) == .seance)

        // Une seconde entrée ne change rien (idempotence de `enter`).
        let origine = seance.enteredAt
        seance.enter()
        #expect(seance.enteredAt == origine)
        #expect(SessionFullscreenRoot.pour(seanceAffichee: seance.isPresented) == .seance)

        seance.leave()
        #expect(!seance.isPresented)
        #expect(SessionFullscreenRoot.pour(seanceAffichee: seance.isPresented) == .fenetre)
        // `enteredAt` survit : rentrer dans la même séance ne remet pas les
        // compteurs de `CAPTURÉ CETTE SÉANCE` à zéro.
        #expect(seance.enteredAt == origine)
    }

    @Test("Sans séance publiée, aucune racine ne monte le mode")
    func nothingPublishedShowsNothing() {
        let presentateur = SessionFullscreenPresenter.shared
        presentateur.retirerLaPresentation()
        #expect(!presentateur.estAffiche(dans: nil))
        #expect(presentateur.vue == nil)
        #expect(presentateur.seance == nil)
    }

    @Test("La séance publiée n'est montée que par la racine de sa fenêtre")
    func onlyThePresentingWindowShowsIt() {
        // Deux fenêtres réunion peuvent être ouvertes ; la racine de l'autre
        // ne doit pas monter la même séance en double.
        _ = NSApplication.shared
        let sienne = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let autre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: true)
        let presentateur = SessionFullscreenPresenter.shared
        let seance = SessionFullscreenState()

        presentateur.presenter(dans: sienne, seance: seance) { AnyView(EmptyView()) }
        // Publiée mais pas encore entrée : la racine reste la fenêtre.
        #expect(!presentateur.estAffiche(dans: sienne))

        seance.enter()
        #expect(presentateur.estAffiche(dans: sienne))
        #expect(SessionFullscreenRoot.pour(
            seanceAffichee: presentateur.estAffiche(dans: sienne)) == .seance)
        #expect(!presentateur.estAffiche(dans: autre))
        #expect(SessionFullscreenRoot.pour(
            seanceAffichee: presentateur.estAffiche(dans: autre)) == .fenetre)
        #expect(!presentateur.estAffiche(dans: nil))

        // La sortie dépublie : la racine redevient la fenêtre, même si l'état
        // était resté à `isPresented`.
        presentateur.retirerLaPresentation()
        #expect(!presentateur.estAffiche(dans: sienne))
        // Idempotent : le démontage rappelle la dépublication.
        presentateur.retirerLaPresentation()
        #expect(!presentateur.estAffiche(dans: sienne))
    }

    // MARK: - Ce que les sources doivent dire

    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ chemin: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8)
    }

    @Test("La racine de chaque fenêtre à réunion branche le mode séance")
    func windowRootsHostTheMode() throws {
        let app = try source("OneToOne/OneToOneApp.swift")
        // Les deux scènes qui peuvent afficher une réunion : la fenêtre
        // principale et la fenêtre dédiée `1to1-meeting` du correctif #31.
        let poses = app.components(separatedBy: ".sessionFullscreenHost()").count - 1
        #expect(poses == 2, "poses de sessionFullscreenHost() dans OneToOneApp : \(poses)")
        #expect(app.contains("1to1-meeting"))
    }

    @Test("La racine se décide sur screen.session, pas sur NSWindow")
    func rootBranchesOnTheSessionState() throws {
        let hote = try source("OneToOne/Views/Meeting/Session/SessionFullscreenHost.swift")
        // La racine lit l'état publié et monte la vue publiée.
        #expect(hote.contains("presentateur.estAffiche(dans: fenetre)"))
        #expect(hote.contains("presentateur.vue"))
        #expect(hote.contains("SessionFullscreenRoot.pour") || hote.contains(".pour(seanceAffichee:"))

        let presentateur = try source("OneToOne/Views/Meeting/Session/SessionFullscreenPresenter.swift")
        // Ce qui est publié est bien `screen.session` de l'écran, et la vue
        // publiée est bien le mode séance.
        #expect(presentateur.contains("seance: screen.session"))
        #expect(presentateur.contains("SessionFullscreenView("))
        // Et l'état publié est ce que `estAffiche` interroge.
        #expect(presentateur.contains("seance?.isPresented == true"))
    }

    @Test("Plus aucune substitution de contentView, et plus de code mort")
    func noAppKitViewSwapLeft() throws {
        let dossier = racine.appendingPathComponent("OneToOne", isDirectory: true)
        let enumerateur = FileManager.default.enumerator(at: dossier,
                                                         includingPropertiesForKeys: nil)
        var coupables: [String] = []
        var swapperEncoreLa: [String] = []
        while let url = enumerateur?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let texte = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            // La substitution qui annulait la présentation. Elle n'a pas de
            // repli : si elle échoue, la fenêtre part en plein écran sur
            // l'ancien contenu, sans que rien ne le signale. Cherchée dans le
            // seul dossier du mode séance — `SlashPanel` et `MentionPanel`
            // posent le `contentView` de **leur** `NSPanel`, ce qui est
            // légitime — et hors commentaires, qui en parlent exprès.
            if url.pathComponents.contains("Session") {
                let lignes = texte.split(separator: "\n", omittingEmptySubsequences: false)
                let code = lignes.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                if code.contains(where: { $0.contains("contentView =") }) {
                    coupables.append(url.lastPathComponent)
                }
            }
            if texte.contains("SessionWindowSwapper") {
                swapperEncoreLa.append(url.lastPathComponent)
            }
        }
        #expect(coupables.isEmpty,
                "substitution de contentView encore présente : \(coupables)")
        #expect(swapperEncoreLa.isEmpty,
                "SessionWindowSwapper est du code mort : \(swapperEncoreLa)")
    }

    @Test("AppKit ne fait plus que le plein écran")
    func appKitOnlyDoesFullscreen() throws {
        let presentateur = try source("OneToOne/Views/Meeting/Session/SessionFullscreenPresenter.swift")
        #expect(presentateur.contains("toggleFullScreen"))
        // Entrer par une autre voie que la pilule ou le menu — l'item natif
        // « Activer le mode plein écran » porte le même `⌃⌘F`, le bouton vert
        // de la barre de titre aussi — doit conduire au même écran.
        #expect(presentateur.contains("willEnterFullScreenNotification"))
        #expect(presentateur.contains("willExitFullScreenNotification"))
    }
}
