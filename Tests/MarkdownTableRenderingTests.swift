import AppKit
import XCTest
@testable import OneToOne

/// Vérifie le rendu réel d'un tableau GFM sur la pile TextKit 1 complète du
/// projet (`MarkdownParser.parse` → `StyleRenderer.applyVisualStyle` →
/// `NSTextStorage` → `MarkdownLayoutManager` → `NSTextContainer`, exactement
/// la pile montée par `EditorRepresentable.makeNSView`), pas seulement le
/// mécanisme `NSTextTable`/`NSTextTableBlock` isolé.
///
/// Étape zéro de ce chantier (mesure préalable à toute conception, cf. le
/// plan) : `NSTextTable` peint-il quoi que ce soit sur cette pile montée à
/// la main ? Vérifié hors écran, apparence forcée en `.aqua` — sinon les
/// couleurs dynamiques (`TableLayout.borderColor` = `.separatorColor`,
/// `.headerBackgroundColor` dérivé de `.quaternaryLabelColor`) passent
/// blanc sur blanc et tout se mesure à zéro, piège documenté par
/// `renderToOffscreenBitmap` dans `StyleRendererTests`. Résultat mesuré :
/// une grille 2×2 minimale peint ~2000 pixels non-blancs sur 20 000 (bordure
/// + glyphes), avec une ligne verticale continue à la frontière de colonne
/// — une vraie grille, pas des artefacts épars. Contraste avec
/// `NSTextList` (mécanisme équivalent pour les listes) : mesuré ne rien
/// peindre du tout sur cette même pile, d'où `MarkdownLayoutManager`, qui
/// dessine les marqueurs de liste à la main. `NSTextTable` n'a pas ce
/// défaut : aucun dessin manuel de bordure n'est nécessaire ici,
/// `NSLayoutManager.drawBackground(forGlyphRange:at:)` (hérité tel quel,
/// `MarkdownLayoutManager` ne le redéfinit pas) peint déjà tout.
final class MarkdownTableRenderingTests: XCTestCase {

    // MARK: - Bordures réellement peintes

    func test_table_bordersArePaintedOnTheRealPipeline() throws {
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        let bitmap = try renderToOffscreenBitmap(storage: storage, width: 240, height: 120)

        var nonWhitePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.redComponent < 0.98 || color.greenComponent < 0.98 || color.blueComponent < 0.98 {
                    nonWhitePixels += 1
                }
            }
        }
        XCTAssertGreaterThan(nonWhitePixels, 0, "le tableau ne peint rien sur la pile TextKit 1 réelle du projet")
    }

    /// Distingue une vraie grille de quelques pixels épars (glyphes de
    /// texte, artefacts d'antialiasing) : une ligne verticale continue doit
    /// courir sur une bonne partie de la hauteur du tableau à la frontière
    /// entre les deux colonnes.
    func test_table_hasAContinuousVerticalBorderAtTheColumnBoundary() throws {
        let markdown = "| Colonne gauche | Colonne droite |\n|---|---|\n| un | deux |\n| trois | quatre |"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        let bitmap = try renderToOffscreenBitmap(storage: storage, width: 400, height: 160)

        func isNonWhite(_ x: Int, _ y: Int) -> Bool {
            guard let color = bitmap.colorAt(x: x, y: y) else { return false }
            return color.redComponent < 0.98 || color.greenComponent < 0.98 || color.blueComponent < 0.98
        }

        var bestRun = 0
        for x in 0..<bitmap.pixelsWide {
            var runLength = 0
            var maxRun = 0
            for y in 0..<bitmap.pixelsHigh {
                if isNonWhite(x, y) {
                    runLength += 1
                    maxRun = max(maxRun, runLength)
                } else {
                    runLength = 0
                }
            }
            bestRun = max(bestRun, maxRun)
        }
        // Trois rangées (en-tête + 2 corps) : une vraie bordure verticale
        // traverse les trois, largement plus haut qu'un simple glyphe.
        XCTAssertGreaterThan(bestRun, 40, "aucune ligne verticale continue trouvée — pas une vraie grille")
    }

    // MARK: - Bon nombre de cellules

    func test_table_hasCorrectCellCount_threeByThree() {
        let markdown = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        | 4 | 5 | 6 |
        """
        let storage = MarkdownParser.parse(markdown)
        var cells: Set<String> = []
        var tableIDs: Set<UUID> = []
        storage.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            cells.insert("\(info.row),\(info.column)")
            tableIDs.insert(info.tableID)
        }
        XCTAssertEqual(tableIDs.count, 1, "un seul tableau logique")
        // 3 colonnes × (1 en-tête + 2 rangées de corps) = 9 cellules.
        XCTAssertEqual(cells.count, 9, "3 colonnes × 3 rangées (en-tête incluse) doit donner 9 cellules")
        for row in 0...2 {
            for column in 0...2 {
                XCTAssertTrue(cells.contains("\(row),\(column)"), "cellule (\(row), \(column)) manquante")
            }
        }
    }

    /// Le nombre de `NSTextTableBlock` réellement construits par
    /// `StyleRenderer` — pas seulement `.mdTableCell` côté parser — doit
    /// correspondre, et **tous** doivent pointer vers la **même**
    /// `NSTextTable` (cf. `tableInstances` dans `StyleRenderer.
    /// applyVisualStyle`) : sinon la grille se disloquerait visuellement
    /// (colonnes non alignées entre rangées), même si chaque cellule prise
    /// isolément a une bordure correcte.
    func test_table_allCellsShareTheSameNSTextTableInstance() throws {
        // En-tête + 2 rangées de corps = 3 rangées, × 2 colonnes = 6 cellules
        // (la ligne `|---|---|` est la séparation d'alignement, pas une
        // rangée de données).
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        var tables: [ObjectIdentifier] = []
        var blockCount = 0
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            blockCount += 1
            tables.append(ObjectIdentifier(block.table))
        }
        XCTAssertEqual(blockCount, 6, "3 rangées (en-tête + 2 de corps) × 2 colonnes = 6 cellules, donc 6 NSTextTableBlock")
        XCTAssertEqual(Set(tables).count, 1, "toutes les cellules doivent partager la même NSTextTable")
    }

    /// Un rafraîchissement **partiel** (une seule ligne éditée, cas réel
    /// d'une frappe dans une cellule) doit, lui aussi, reconstruire tout le
    /// tableau avec une `NSTextTable` partagée — pas seulement le
    /// rafraîchissement complet ci-dessus. Reproduit le chemin exact
    /// qu'exerce `EditorRepresentable.Coordinator.textDidChange`
    /// (`applyVisualStyle(to:affectedRange:)` avec un `affectedRange` réduit
    /// à la frappe).
    func test_table_partialRestyleOfOneCell_keepsTheSharedTableInstance() throws {
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        // Simule une frappe dans la dernière cellule ("4") : édite un seul
        // caractère puis ne restyle que cette position, comme le fait
        // `Coordinator.textDidChange` avec `pendingStyleRange`.
        let ns = storage.string as NSString
        let fourLocation = ns.range(of: "4").location
        storage.replaceCharacters(in: NSRange(location: fourLocation, length: 1), with: "9")
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: NSRange(location: fourLocation, length: 1))

        var tables: [ObjectIdentifier] = []
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            tables.append(ObjectIdentifier(block.table))
        }
        XCTAssertEqual(Set(tables).count, 1,
                       "un rafraîchissement partiel d'une seule cellule doit quand même reconstruire tout le tableau avec une NSTextTable partagée")
    }

    // MARK: - Helper (copie de StyleRendererTests.renderToOffscreenBitmap)

    private func renderToOffscreenBitmap(storage: NSTextStorage, width: Int, height: Int) throws -> NSBitmapImageRep {
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat(width), height: CGFloat(height)))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))

        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
            let glyphRange = layoutManager.glyphRange(for: container)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
