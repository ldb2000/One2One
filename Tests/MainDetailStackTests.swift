import Testing
import Foundation
@testable import OneToOne

/// La pile de navigation de la colonne détail se vide quand la route change.
///
/// **Le défaut.** La liste des réunions pousse `MeetingView` par un
/// `NavigationLink` inline, dans la pile **implicite** de la colonne détail du
/// `NavigationSplitView`. Depuis le routeur (décision **D0**), la colonne est
/// un `switch` sur `MainRouter.route` : changer de route remplace la **racine**
/// de cette pile, mais pas ce qui a été poussé par-dessus. Cliquer « Notes »
/// dans la barre latérale écrivait bien la route, l'écran des notes se montait
/// bien — sous la réunion, invisible. La barre latérale semblait morte.
/// Reproduit le 2026-09-14 sur macOS 26.5 dans un projet minimal.
///
/// **La règle.** La colonne détail porte sa propre `NavigationStack`, dont
/// l'identité est `MainRoute.pileDeDetail` : une route nouvelle recrée la pile,
/// donc la vide. Les onglets d'un même projet partagent une identité — un
/// onglet n'est pas un écran quitté (`MainRouter.switchTab`), et recréer la pile
/// à chaque onglet détruirait l'état de `ProjectScreen`.
@Suite("Pile de navigation de la colonne détail")
struct MainDetailStackTests {

    private let projet = UUID()
    private let autreProjet = UUID()

    @Test("Une route est sa propre identité de pile")
    func identiteSimple() {
        #expect(MainRoute.meetings.pileDeDetail == .meetings)
        #expect(MainRoute.notes.pileDeDetail == .notes)
        #expect(MainRoute.meetings.pileDeDetail != MainRoute.notes.pileDeDetail)
        #expect(MainRoute.searchReports("ged").pileDeDetail == .searchReports("ged"))
    }

    @Test("Les onglets d'un même projet partagent la même pile")
    func ongletsDuMemeProjet() {
        let identites = Set(ProjectTab.allCases.map { MainRoute.project(projet, $0).pileDeDetail })
        #expect(identites.count == 1)
    }

    @Test("Deux projets ont deux piles")
    func deuxProjets() {
        #expect(MainRoute.project(projet, .pilotage).pileDeDetail
                != MainRoute.project(autreProjet, .pilotage).pileDeDetail)
    }

    @Test("La colonne détail porte une NavigationStack identifiée par la route")
    func colonneDetailCablee() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OneToOne/Views/Navigation/MainDetailView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("NavigationStack {"),
                "sans NavigationStack propre, une réunion poussée survit au changement de route")
        #expect(source.contains(".pileDeDetail)"),
                "l'identité de la pile doit être la fonction pure testée ci-dessus")
    }
}
