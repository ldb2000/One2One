import SwiftUI

/// Les cinq couleurs de la barre d'outils de l'atelier (spec §7.2 : « 5
/// couleurs (`ink/1`, action, report, ok, warn) — la couleur active porte un
/// anneau blanc + contour »).
///
/// Les couleurs viennent **des jetons**, jamais d'un littéral : la règle du
/// programme §7 est « jamais de nouvelle couleur hors `One2OneTokens` ». Le
/// moteur de planches attend une chaîne hexadécimale, qu'on dérive du jeton au
/// lieu de la recopier — `WorkshopPaletteTests` vérifie que les deux
/// coïncident.
enum WorkshopPalette {

    struct Entry: Identifiable, Equatable {
        var id: String { hex }
        /// Info-bulle française.
        var label: String
        var color: Color
        /// Hexadécimal passé à `window.oneToOneBoard.setColor`.
        var hex: String
    }

    /// Hexadécimal `#rrggbb` d'une couleur, en minuscules. Pur : passe par les
    /// composantes sRGB, comme `ContrastRatio`.
    static func hexString(_ color: Color) -> String {
        guard let c = ContrastRatio.components(color) else { return "#000000" }
        let r = Int((c.r * 255).rounded())
        let g = Int((c.g * 255).rounded())
        let b = Int((c.b * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Dans l'ordre de la capture : noir (actif par défaut), bleu, brique,
    /// vert, ambre.
    static let entries: [Entry] = [
        Entry(label: "Encre", color: One2OneToken.ink1, hex: hexString(One2OneToken.ink1)),
        Entry(label: "Action", color: One2OneToken.action, hex: hexString(One2OneToken.action)),
        Entry(label: "Rapport", color: One2OneToken.report, hex: hexString(One2OneToken.report)),
        Entry(label: "Tenu", color: One2OneToken.ok, hex: hexString(One2OneToken.ok)),
        Entry(label: "À surveiller", color: One2OneToken.warn, hex: hexString(One2OneToken.warn)),
    ]

    /// La couleur par défaut d'une planche neuve : l'encre.
    static var defaultHex: String { entries[0].hex }

    /// L'entrée correspondant à un hexadécimal, si elle existe.
    static func entry(forHex hex: String) -> Entry? {
        entries.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }
}
