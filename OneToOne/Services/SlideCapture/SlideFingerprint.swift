import CoreGraphics
import Foundation
import ImageIO

/// Signature compacte d'une image, conçue pour comparer deux captures successives.
///
/// La réduction à 32×32 en niveaux de gris est le cœur de la robustesse du détecteur :
/// à cette échelle un curseur de souris ou du bruit de compression pèsent moins d'un
/// millième de la surface, alors qu'un changement de slide en modifie une large part.
struct SlideFingerprint: Equatable, Sendable {

    /// Côté de l'empreinte, en échantillons.
    static let side = 32

    /// Luminances, ligne par ligne, `side * side` éléments.
    let samples: [UInt8]

    init(samples: [UInt8]) {
        precondition(samples.count == SlideFingerprint.side * SlideFingerprint.side,
                     "une empreinte fait exactement \(SlideFingerprint.side * SlideFingerprint.side) échantillons")
        self.samples = samples
    }

    /// Réduit l'image en empreinte. Retourne `nil` si CoreGraphics refuse le contexte.
    init?(image: CGImage) {
        let side = SlideFingerprint.side
        guard let space = CGColorSpace(name: CGColorSpace.linearGray) else { return nil }
        var buffer = [UInt8](repeating: 0, count: side * side)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side, space: space,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            // `.high` fait une vraie moyenne des pixels sources ; c'est ce qui rend
            // l'empreinte insensible au curseur. Ne pas baisser cette qualité.
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        self.samples = buffer
    }

    /// Empreinte d'un PNG sur disque (réamorçage d'un lot existant). `nil` si le
    /// fichier est absent ou illisible.
    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image: image)
    }

    /// Écart moyen normalisé entre deux empreintes.
    /// `0` = images identiques, `1` = noir uniforme contre blanc uniforme.
    func distance(to other: SlideFingerprint) -> Double {
        var total = 0
        for index in samples.indices {
            total += abs(Int(samples[index]) - Int(other.samples[index]))
        }
        return Double(total) / (Double(samples.count) * 255.0)
    }
}
