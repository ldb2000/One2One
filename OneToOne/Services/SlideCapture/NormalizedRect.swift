import CoreGraphics

/// Zone rectangulaire exprimée en fraction des dimensions de son support.
///
/// Stocker la zone en proportions et non en pixels est ce qui permet au cadrage de
/// survivre à un redimensionnement de la fenêtre source ou à un changement d'écran.
///
/// Convention : l'origine `(0, 0)` est en **haut à gauche**, comme les coordonnées
/// locales SwiftUI et comme `CGImage.cropping(to:)`.
struct NormalizedRect: Equatable, Sendable, Codable {

    let x: Double
    let y: Double
    let width: Double
    let height: Double

    /// La totalité du support.
    static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    /// Les valeurs sont ramenées dans `0…1` et la taille est réduite pour ne pas
    /// dépasser le bord : une zone invalide est impossible à construire.
    init(x: Double, y: Double, width: Double, height: Double) {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        self.x = clampedX
        self.y = clampedY
        self.width = min(max(width, 0), 1 - clampedX)
        self.height = min(max(height, 0), 1 - clampedY)
    }

    /// Zone décrite par un glissement entre deux points dans une vue de taille `size`.
    /// L'ordre des points est indifférent.
    init(from start: CGPoint, to end: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { self = .full; return }
        self.init(
            x: Double(min(start.x, end.x)) / Double(size.width),
            y: Double(min(start.y, end.y)) / Double(size.height),
            width: Double(abs(end.x - start.x)) / Double(size.width),
            height: Double(abs(end.y - start.y)) / Double(size.height)
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        self.init(x: x, y: y, width: width, height: height)
    }

    /// Vrai si la zone n'a pas de surface exploitable.
    var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Zone candidate produite par un glissement. Sous `minimumFraction` sur l'un des
    /// deux axes, un glissement accidentel ne doit pas rendre le cadrage inutilisable :
    /// `current` est renvoyée inchangée. Fonction pure, sans SwiftUI : testable sans geste.
    static func fromDrag(
        from start: CGPoint,
        to end: CGPoint,
        in size: CGSize,
        minimumFraction: Double = 0.05,
        current: NormalizedRect
    ) -> NormalizedRect {
        let candidate = NormalizedRect(from: start, to: end, in: size)
        guard candidate.width > minimumFraction, candidate.height > minimumFraction else {
            return current
        }
        return candidate
    }

    /// Rectangle d'affichage pour une vue de taille `size`, inverse de `init(from:to:in:)`.
    /// L'appelant passe la taille d'affichage réelle de l'image : aucun décalage aspect-fit.
    func displayRect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    /// Zone en pixels pour un support donné, arrondie sur la grille et bornée.
    func pixelRect(forWidth imageWidth: Int, height imageHeight: Int) -> CGRect {
        let rect = CGRect(
            x: (x * Double(imageWidth)).rounded(.down),
            y: (y * Double(imageHeight)).rounded(.down),
            width: (width * Double(imageWidth)).rounded(),
            height: (height * Double(imageHeight)).rounded()
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }

    /// Recadre l'image. `nil` si la zone est vide ou le crop impossible.
    func apply(to image: CGImage) -> CGImage? {
        guard !isEmpty else { return nil }
        let rect = pixelRect(forWidth: image.width, height: image.height)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return image.cropping(to: rect)
    }
}
