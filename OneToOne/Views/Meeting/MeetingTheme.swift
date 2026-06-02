import SwiftUI
import AppKit

/// Palette et typographies partagées des écrans de réunion (look « papier crème »).
enum MeetingTheme {
    /// Fond principal des écrans/zones (canvas).
    static let canvasCream  = Color(nsColor: NSColor(srgbRed: 0.976, green: 0.960, blue: 0.929, alpha: 1))
    /// Fond des surfaces secondaires (sidebar, cartes) — légèrement plus clair que le canvas.
    static let surfaceCream = Color(nsColor: NSColor(srgbRed: 0.988, green: 0.980, blue: 0.957, alpha: 1))
    /// Couleur d'accent (boutons d'action principaux, éléments interactifs mis en avant).
    static let accentOrange = Color(nsColor: NSColor(srgbRed: 0.776, green: 0.400, blue: 0.400, alpha: 1))
    /// Trait fin de séparation (bordures, dividers).
    static let hairline     = Color.secondary.opacity(0.18)
    /// Fond des badges/pills sombres (ex. pill d'enregistrement, lecture audio).
    static let badgeBlack   = Color(nsColor: NSColor(white: 0.10, alpha: 1))
    /// Ombre portée discrète pour les cartes en relief.
    static let softShadow   = Color.black.opacity(0.06)

    /// Titre principal serif (en-têtes de page).
    static let titleSerif   = Font.system(size: 34, weight: .semibold, design: .serif)
    /// Corps de texte serif (contenu éditorial, rapports).
    static let bodySerif    = Font.system(.body, design: .serif)
    /// Libellé de section en capitales (ex. « CAPTURE », « PANNEAUX »).
    static let sectionLabel = Font.caption2.weight(.bold)
    /// Métadonnées chiffrées alignées (durées, compteurs) — chasse fixe.
    static let meta         = Font.caption.monospacedDigit()
}
