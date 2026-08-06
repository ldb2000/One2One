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
/// list marker in the contents. It is NO by default.") est une propriété
/// **de classe** (pas d'instance, illisible sur un `NSTextList` particulier),
/// en lecture seule (pas un réglage activable depuis ce code), et mesurée
/// à `false` sur macOS 26.5 — la machine de développement de cette app,
/// dont le déploiement (macOS 15) est de toute façon antérieur à
/// l'introduction de cette propriété (macOS 26). `NSTextList` n'apporte donc
/// rien pour le dessin, et rien non plus pour représenter les deux états
/// d'une case à cocher (`markerFormat` n'est pas paramétré par un booléen
/// coché/décoché) : cette classe dessine donc directement, à partir de
/// `.mdListInfo` lu sur le storage.
///
/// Le marqueur est peint dans la marge que `StyleRenderer.applyVisualStyle`
/// réserve via `ListMarkerLayout.textIndent(for:)` — à gauche du texte de
/// l'item, jamais par-dessus.
final class MarkdownLayoutManager: NSLayoutManager {

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
        drawBlockquoteRules(forGlyphRange: glyphsToShow, at: origin)
        drawTableControls(at: origin)
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
            // Strict : `storage.attribute(at:)` exige `location < length`.
            // À l'égalité (fragment de ligne vide en toute fin de texte,
            // ex. juste après un `\n` final), lire l'attribut lèverait
            // `NSRangeException`.
            guard charRange.location < ns.length else { return }
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
        // Police et couleur fixes (`ListMarkerLayout.markerFont`/`markerColor`)
        // — pas celles du premier caractère de l'item : un item en gras/lien/
        // code inline ne doit pas changer l'apparence de son marqueur.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ListMarkerLayout.markerFont,
            .foregroundColor: ListMarkerLayout.markerColor
        ]

        let markerText = ListMarkerLayout.markerText(for: info) as NSString
        let markerSize = markerText.size(withAttributes: attributes)

        let paragraphStyle = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        let textIndent = paragraphStyle?.firstLineHeadIndent ?? ListMarkerLayout.textIndent(for: info)

        let markerX = origin.x + textIndent - ListMarkerLayout.markerTrailingGap - markerSize.width
        let markerY = origin.y + lineFragmentRect.minY + (lineFragmentRect.height - markerSize.height) / 2
        markerText.draw(at: NSPoint(x: markerX, y: markerY), withAttributes: attributes)
    }

    /// Parcourt les fragments de ligne du rendu en cours et peint le filet
    /// vertical d'une citation sur ceux qui appartiennent à un bloc
    /// `.mdBlockType == .blockquote` — lu au début du fragment, à l'instar de
    /// `drawListMarkers`, mais **sans** la restriction « premier fragment du
    /// paragraphe » : contrairement au marqueur de liste (posé une seule fois
    /// par item), le filet doit courir sur toute la hauteur du bloc, donc sur
    /// chaque ligne visuelle qui en fait partie — qu'elle soit un simple
    /// retour à la ligne automatique à l'intérieur d'un même paragraphe, ou
    /// la première ligne d'un paragraphe suivant à l'intérieur de la même
    /// citation (plusieurs paragraphes cités séparés par un `\n`, cf.
    /// `MarkdownParser.emitBlockQuote`, qui pose `.mdBlockType` sur toute la
    /// plage englobante). `enumerateLineFragments` renvoie des rects de ligne
    /// qui se succèdent verticalement sans intervalle (aucun
    /// `paragraphSpacing` n'est posé dans ce module — vérifié) : peindre le
    /// rect plein de chaque fragment produit donc un filet continu sur
    /// plusieurs lignes, pas des segments espacés.
    private func drawBlockquoteRules(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0 else { return }
        let ns = storage.string as NSString

        enumerateLineFragments(forGlyphRange: glyphsToShow) { lineRect, _, _, lineGlyphRange, _ in
            let charRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard charRange.location < ns.length else { return }
            guard storage.attribute(.mdBlockType, at: charRange.location, effectiveRange: nil) as? BlockType == .blockquote else {
                return
            }
            self.drawBlockquoteRule(forLineFragmentRect: lineRect, origin: origin)
        }
    }

    private func drawBlockquoteRule(forLineFragmentRect lineFragmentRect: NSRect, origin: NSPoint) {
        let ruleRect = NSRect(
            x: origin.x + BlockquoteRuleLayout.ruleLeadingGap,
            y: origin.y + lineFragmentRect.minY,
            width: BlockquoteRuleLayout.ruleThickness,
            height: lineFragmentRect.height
        )
        BlockquoteRuleLayout.ruleColor.setFill()
        ruleRect.fill()
    }

    // MARK: - Contrôles de tableau (curseur dans une cellule)

    /// Peint les contrôles de tableau (ajouter une ligne, ajouter une
    /// colonne, supprimer la ligne/la colonne courantes) quand le curseur
    /// est dans une cellule (`.mdTableCell` à `selectedRange().location`) —
    /// jamais au survol de la souris, voir la doc de tête de
    /// `TableControlLayout`. Même invariant que `drawListMarkers`/
    /// `drawBlockquoteRules` : lu depuis le storage/la sélection au moment du
    /// dessin, jamais écrit dedans.
    ///
    /// `firstTextView` — seule façon d'atteindre `selectedRange()` depuis un
    /// `NSLayoutManager`, qui n'a pas de notion de sélection propre. Un seul
    /// jeu de contrôles à la fois (celui de la cellule du curseur), donc pas
    /// besoin d'`enumerateLineFragments` comme les deux méthodes précédentes
    /// (peintes potentiellement pour chaque ligne du `glyphsToShow` reçu) :
    /// `TableControlLayout.placementForCursor` fait sa propre mesure via
    /// `boundingRect(forGlyphRange:in:)`, indépendante de la portion en cours
    /// de rafraîchissement — dessiner en dehors du rectangle actuellement
    /// redessiné est sans effet visible (AppKit borne le clip courant), pas
    /// une erreur.
    private func drawTableControls(at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0,
              let textView = firstTextView, let container = textView.textContainer
        else { return }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard location >= 0,
              let placement = TableControlLayout.placementForCursor(
                in: storage, at: location, layoutManager: self, container: container
              )
        else { return }

        drawTableControl(placement.addRow, color: TableControlLayout.addControlColor, symbol: .plus, origin: origin)
        drawTableControl(placement.addColumn, color: TableControlLayout.addControlColor, symbol: .plus, origin: origin)
        if let deleteRow = placement.deleteRow {
            drawTableControl(deleteRow, color: TableControlLayout.deleteControlColor, symbol: .cross, origin: origin)
        }
        if let deleteColumn = placement.deleteColumn {
            drawTableControl(deleteColumn, color: TableControlLayout.deleteControlColor, symbol: .cross, origin: origin)
        }
    }

    private enum TableControlSymbol { case plus, cross }

    /// Un disque de couleur (`color`) surmonté d'un symbole (`+`/`×`, tracé
    /// au trait plutôt qu'en glyphe de police — décor pur, aucune dépendance
    /// à une métrique de fonte). `rect` en coordonnées conteneur (voir
    /// `TableControlLayout.Placement`), décalé par `origin` comme
    /// `drawMarker`/`drawBlockquoteRule`.
    private func drawTableControl(_ rect: NSRect, color: NSColor, symbol: TableControlSymbol, origin: NSPoint) {
        let viewRect = rect.offsetBy(dx: origin.x, dy: origin.y)
        NSBezierPath(ovalIn: viewRect).fill(color: color)

        let symbolInset = viewRect.insetBy(dx: viewRect.width * 0.28, dy: viewRect.height * 0.28)
        let path = NSBezierPath()
        path.lineWidth = 1.4
        switch symbol {
        case .plus:
            path.move(to: NSPoint(x: symbolInset.midX, y: symbolInset.minY))
            path.line(to: NSPoint(x: symbolInset.midX, y: symbolInset.maxY))
            path.move(to: NSPoint(x: symbolInset.minX, y: symbolInset.midY))
            path.line(to: NSPoint(x: symbolInset.maxX, y: symbolInset.midY))
        case .cross:
            path.move(to: NSPoint(x: symbolInset.minX, y: symbolInset.minY))
            path.line(to: NSPoint(x: symbolInset.maxX, y: symbolInset.maxY))
            path.move(to: NSPoint(x: symbolInset.minX, y: symbolInset.maxY))
            path.line(to: NSPoint(x: symbolInset.maxX, y: symbolInset.minY))
        }
        TableControlLayout.symbolColor.setStroke()
        path.stroke()
    }
}

private extension NSBezierPath {
    /// Remplit ce chemin avec `color` — évite `color.setFill(); self.fill()`
    /// répété à chaque contrôle dans `drawTableControl`.
    func fill(color: NSColor) {
        color.setFill()
        fill()
    }
}
