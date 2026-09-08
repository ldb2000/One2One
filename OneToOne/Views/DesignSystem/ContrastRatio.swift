import AppKit
import SwiftUI

/// Ratio de contraste WCAG 2.1 entre deux couleurs.
///
/// Fonctions **pures** : elles ne dépendent que des composantes sRGB de la
/// couleur, pas d'une session graphique. La conversion passe par `NSColor`
/// parce que `Color` ne publie pas ses composantes ; `usingColorSpace(.sRGB)`
/// suffit et ne touche pas au serveur de fenêtres.
///
/// Sert au test de contraste des jetons (spec §1.2 : « tout texte sous 12 px
/// doit atteindre 4,5:1 »). Rendre `nil` plutôt que 1 ou 21 sur une couleur
/// inconvertible est volontaire : un test doit échouer bruyamment, pas mesurer
/// un contraste imaginaire.
enum ContrastRatio {

    /// Composantes sRGB de la couleur, normalisées 0…1, ou `nil` si la couleur
    /// n'est pas convertible en sRGB (couleur dynamique, motif…).
    static func components(_ color: Color) -> (r: Double, g: Double, b: Double)? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
    }

    /// Linéarisation d'une composante sRGB (WCAG 2.1, formule de la luminance
    /// relative).
    static func linearized(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// Luminance relative 0…1.
    static func relativeLuminance(_ color: Color) -> Double? {
        guard let c = components(color) else { return nil }
        return 0.2126 * linearized(c.r) + 0.7152 * linearized(c.g) + 0.0722 * linearized(c.b)
    }

    /// Ratio de contraste, toujours ≥ 1 quel que soit l'ordre des arguments.
    static func ratio(_ a: Color, _ b: Color) -> Double? {
        guard let la = relativeLuminance(a), let lb = relativeLuminance(b) else { return nil }
        let lighter = max(la, lb), darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
