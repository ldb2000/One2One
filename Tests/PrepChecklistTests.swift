import Testing
import Foundation
@testable import OneToOne

/// Le bloc « Prochain 1:1 » affiche « Prep à 4 points sur 6 » et quatre lignes
/// cochables. Ces points vivent dans le markdown de `Meeting.prepNotes`, sous
/// forme de cases GFM — c'est déjà ce que l'éditeur y écrit.
@Suite("Préparation d'un 1:1 — les cases vivent dans le markdown")
struct PrepChecklistTests {

    @Test("Les cases se lisent, cochées ou non")
    func itemsAreRead() {
        let markdown = """
        - [ ] 3 actions en retard sur ARC-118
        - [x] Charge support après bascule
        Une ligne qui n'est pas une case
        - [ ] Suite de la mobilité
        """
        let points = PrepChecklist.items(from: markdown)
        #expect(points.count == 3)
        #expect(points[0].text == "3 actions en retard sur ARC-118")
        #expect(points[1].done)
        #expect(!points[2].done)
    }

    @Test("Le compte se lit « n sur N »")
    func countReadsAsDoneOverTotal() {
        let markdown = "- [x] a\n- [x] b\n- [ ] c"
        #expect(PrepChecklist.progress(from: markdown) == "2 points sur 3")
        #expect(PrepChecklist.progress(from: "aucune case") == nil)
    }

    @Test("Cocher une case réécrit le markdown, sans toucher au reste")
    func togglingRewritesOnlyThatLine() {
        let markdown = "Contexte libre\n- [ ] premier\n- [x] second"
        let apres = PrepChecklist.toggled(markdown, at: 0)
        #expect(apres == "Contexte libre\n- [x] premier\n- [x] second")
        #expect(PrepChecklist.toggled(apres, at: 1) == "Contexte libre\n- [x] premier\n- [ ] second")
    }

    @Test("Un rang inexistant laisse le markdown intact")
    func unknownIndexChangesNothing() {
        let markdown = "- [ ] seul"
        #expect(PrepChecklist.toggled(markdown, at: 7) == markdown)
    }
}
