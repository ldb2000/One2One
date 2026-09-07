import Testing
import CoreGraphics
@testable import OneToOne

/// Décision **D10** du programme : « Vues Calendrier/Eisenhower dans le rail
/// 330 px — conservées dans le rail (comme sur `1a-cockpit.png`) en rendu
/// compact. La capture fait foi. »
///
/// Le rendu compact est un **ajout** : le paramètre est optionnel et son défaut
/// reproduit exactement les métriques d'avant. C'est ce que ces tests
/// verrouillent — une régression sur l'écran Actions plein serait invisible
/// autrement, puisque personne ne mesure une cellule de calendrier à l'œil.
@Suite("Rendus compacts du calendrier et d'Eisenhower")
struct ActionsBoardsCompactTests {

    @Test("Le calendrier garde ses métriques d'origine par défaut")
    func calendarDefaultsUnchanged() {
        #expect(CalendarBoard.dayCellMinHeight(fillsAvailableSpace: false, compact: false) == 46)
        #expect(CalendarBoard.dayCellMinHeight(fillsAvailableSpace: true, compact: false) == 84)
        #expect(CalendarBoard.maxChipsPerDay(fillsAvailableSpace: false, compact: false) == 2)
        #expect(CalendarBoard.maxChipsPerDay(fillsAvailableSpace: true, compact: false) == 6)
    }

    @Test("Le calendrier compact resserre la cellule et n'y montre qu'une action")
    func calendarCompactIsSmaller() {
        let compacte = CalendarBoard.dayCellMinHeight(fillsAvailableSpace: false, compact: true)
        #expect(compacte < CalendarBoard.dayCellMinHeight(fillsAvailableSpace: false, compact: false))
        #expect(compacte == 32)
        #expect(CalendarBoard.maxChipsPerDay(fillsAvailableSpace: false, compact: true) == 1)
    }

    @Test("Plein écran l'emporte sur compact : les deux ne se cumulent pas")
    func fillsAvailableSpaceWins() {
        // Le cas ne se produit pas dans l'app, mais un appelant distrait ne
        // doit pas obtenir une grille pleine hauteur aux cellules minuscules.
        #expect(CalendarBoard.dayCellMinHeight(fillsAvailableSpace: true, compact: true) == 84)
        #expect(CalendarBoard.maxChipsPerDay(fillsAvailableSpace: true, compact: true) == 6)
    }

    @Test("Eisenhower garde ses métriques d'origine par défaut")
    func eisenhowerDefaultsUnchanged() {
        #expect(EisenhowerBoard.boxMinHeight(fillsAvailableSpace: false, compact: false) == 90)
        // Plein écran, la hauteur est imposée par le conteneur, pas par la boîte.
        #expect(EisenhowerBoard.boxMinHeight(fillsAvailableSpace: true, compact: false) == nil)
    }

    @Test("Eisenhower compact réduit la hauteur de quadrant")
    func eisenhowerCompactIsSmaller() {
        let compacte = EisenhowerBoard.boxMinHeight(fillsAvailableSpace: false, compact: true)
        #expect(compacte == 54)
        #expect((compacte ?? 0) < 90)
        #expect(EisenhowerBoard.boxMinHeight(fillsAvailableSpace: true, compact: true) == nil)
    }
}
