import SwiftUI
import AppKit

/// Jetons de la fiche collaborateur v3, aux valeurs exactes de
/// `SPEC-Fiche-Collaborateur.md` (tour 5 du handoff).
///
/// **Clair et sombre.** La spec donne les deux valeurs ; il n'y a pas de
/// catalogue d'assets dans ce paquet SwiftPM, donc chaque jeton est une
/// couleur dynamique résolue à l'apparence.
///
/// ## Rapport avec `AppTheme`
///
/// `AppTheme.verbe` **est** le `link` de cette spec — même valeur `#0A6CFF`,
/// et son commentaire interdit de la dupliquer sous un autre nom. Elle est
/// donc reprise, pas redéfinie.
///
/// Trois jetons sont en revanche **proches sans être identiques** à ceux
/// d'`AppTheme`, parce que les deux palettes ont été lues sur des captures
/// différentes :
///
/// | ici | `AppTheme` | écart |
/// |---|---|---|
/// | `late` `#D9483F` | `urgenceForte` `#E5484D` | teinte plus sourde |
/// | `ok` `#3F9D6B` | `nominal` `#2E7D52` | plus clair |
/// | `ai` `#7A5CD6` | `accentManager` `#6E56CF` | plus saturé |
///
/// Elles coexistent tant que la fiche v3 et la vitrine Actions ne sont pas
/// passées sous la même palette. **Ne pas « corriger » l'une vers l'autre sans
/// arbitrage** : ce sont deux lectures de design, pas une erreur de saisie.
enum FicheTokens {

    // MARK: - Surfaces

    /// Fond de la fiche.
    static let bg       = dynamique(clair: 0xFFFFFF, sombre: 0x1B1A18)
    /// Colonne d'état, à droite.
    static let railBg   = dynamique(clair: 0xFAF8F4, sombre: 0x1E1D1B)
    /// Barre de titre.
    static let chromeBg = dynamique(clair: 0xEDEAE4, sombre: 0x232220)
    /// Fond d'une ligne de fil survolée.
    static let rowHover = dynamique(clair: 0xF6F4EF, sombre: 0x2E2C28)

    // MARK: - Traits

    /// Entre deux zones.
    static let divider  = dynamique(clair: 0xEBE8E2, sombre: 0x2E2C28)
    /// Entre deux lignes, et rail vertical des puces.
    static let hairline = dynamique(clair: 0xF1EEE9, sombre: 0x2A2825)
    /// Bordure d'un contrôle.
    static let stroke   = dynamique(clair: 0xDCD8D0, sombre: 0x38352F)

    // MARK: - Sémantique

    static let late = statique(0xD9483F)
    static let warn = statique(0xC9762F)
    static let ok   = statique(0x3F9D6B)
    static let ai   = statique(0x7A5CD6)
    /// Reprise d'`AppTheme.verbe` : même valeur, un seul nom.
    static let link = AppTheme.verbe

    // MARK: - Texte

    static let ink = dynamique(clair: 0x1D1D1F, sombre: 0xF0EDE7)
    /// Texte secondaire : 46 % d'encre.
    static let inkSecondary = ink.opacity(0.46)
    /// Texte tertiaire : 34 % d'encre.
    static let inkTertiary  = ink.opacity(0.34)

    // MARK: - Métriques

    /// Largeur **fixe** de la colonne d'état. Non redimensionnable : c'est
    /// elle qui répond à « où en est cette personne » quel que soit le défilement.
    static let railWidth: CGFloat = 296
    static let headerHeight: CGFloat = 71
    static let rowHeight: CGFloat = 42
    static let dateWidth: CGFloat = 46
    static let pillWidth: CGFloat = 56
    static let pillHeight: CGFloat = 18

    // MARK: - Fabrique

    private static func statique(_ rgb: Int) -> Color {
        Color(nsColor: nsColor(rgb))
    }

    private static func dynamique(clair: Int, sombre: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { apparence in
            apparence.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? nsColor(sombre) : nsColor(clair)
        })
    }

    private static func nsColor(_ rgb: Int) -> NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 0xFF) / 255,
                green:   Double((rgb >> 8) & 0xFF) / 255,
                blue:    Double(rgb & 0xFF) / 255,
                alpha: 1)
    }
}
