import AppKit
import XCTest
@testable import OneToOne

/// Caractérise `SlashPanelPositioning.origin` : la seule partie du panneau du
/// menu `/` testable sans interface (voir `OneToOne/Markdown/Slash/SlashPanel.swift`).
/// Le reste du panneau (rendu SwiftUI, focus, positionnement réel d'un
/// `NSPanel`) n'a pas de couverture automatisée dans ce projet — il n'existe
/// pas de dépendance permettant de piloter des vues SwiftUI ici.
final class SlashPanelPositioningTests: XCTestCase {

    /// Écran de référence pour tous les tests : 1440×900, pas de menu bar/dock
    /// à modéliser puisqu'on part directement de `visibleFrame`.
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let panelSize = NSSize(width: 260, height: 200)

    // MARK: - Cas nominal : sous le curseur

    func test_nominal_positionsJustBelowCursor() {
        // Curseur au milieu de l'écran, largement assez de place en dessous.
        let cursorRect = NSRect(x: 300, y: 500, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: panelSize, visibleFrame: screen)

        // Bord haut du panneau (origin.y + height) touche le bas du curseur.
        XCTAssertEqual(origin.y + panelSize.height, cursorRect.minY, accuracy: 0.001)
        XCTAssertEqual(origin.x, cursorRect.minX, accuracy: 0.001)
    }

    // MARK: - Débordement en bas : bascule au-dessus

    func test_bottomOverflow_flipsAboveCursor() {
        // Curseur près du bas de l'écran : loger le panneau en dessous
        // (200pt de haut) le ferait sortir de l'écran.
        let cursorRect = NSRect(x: 300, y: 30, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: panelSize, visibleFrame: screen)

        // Bascule : le bord bas du panneau touche le haut du curseur.
        XCTAssertEqual(origin.y, cursorRect.maxY, accuracy: 0.001)
        // Et cette bascule évite bien le débordement qu'aurait produit le cas nominal.
        XCTAssertLessThan(cursorRect.minY - panelSize.height, screen.minY, "précondition : le cas nominal aurait débordé")
    }

    // MARK: - Débordement à droite : recalage

    func test_rightOverflow_clampsToScreenEdge() {
        // Curseur proche du bord droit : x + largeur du panneau dépasserait
        // l'écran sans recalage.
        let cursorRect = NSRect(x: 1400, y: 500, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(origin.x, screen.maxX - panelSize.width, accuracy: 0.001)
        XCTAssertLessThanOrEqual(origin.x + panelSize.width, screen.maxX)
    }

    // MARK: - Curseur près du bord supérieur : reste en dessous

    func test_cursorNearTopEdge_staysBelowRatherThanFlipping() {
        // Le curseur est tout en haut de l'écran ; il y a largement la place
        // de loger le panneau en dessous (tout l'écran, hormis quelques
        // points). Il ne doit PAS basculer au-dessus (ce qui le ferait
        // sortir de l'écran par le haut).
        let cursorRect = NSRect(x: 300, y: 880, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(origin.y + panelSize.height, cursorRect.minY, accuracy: 0.001,
                        "doit rester positionné sous le curseur, pas basculer au-dessus")
    }

    // MARK: - Filet de sécurité : rectangle curseur aberrant (hors écran)

    func test_degenerateCursorBelowScreen_clampsToVisibleFrameBottom() {
        // Rectangle curseur situé sous le bas de l'écran (donnée aberrante,
        // ex. rect périmé) : même la bascule au-dessus (cursorRect.maxY)
        // resterait sous l'écran. Le filet de sécurité doit ramener le
        // panneau dans le cadre visible plutôt que de le laisser hors écran.
        let cursorRect = NSRect(x: 300, y: -100, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(origin.y, screen.minY, accuracy: 0.001)
    }

    // MARK: - Débordement à gauche : recalage symétrique

    func test_leftOverflow_clampsToScreenEdge() {
        let cursorRect = NSRect(x: -50, y: 500, width: 2, height: 16)

        let origin = SlashPanelPositioning.origin(cursorRect: cursorRect, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(origin.x, screen.minX, accuracy: 0.001)
    }
}
