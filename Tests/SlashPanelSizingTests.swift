import AppKit
import XCTest
@testable import OneToOne

/// Caractérise `SlashPanelSizing.height` : la partie du panneau du menu `/`
/// qui décide s'il déborde de l'écran (voir la doc de tête de
/// `SlashPanel.swift` et le rapport de tâche du plafonnement/défilement).
/// Extraite pour rester testable sans `[DisplayGroup]` (type privé au
/// fichier `SlashPanel.swift`) — même stratégie que `SlashPanelPositioning`,
/// voir `Tests/SlashPanelPositioningTests.swift`.
///
/// Le reste du panneau (rendu SwiftUI du `ScrollView`, défilement réel au
/// clavier) n'a pas de couverture automatisée ici — pas de dépendance
/// permettant de piloter une vue SwiftUI dans ce projet.
final class SlashPanelSizingTests: XCTestCase {

    // MARK: - Suit le contenu en deçà du plafond

    func test_belowCap_followsContent_forCurrentFilteredCatalogExample() {
        // "titre" (voir `SlashCatalogTests`) : 1 groupe (« Blocs de base »),
        // 3 entrées (Titre 1/2/3) — bien en deçà du plafond.
        let height = SlashPanelSizing.height(groupCount: 1, rowCount: 3)

        let expected = SlashPanelMetrics.verticalInset * 2
            + 1 * SlashPanelMetrics.headerHeight
            + 3 * SlashPanelMetrics.rowHeight
        XCTAssertEqual(height, expected, accuracy: 0.001)
        XCTAssertLessThan(height, SlashPanelMetrics.maxHeight,
                           "3 entrées filtrées ne doivent pas atteindre le plafond")
    }

    func test_belowCap_threeFilteredEntries_doesNotGrowToThePlafond() {
        // Exigence explicite de la tâche : à 3 entrées filtrées, le panneau
        // doit faire 3 lignes, pas le plafond.
        let threeRows = SlashPanelSizing.height(groupCount: 1, rowCount: 3)
        let capped = SlashPanelSizing.height(groupCount: 3, rowCount: 12)

        XCTAssertLessThan(threeRows, capped,
                           "un panneau à 3 entrées ne doit pas faire la même hauteur qu'un panneau plafonné")
    }

    // MARK: - Plafonné au-delà d'un certain nombre d'entrées

    func test_atCap_currentFullCatalog_isClampedBelowItsNaturalHeight() {
        // Le catalogue complet, non filtré (`SlashCatalog.all` : 12 entrées,
        // 3 groupes) mesure naturellement 390pt sans plafond — mesure citée
        // par la tâche. Avec le plafond, il doit être ramené à `maxHeight`.
        let natural = SlashPanelMetrics.verticalInset * 2
            + 3 * SlashPanelMetrics.headerHeight
            + 12 * SlashPanelMetrics.rowHeight
        XCTAssertEqual(natural, 390, accuracy: 0.001, "prémisse : hauteur naturelle mesurée par la tâche")

        let height = SlashPanelSizing.height(groupCount: 3, rowCount: 12)

        XCTAssertEqual(height, SlashPanelMetrics.maxHeight, accuracy: 0.001)
        XCTAssertLessThan(height, natural, "le plafond doit s'exercer dès le catalogue actuel, non filtré")
    }

    func test_atCap_hypotheticalTwentyFourEntries_isClampedToTheSameHeight() {
        // Reprend l'exemple à 24 entrées de la tâche (~724pt sans plafond) :
        // doit être ramené exactement à `maxHeight`, comme le catalogue
        // actuel — le plafond ne dépend que d'avoir dépassé le seuil, pas de
        // combien.
        let height = SlashPanelSizing.height(groupCount: 3, rowCount: 24)

        XCTAssertEqual(height, SlashPanelMetrics.maxHeight, accuracy: 0.001)
    }

    func test_cap_isMonotonic_moreRowsNeverExceedsMaxHeight() {
        let capped100 = SlashPanelSizing.height(groupCount: 5, rowCount: 100)
        XCTAssertEqual(capped100, SlashPanelMetrics.maxHeight, accuracy: 0.001,
                        "aucune quantité de contenu ne doit dépasser le plafond")
    }

    // MARK: - Frontière exacte du plafond

    func test_exactlyAtRowBudget_withNoHeader_matchesCapExactly() {
        // `maxVisibleRows` lignes, sans en-tête : la hauteur naturelle et le
        // plafond coïncident exactement à cette frontière.
        let height = SlashPanelSizing.height(groupCount: 0, rowCount: SlashPanelMetrics.maxVisibleRows)

        XCTAssertEqual(height, SlashPanelMetrics.maxHeight, accuracy: 0.001)
    }

    func test_oneRowPastTheBudget_getsClamped() {
        let atBudget = SlashPanelSizing.height(groupCount: 0, rowCount: SlashPanelMetrics.maxVisibleRows)
        let pastBudget = SlashPanelSizing.height(groupCount: 0, rowCount: SlashPanelMetrics.maxVisibleRows + 1)

        XCTAssertEqual(pastBudget, atBudget, accuracy: 0.001,
                        "une ligne de plus que le plafond ne doit plus faire grandir le panneau")
    }

    // MARK: - Positionnement au plafond (délégation à `SlashPanelPositioning`)

    /// `idealSize` alimente directement `SlashPanel.show(near:on:)` via
    /// `frame.size` — ce test vérifie que la taille plafonnée, une fois
    /// passée à `SlashPanelPositioning.origin` (déjà testée séparément dans
    /// `Tests/SlashPanelPositioningTests.swift`), continue à produire un
    /// positionnement dans l'écran, y compris la bascule au-dessus du
    /// curseur quand la place manque en dessous.
    func test_cappedPanelSize_positionsBelowCursor_whenRoomAvailable() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let cappedSize = NSSize(width: SlashPanelMetrics.width, height: SlashPanelMetrics.maxHeight)
        let cursorRect = NSRect(x: 300, y: 500, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: cappedSize, visibleFrame: screen)

        XCTAssertEqual(origin.y + cappedSize.height, cursorRect.minY, accuracy: 0.001,
                        "assez de place en dessous : pas de bascule")
    }

    func test_cappedPanelSize_stillPositionsWithinScreen_whenFlippingAboveCursor() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let cappedSize = NSSize(width: SlashPanelMetrics.width, height: SlashPanelMetrics.maxHeight)
        // Curseur proche du bas de l'écran : le loger en dessous (avec la
        // hauteur plafonnée) le ferait déborder.
        let cursorRect = NSRect(x: 300, y: 50, width: 2, height: 16)
        XCTAssertLessThan(cursorRect.minY - cappedSize.height, screen.minY,
                           "précondition : le cas nominal (sous le curseur) déborderait bien de l'écran")

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: cappedSize, visibleFrame: screen)

        XCTAssertEqual(origin.y, cursorRect.maxY, accuracy: 0.001, "doit basculer au-dessus du curseur")
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
        XCTAssertLessThanOrEqual(origin.y + cappedSize.height, screen.maxY,
                                  "le panneau plafonné, une fois basculé au-dessus, doit tenir dans l'écran")
    }
}
