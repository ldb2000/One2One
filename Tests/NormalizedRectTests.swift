import Testing
import CoreGraphics
import Foundation
@testable import OneToOne

@Suite("NormalizedRect")
struct NormalizedRectTests {

    @Test("la zone entière ne change pas les dimensions")
    func fullKeepsSize() throws {
        let image = SlideImageFixtures.solid(gray: 0.5, width: 800, height: 600)
        let cropped = try #require(NormalizedRect.full.apply(to: image))
        #expect(cropped.width == 800)
        #expect(cropped.height == 600)
    }

    @Test("une même zone normalisée survit au redimensionnement de la fenêtre")
    func survivesResize() throws {
        let zone = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let small = try #require(zone.apply(to: SlideImageFixtures.solid(gray: 0.5, width: 400, height: 300)))
        let large = try #require(zone.apply(to: SlideImageFixtures.solid(gray: 0.5, width: 800, height: 600)))
        #expect(small.width == 200)
        #expect(small.height == 150)
        #expect(large.width == 400)
        #expect(large.height == 300)
    }

    @Test("les coordonnées hors bornes sont ramenées dans 0...1")
    func clamping() {
        let zone = NormalizedRect(x: -0.5, y: 0.8, width: 3, height: 3)
        #expect(zone.x == 0)
        #expect(zone.y == 0.8)
        #expect(zone.width == 1)
        #expect(abs(zone.height - 0.2) < 1e-12)
    }

    @Test("une zone de surface nulle est vide et ne recadre rien")
    func degenerate() {
        let zone = NormalizedRect(x: 0.5, y: 0.5, width: 0, height: 0.3)
        #expect(zone.isEmpty)
        #expect(zone.apply(to: SlideImageFixtures.solid(gray: 0.5)) == nil)
    }

    @Test("le crop y=0 porte sur le HAUT de l'image à l'écran")
    func topLeftOrigin() throws {
        // CoreGraphics dessine origine en bas : ce rectangle est la moitié BASSE.
        let image = SlideImageFixtures.make(width: 100, height: 100) { ctx in
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }
        // y = 0, hauteur 0,5 → moitié HAUTE à l'écran, donc la partie blanche.
        let top = try #require(NormalizedRect(x: 0, y: 0, width: 1, height: 0.5).apply(to: image))
        let fp = try #require(SlideFingerprint(image: top))
        let white = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 1)))
        #expect(fp.distance(to: white) < 0.02)
    }

    @Test("un glissement sous le seuil des 5 % laisse la zone actuelle inchangée")
    func dragBelowThresholdKeepsCurrent() {
        let size = CGSize(width: 400, height: 400)
        let current = NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let result = NormalizedRect.fromDrag(
            from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 60), in: size, current: current
        )
        #expect(result == current)
    }

    @Test("les quatre composantes du glissement sont ancrées sur des valeurs asymétriques")
    func dragCandidateAsymmetricComponents() {
        // Vue bien plus large que haute, glissement dans le quart supérieur gauche :
        // quatre valeurs attendues toutes distinctes, y proche de 0 (le haut). Une
        // inversion d'axe Y ou une confusion x/y ferait échouer ce test, contrairement
        // au test d'aller-retour ci-dessous.
        let size = CGSize(width: 1000, height: 200)
        let result = NormalizedRect.fromDrag(
            from: CGPoint(x: 100, y: 10), to: CGPoint(x: 250, y: 70), in: size, current: .full
        )
        #expect(abs(result.x - 0.1) < 1e-12)
        #expect(abs(result.y - 0.05) < 1e-12)
        #expect(abs(result.width - 0.15) < 1e-12)
        #expect(abs(result.height - 0.3) < 1e-12)
    }

    @Test("l'ordre des deux points du glissement est indifférent")
    func dragDirectionAgnostic() {
        let size = CGSize(width: 400, height: 400)
        let forward = NormalizedRect.fromDrag(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 300, y: 200), in: size, current: .full)
        let backward = NormalizedRect.fromDrag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), in: size, current: .full)
        #expect(forward == backward)
    }

    @Test("un glissement débordant est borné, une vue de taille nulle ne casse rien")
    func dragClampsAndTolerantToDegenerateSize() {
        let overflow = NormalizedRect.fromDrag(
            from: CGPoint(x: -200, y: -200), to: CGPoint(x: 900, y: 900),
            in: CGSize(width: 400, height: 400), current: .full
        )
        #expect(overflow.x >= 0 && overflow.width <= 1 && !overflow.isEmpty)

        let current = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        for size in [CGSize(width: 0, height: 100), CGSize(width: 100, height: -10), .zero] {
            let r = NormalizedRect.fromDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50), in: size, current: current)
            #expect(r.x >= 0 && r.x <= 1 && r.width >= 0 && r.width <= 1)
        }
    }

    @Test("displayRect suit la convention haut-gauche, sans inversion d'axe Y")
    func displayRectTopLeftConvention() {
        let zone = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        #expect(zone.displayRect(in: CGSize(width: 800, height: 400)) == CGRect(x: 200, y: 200, width: 400, height: 100))
    }

    @Test("la zone survit à un aller-retour Codable")
    func codableRoundTrip() throws {
        let zone = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let data = try JSONEncoder().encode(zone)
        #expect(try JSONDecoder().decode(NormalizedRect.self, from: data) == zone)
    }
}
