import CoreGraphics
import Foundation
import Testing
@testable import OneToOne

/// Le tracé de la zone à la souris (écart n° 3 laissé par le lot 7).
///
/// Aucune fenêtre n'est créée : ce qui se casse dans un sélecteur de zone est la
/// géométrie — un axe inversé, un glissement à l'envers, un clic pris pour une zone.
@Suite("RegionSelection")
struct RegionSelectionTests {

    private let ecran = CGSize(width: 1_000, height: 800)

    @Test("le rectangle dessiné se moque du sens du glissement")
    func drawnRectIsDirectionAgnostic() {
        let attendu = CGRect(x: 100, y: 50, width: 300, height: 200)
        #expect(RegionSelection.drawnRect(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 400, y: 250)) == attendu)
        #expect(RegionSelection.drawnRect(from: CGPoint(x: 400, y: 250), to: CGPoint(x: 100, y: 50)) == attendu)
    }

    @Test("la zone normalisée est en fraction de l'écran, origine en haut à gauche")
    func normalizedIsTopLeft() throws {
        let zone = try #require(RegionSelection.normalized(
            from: CGPoint(x: 100, y: 80), to: CGPoint(x: 600, y: 480), in: ecran))
        #expect(zone.x == 0.1)
        #expect(zone.y == 0.1)
        #expect(zone.width == 0.5)
        #expect(zone.height == 0.5)
    }

    @Test("un glissement à l'envers donne la même zone")
    func reversedDragSameZone() {
        let direct = RegionSelection.normalized(
            from: CGPoint(x: 100, y: 80), to: CGPoint(x: 600, y: 480), in: ecran)
        let inverse = RegionSelection.normalized(
            from: CGPoint(x: 600, y: 480), to: CGPoint(x: 100, y: 80), in: ecran)
        #expect(direct == inverse)
    }

    @Test("un clic, ou un tracé trop fin, n'est pas une zone")
    func tinyDragIsRefused() {
        // Clic net.
        #expect(RegionSelection.normalized(
            from: CGPoint(x: 500, y: 400), to: CGPoint(x: 500, y: 400), in: ecran) == nil)
        // Trait horizontal : large mais sans hauteur.
        #expect(RegionSelection.normalized(
            from: CGPoint(x: 100, y: 400), to: CGPoint(x: 900, y: 405), in: ecran) == nil)
        // Sous les 2 % sur les deux axes.
        #expect(RegionSelection.normalized(
            from: CGPoint(x: 100, y: 100), to: CGPoint(x: 115, y: 112), in: ecran) == nil)
        // Juste au-dessus du seuil : acceptée.
        #expect(RegionSelection.normalized(
            from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 130), in: ecran) != nil)
    }

    @Test("un écran de taille nulle ne produit pas de zone")
    func zeroSizedScreen() {
        #expect(RegionSelection.normalized(
            from: .zero, to: CGPoint(x: 10, y: 10), in: .zero) == nil)
    }

    @Test("une zone débordant l'écran est ramenée dans le cadre")
    func clampedToScreen() throws {
        let zone = try #require(RegionSelection.normalized(
            from: CGPoint(x: 800, y: 700), to: CGPoint(x: 1_400, y: 1_200), in: ecran))
        #expect(zone.x + zone.width <= 1.0)
        #expect(zone.y + zone.height <= 1.0)
        #expect(zone.width > 0)
        #expect(zone.height > 0)
    }
}
