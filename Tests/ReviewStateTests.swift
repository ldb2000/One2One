import Testing
import Foundation
@testable import OneToOne

/// L'état d'écran du mode Relire et son entrée automatique après génération du
/// rapport (spec §2.2 et §2.7 ; périmètre du lot 5, point 6).
///
/// Ces deux règles sont testées **sans vue** parce qu'elles ne se voient pas
/// autrement : un focus posé puis jamais consommé se rejoue à chaque rendu et
/// vole le curseur, et un rapport généré qui laisse l'écran sur l'espace
/// Rapport n'affiche jamais la file d'actions à assigner.
@Suite("État d'écran du mode Relire")
@MainActor
struct ReviewStateTests {

    private func makeScreen() -> MeetingScreenModel {
        MeetingScreenModel(defaults: UserDefaults(suiteName: "test.review.\(UUID().uuidString)")!)
    }

    @Test("Un modèle d'écran neuf porte un état de relecture au repos")
    func freshState() {
        let screen = makeScreen()
        #expect(screen.review.section == .synthese)
        #expect(screen.review.focusRequest == nil)
        #expect(screen.review.toutAfficher == false)
        #expect(screen.review.vue == .liste)
        #expect(screen.review.ligneSelectionnee == nil)
    }

    @Test("Deux demandes de focus identiques sont deux demandes")
    func focusTokenAdvances() {
        let etat = ReviewState()
        etat.demanderFocus(.responsablePremiereActionNonAssignee)
        let premiere = etat.focusRequest
        etat.demanderFocus(.responsablePremiereActionNonAssignee)
        let seconde = etat.focusRequest
        #expect(premiere != nil)
        #expect(seconde != nil)
        #expect(premiere != seconde)
        #expect(premiere?.cible == seconde?.cible)
    }

    @Test("Une demande servie ne se rejoue pas")
    func focusConsumed() {
        let etat = ReviewState()
        etat.demanderFocus(.responsablePremiereActionNonAssignee)
        #expect(etat.focusRequest != nil)
        etat.focusServi()
        #expect(etat.focusRequest == nil)
    }

    @Test("Après le rapport, l'écran passe en Relire et pose le focus d'assignation")
    func afterReportGeneration() {
        let screen = makeScreen()
        screen.space = .report
        screen.mode = .live
        screen.review.section = .actions

        ReviewState.apresGenerationDuRapport(screen)

        #expect(screen.space == .meeting)
        #expect(screen.mode == .review)
        #expect(screen.review.section == .synthese)
        #expect(screen.review.focusRequest?.cible == .responsablePremiereActionNonAssignee)
    }

    @Test("Rapport et Documents changent d'espace, les autres entrées non")
    func sectionsThatSwitchSpace() {
        #expect(ReviewState.Section.rapport.changeDEspace == .report)
        #expect(ReviewState.Section.documents.changeDEspace == .resources)
        for section in [ReviewState.Section.synthese, .notes, .transcription,
                        .actions, .assistant] {
            #expect(section.changeDEspace == nil)
        }
    }

    @Test("Chaque section porte un libellé et un symbole")
    func labelsAreComplete() {
        for section in ReviewState.Section.allCases {
            #expect(!section.libelle.isEmpty)
            #expect(!section.symbole.isEmpty)
        }
    }

    // MARK: - La nav latérale remplace la barre d'espaces

    @Test("La barre d'espaces est masquée dans le poste de pilotage, et là seulement")
    func spacesBarHiddenInReview() {
        // Décision D0 : la nav latérale de 190 px remplace la barre d'espaces
        // dans ce mode.
        #expect(MeetingSpacesBar.estMasquee(space: .meeting, mode: .review))
        // Ailleurs elle reste : en mode Relire, les espaces Rapport et
        // Ressources n'ont pas de nav latérale, et sans barre on s'y
        // retrouverait sans rien pour en sortir.
        #expect(!MeetingSpacesBar.estMasquee(space: .report, mode: .review))
        #expect(!MeetingSpacesBar.estMasquee(space: .resources, mode: .review))
        #expect(!MeetingSpacesBar.estMasquee(space: .meeting, mode: .live))
        #expect(!MeetingSpacesBar.estMasquee(space: .meeting, mode: .prepare))
    }

    // MARK: - Le chemin post-génération de MeetingView

    /// `MeetingView.swift`, lu depuis `#filePath`.
    private var sourceMeetingView: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/
            .deletingLastPathComponent()      // racine
            .appendingPathComponent("OneToOne/Views/MeetingView.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("La génération de rapport passe par la transition du mode Relire")
    func meetingViewUsesTheTransition() {
        let source = sourceMeetingView
        // Sans cette garde, le test passerait sur un fichier introuvable.
        #expect(source.contains("private func generateReport() async"))
        #expect(source.contains("ReviewState.apresGenerationDuRapport(self.screen)"))
    }
}
