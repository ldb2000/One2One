import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images de test pour la capture de slides. Le contexte fourni au closure a son
/// origine **en bas à gauche** (convention CoreGraphics) : un rectangle dessiné en
/// `y: 0` est le BAS de l'image à l'écran. Les tests d'axe en tiennent compte.
enum SlideImageFixtures {

    static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { fatalError("contexte de test non créable") }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(ctx)
        guard let image = ctx.makeImage() else { fatalError("image de test non créable") }
        return image
    }

    /// Image uniforme d'un gris donné (0 = noir, 1 = blanc).
    static func solid(gray: Double, width: Int = 400, height: Int = 300) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: gray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Image blanche avec un bandeau noir couvrant `fraction` de la hauteur (en bas).
    /// Simule un changement de contenu d'ampleur contrôlée.
    static func banded(fraction: Double, width: Int = 400, height: Int = 300) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height) * fraction))
        }
    }

    /// Écrit une image en PNG, sans passer par le service : simule un lot déjà sur disque.
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
