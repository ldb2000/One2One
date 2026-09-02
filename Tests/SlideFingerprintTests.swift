import Testing
import CoreGraphics
import Foundation
@testable import OneToOne

@Suite("SlideFingerprint")
struct SlideFingerprintTests {

    @Test("une empreinte est à distance nulle d'elle-même")
    func identity() throws {
        let fp = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.5)))
        #expect(fp.distance(to: fp) == 0)
    }

    @Test("noir et blanc uniformes sont à distance maximale")
    func opposites() throws {
        let black = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 0)))
        let white = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 1)))
        #expect(black.distance(to: white) > 0.95)
    }

    @Test("la distance est symétrique")
    func symmetry() throws {
        let a = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.2)))
        let b = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.8)))
        #expect(abs(a.distance(to: b) - b.distance(to: a)) < 1e-12)
    }

    @Test("un curseur de souris reste sous le seuil le plus sensible (0,010)")
    func cursorIsInvisible() throws {
        let plain = SlideImageFixtures.banded(fraction: 0.5)
        let withCursor = SlideImageFixtures.make(width: 400, height: 300) { ctx in
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 150))
            // un pointeur de 12x18 points, la taille réelle d'un curseur macOS
            ctx.setFillColor(gray: 0.2, alpha: 1)
            ctx.fill(CGRect(x: 200, y: 200, width: 12, height: 18))
        }
        let a = try #require(SlideFingerprint(image: plain))
        let b = try #require(SlideFingerprint(image: withCursor))
        #expect(a.distance(to: b) < 0.010)
    }

    @Test("un bandeau de 2 % de la hauteur donne une distance d'environ 0,019")
    func twoPercentBanner() throws {
        let a = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.50)))
        let b = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.52)))
        let d = a.distance(to: b)
        #expect(d > 0.015 && d < 0.025)
    }

    @Test("un changement de slide franchit même le seuil le moins sensible (0,045)")
    func slideChangeIsVisible() throws {
        let a = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.2)))
        let b = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.7)))
        #expect(a.distance(to: b) > 0.045)
    }

    @Test("l'empreinte a toujours 32x32 échantillons")
    func fixedSize() throws {
        let fp = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 0.5, width: 1920, height: 1080)))
        #expect(fp.samples.count == 32 * 32)
    }

    @Test("une empreinte se lit depuis un PNG sur disque et vaut celle de l'image")
    func loadsFromPNG() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("slide-0001-101010.png")
        let image = SlideImageFixtures.banded(fraction: 0.3)
        try SlideImageFixtures.writePNG(image, to: url)

        let fromDisk = try #require(SlideFingerprint(contentsOf: url))
        let fromImage = try #require(SlideFingerprint(image: image))
        #expect(fromDisk.distance(to: fromImage) < 0.001)
        #expect(SlideFingerprint(contentsOf: dir.appendingPathComponent("absent.png")) == nil)
    }
}
