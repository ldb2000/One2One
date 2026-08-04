import AppKit

/// `NSLayoutManager` qui dessine, en plus du rendu standard, le marqueur
/// (puce, numéro, case à cocher) des items de liste — sans jamais l'écrire
/// dans le `textStorage`.
///
/// TextKit 1 ne dessine **pas** automatiquement les marqueurs d'un
/// `NSParagraphStyle.textLists` : vérifié empiriquement (rendu hors écran
/// dans un bitmap, `paragraphStyle.textLists` posé sans effet visible dans la
/// marge sur cette même pile storage→layoutManager→container montée à la
/// main) et confirmé par la documentation de la plateforme —
/// `NSTextList.includesTextListMarkers` ("When YES, TextKit includes text
/// list marker in the contents. It is NO by default.") n'existe que depuis
/// macOS 26, hors du déploiement macOS 15 de cette app, et est de toute
/// façon en lecture seule (pas un réglage activable ici). `NSTextList`
/// n'apporte donc rien pour le dessin, et rien non plus pour représenter les
/// deux états d'une case à cocher (`markerFormat` n'est pas paramétré par un
/// booléen coché/décoché) : cette classe dessine donc directement, à partir
/// de `.mdListInfo` lu sur le storage.
///
/// Le marqueur est peint dans la marge que `StyleRenderer.applyVisualStyle`
/// réserve via `ListMarkerLayout.textIndent(for:)` — à gauche du texte de
/// l'item, jamais par-dessus.
final class MarkdownLayoutManager: NSLayoutManager {

    /// Espace, en points, laissé entre le marqueur et le début du texte.
    private static let markerTrailingGap: CGFloat = 4

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Parcourt les fragments de ligne du rendu en cours et dessine un
    /// marqueur pour ceux qui commencent un item de liste — reconnus en
    /// comparant le début du fragment au début de son paragraphe : un item
    /// qui a débordé sur plusieurs lignes visuelles ne reçoit un marqueur que
    /// sur la première, les lignes de repli s'alignant sur `headIndent` sans
    /// marqueur, exactement comme un retrait de liste classique.
    private func drawListMarkers(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0 else { return }
        let ns = storage.string as NSString

        enumerateLineFragments(forGlyphRange: glyphsToShow) { [weak self] lineRect, _, _, lineGlyphRange, _ in
            guard let self else { return }
            let charRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard charRange.location <= ns.length else { return }
            let isParagraphStart = charRange.location == 0
                || ns.character(at: charRange.location - 1) == 0x0A
            guard isParagraphStart else { return }
            guard let info = storage.attribute(.mdListInfo, at: charRange.location, effectiveRange: nil) as? ListInfo else {
                return
            }

            self.drawMarker(for: info, at: charRange.location, in: storage, lineFragmentRect: lineRect, origin: origin)
        }
    }

    private func drawMarker(
        for info: ListInfo,
        at location: Int,
        in storage: NSTextStorage,
        lineFragmentRect: NSRect,
        origin: NSPoint
    ) {
        let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: StyleRenderer.baseFontSize)
        let color = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            ?? NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        let markerText = ListMarkerLayout.markerText(for: info) as NSString
        let markerSize = markerText.size(withAttributes: attributes)

        let paragraphStyle = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        let textIndent = paragraphStyle?.firstLineHeadIndent ?? ListMarkerLayout.textIndent(for: info.level)

        let markerX = origin.x + textIndent - Self.markerTrailingGap - markerSize.width
        let markerY = origin.y + lineFragmentRect.minY + (lineFragmentRect.height - markerSize.height) / 2
        markerText.draw(at: NSPoint(x: markerX, y: markerY), withAttributes: attributes)
    }
}
