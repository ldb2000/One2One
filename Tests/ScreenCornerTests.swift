import CoreGraphics
import Testing
@testable import OneToOne

/// Tests **portés** de `Teams-Capture/Tests/CaptureDesignTests/ScreenCornerTests.swift`
/// avec le type qu'ils gardent (programme §2.5 : copier, jamais lier — et porter les
/// tests avec le code).
@Suite("ScreenCorner")
struct ScreenCornerTests {

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("le coin retenu est le plus proche du point relâché")
    func nearestCorner() {
        #expect(ScreenCorner.nearest(to: CGPoint(x: 10, y: 10), in: screen) == .bottomLeading)
        #expect(ScreenCorner.nearest(to: CGPoint(x: 990, y: 10), in: screen) == .bottomTrailing)
        #expect(ScreenCorner.nearest(to: CGPoint(x: 10, y: 790), in: screen) == .topLeading)
        #expect(ScreenCorner.nearest(to: CGPoint(x: 990, y: 790), in: screen) == .topTrailing)
        #expect(ScreenCorner.nearest(to: CGPoint(x: 600, y: 500), in: screen) == .topTrailing)
    }

    @Test("l'origine calculée laisse la pastille entièrement visible, marge comprise")
    func originStaysInside() {
        let size = CGSize(width: 300, height: 40)
        for corner in ScreenCorner.allCases {
            let origin = corner.origin(for: size, in: screen, inset: 16)
            #expect(origin.x >= screen.minX + 16)
            #expect(origin.y >= screen.minY + 16)
            #expect(origin.x + size.width <= screen.maxX - 16)
            #expect(origin.y + size.height <= screen.maxY - 16)
        }
    }

    @Test("les quatre origines exactes, pour repérer un axe inversé qu'un « reste dans le cadre » laisserait passer")
    func exactOrigins() {
        let size = CGSize(width: 300, height: 40)
        #expect(ScreenCorner.topLeading.origin(for: size, in: screen, inset: 16) == CGPoint(x: 16, y: 744))
        #expect(ScreenCorner.topTrailing.origin(for: size, in: screen, inset: 16) == CGPoint(x: 684, y: 744))
        #expect(ScreenCorner.bottomLeading.origin(for: size, in: screen, inset: 16) == CGPoint(x: 16, y: 16))
        #expect(ScreenCorner.bottomTrailing.origin(for: size, in: screen, inset: 16) == CGPoint(x: 684, y: 16))
    }

    @Test("sur un écran plus petit que la pastille, l'origine reste dans le cadre")
    func originOnTinyScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 30)
        for corner in ScreenCorner.allCases {
            let origin = corner.origin(for: CGSize(width: 300, height: 40), in: tiny, inset: 16)
            #expect(origin.x >= tiny.minX)
            #expect(origin.y >= tiny.minY)
        }
    }

    @Test("un coin se sérialise en chaîne stable, pour être mémorisé dans AppSettings")
    func rawValuesAreStable() {
        #expect(ScreenCorner.allCases.map(\.rawValue) == [
            "topLeading", "topTrailing", "bottomLeading", "bottomTrailing",
        ])
        #expect(ScreenCorner(rawValue: "bottomTrailing") == .bottomTrailing)
        #expect(ScreenCorner(rawValue: "nulle-part") == nil)
    }
}
