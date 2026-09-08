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

    // MARK: - Palette par mode (spec §7.1)

    /// La table des trois palettes. **Fonction pure**, et c'est tout le
    /// critère n° 2 du chantier 6 (« les trois modes sont accessibles en un
    /// clic et conservent chacun leur palette ») : la vue ne fait que la lire,
    /// le test l'assène colonne par colonne.
    ///
    /// Les trois épaisseurs de la barre d'outils (`Fin`, `Moyen`, `Épais`)
    /// sont communes aux trois modes — le « stylo (3 épaisseurs) » de la spec
    /// est donc **un** outil, pas trois.
    static func tools(for mode: BoardMode) -> [WhiteboardTool] {
        switch mode {
        case .sketch:
            return [.pencil, .rectangle, .ellipse, .arrow, .line, .text, .note, .image, .eraser]
        case .diagram:
            // Les formes viennent de la bibliothèque (`shapes(for:)`), en
            // dessous de ces quatre outils.
            return [.selection, .connector, .text, .eraser]
        case .ink:
            return [.pen, .highlighter, .eraser, .ruler, .lasso]
        }
    }

    /// L'outil armé à l'ouverture d'une planche de ce mode : le premier de sa
    /// palette. Un mode qui garderait l'outil du mode précédent proposerait un
    /// crayon dans une palette qui n'en a pas.
    static func defaultTool(for mode: BoardMode) -> WhiteboardTool {
        tools(for: mode).first ?? .pencil
    }

    /// Les formes de la bibliothèque offertes par le mode. Seul le Schéma en a
    /// (spec §7.1) ; les deux autres rendent une liste vide, et la vue ne
    /// dessine alors aucune séparation.
    static func shapes(for mode: BoardMode) -> [BoardShapeLibrary.Shape] {
        mode == .diagram ? BoardShapeLibrary.Shape.allCases : []
    }
}
