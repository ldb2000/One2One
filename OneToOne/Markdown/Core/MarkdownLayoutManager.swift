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
        drawMermaidDiagrams(forGlyphRange: glyphsToShow, at: origin)
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

        drawTableControl(placement.addRow, symbol: .plus, iconColor: TableControlLayout.addIconColor, origin: origin)
        drawTableControl(placement.addColumn, symbol: .plus, iconColor: TableControlLayout.addIconColor, origin: origin)
        if let deleteRow = placement.deleteRow {
            drawTableControl(deleteRow, symbol: .minus, iconColor: TableControlLayout.deleteIconColor, origin: origin)
        }
        if let deleteColumn = placement.deleteColumn {
            drawTableControl(deleteColumn, symbol: .minus, iconColor: TableControlLayout.deleteIconColor, origin: origin)
        }
    }

    private enum TableControlSymbol {
        case plus
        case minus

        /// Nom SF Symbols — `"plus"`/`"minus"`, disponibles depuis macOS 11
        /// (déploiement de l'app : macOS 15, cf. `CLAUDE.md`).
        var systemSymbolName: String {
            switch self {
            case .plus: return "plus"
            case .minus: return "minus"
            }
        }
    }

    /// Une pastille de fond neutre (`TableControlLayout.
    /// controlBackgroundColor`, bordure fine `controlBorderColor` — le
    /// patron « bouton +/– » natif macOS, cf. Mail/Réglages Système/
    /// Trousseaux) surmontée d'une icône SF Symbols (`+`/`–`) teintée
    /// `iconColor` — remplace un premier essai (disque de couleur saturée,
    /// croix dessinée au trait) jugé peu soigné, voir la doc de tête de
    /// `TableControlLayout`. `rect` en coordonnées conteneur (voir
    /// `TableControlLayout.Placement`), décalé par `origin` comme
    /// `drawMarker`/`drawBlockquoteRule`.
    ///
    /// Teinte l'icône par le patron `.sourceAtop` (dessiner l'image
    /// « template », puis remplir son propre rectangle avec `iconColor` en
    /// mode `.sourceAtop` — ne colore que les pixels déjà opaques de
    /// l'icône) : `NSImage.isTemplate` seul ne suffit pas à forcer une
    /// couleur arbitraire au dessin direct, `.sourceAtop` est le patron
    /// standard AppKit pour teindre un glyphe SF Symbols hors `NSButton`/
    /// `NSImageView` (qui, eux, teignent via `contentTintColor`).
    private func drawTableControl(_ rect: NSRect, symbol: TableControlSymbol, iconColor: NSColor, origin: NSPoint) {
        let viewRect = rect.offsetBy(dx: origin.x, dy: origin.y)

        let background = NSBezierPath(ovalIn: viewRect.insetBy(dx: 0.5, dy: 0.5))
        TableControlLayout.controlBackgroundColor.setFill()
        background.fill()
        TableControlLayout.controlBorderColor.setStroke()
        background.lineWidth = TableControlLayout.controlBorderWidth
        background.stroke()

        guard let symbolImage = NSImage(
            systemSymbolName: symbol.systemSymbolName, accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: viewRect.width * 0.5, weight: .semibold))
        else { return }

        let tinted = NSImage(size: symbolImage.size, flipped: false) { imageRect in
            symbolImage.draw(in: imageRect)
            iconColor.set()
            imageRect.fill(using: .sourceAtop)
            return true
        }

        let iconSize = symbolImage.size
        let iconRect = NSRect(
            x: viewRect.midX - iconSize.width / 2,
            y: viewRect.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        tinted.draw(in: iconRect)
    }

    // MARK: - Diagrammes mermaid

    /// Peint chaque bloc mermaid (`.mdMermaidAttachment`, posé par
    /// `StyleRenderer.applyMermaidAttachment`) selon qu'il est **fermé**
    /// (diagramme peint par-dessus le texte source masqué, voir
    /// `drawMermaidDiagram`) ou **ouvert** (curseur dedans : gouttière de
    /// numéros de ligne + en-tête peints à côté du texte source normalement
    /// affiché, voir `drawMermaidLineNumber`/`drawMermaidHeader`) — l'état se
    /// lit sur la sélection courante, jamais sur un attribut stocké (même
    /// principe que `drawTableControls`). Un clic sur un bloc fermé (voir
    /// `EditorTextView.mermaidBlockRange(at:)`) l'ouvre en repositionnant le
    /// curseur dedans ; le bouton « Terminé » (`EditorTextView.
    /// mermaidDoneButtonRange(at:)`) ou un clic/une flèche qui en sort le
    /// referme — `EditorRepresentable.Coordinator.
    /// updateMermaidBlockGeometryIfNeeded` recalcule alors sa géométrie
    /// (hauteur de ligne) pour l'état qu'il vient de prendre, ce dessin ne
    /// fait que suivre l'état déjà posé.
    ///
    /// `drawnClosedBlockStarts` évite de repeindre le même diagramme fermé
    /// pour chacune de ses lignes visuelles masquées — `enumerateLineFragments`
    /// en visite une par ligne, mais un bloc de plusieurs lignes ne doit
    /// recevoir son diagramme qu'une fois (la gouttière/l'en-tête, eux,
    /// doivent au contraire se répéter par ligne/apparaître une fois en tête
    /// — gérés directement par condition, pas par un tel ensemble).
    private func drawMermaidDiagrams(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0,
              let textView = firstTextView, let container = textView.textContainer
        else { return }
        let ns = storage.string as NSString
        let selectedLocation = textView.selectedRange().location
        var drawnClosedBlockStarts = Set<Int>()

        enumerateLineFragments(forGlyphRange: glyphsToShow) { [weak self] lineRect, _, _, lineGlyphRange, _ in
            guard let self else { return }
            let charRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard charRange.location < ns.length else { return }

            guard let attachment = storage.attribute(.mdMermaidAttachment, at: charRange.location, effectiveRange: nil) as? NSTextAttachment,
                  let blockRange = MermaidBlockLayout.blockRange(in: storage, at: charRange.location)
            else { return }

            let isOpen = MermaidBlockLayout.selectionTouches(selectedLocation, blockRange: blockRange)
            if isOpen {
                let lineIndex = self.mermaidSourceLineIndex(forCharacterLocation: charRange.location, blockRange: blockRange, in: ns)
                self.drawMermaidLineNumber(lineIndex, lineFragmentRect: lineRect, origin: origin)
                if charRange.location == blockRange.location {
                    self.drawMermaidHeader(above: lineRect, origin: origin, containerWidth: container.size.width)
                }
                return
            }

            guard !drawnClosedBlockStarts.contains(blockRange.location) else { return }
            drawnClosedBlockStarts.insert(blockRange.location)
            self.drawMermaidDiagram(attachment, forBlockRange: blockRange, in: container, origin: origin)
        }
    }

    /// Peint le diagramme (ou le cadre de secours — chargement/erreur, voir
    /// `MermaidAttachmentFactory`) **à sa taille native** — jamais étiré pour
    /// remplir une zone réservée arbitraire (l'ancien défaut : un bloc de 2
    /// lignes de source réservait 220pt, l'image y était alors redimensionnée
    /// en « letterbox » dans cette zone bien plus grande qu'elle). La position
    /// vient de la **première ligne** du bloc (`lineFragmentRect`, dont la
    /// hauteur a été réservée exactement à `image.size.height + 2×inset` par
    /// `StyleRenderer.applyClosedMermaidGeometry`) — jamais de
    /// `boundingRect(forGlyphRange:)` sur tout le bloc : avec le texte source
    /// masqué (couleur `.clear`), un tel rect dégénérerait vers la largeur
    /// quasi nulle des glyphes invisibles, pas la largeur voulue du cadre.
    /// La largeur est plafonnée à ce qui reste disponible dans le conteneur
    /// (« la colonne de texte »), jamais au-delà.
    private func drawMermaidDiagram(
        _ attachment: NSTextAttachment,
        forBlockRange blockRange: NSRange,
        in container: NSTextContainer,
        origin: NSPoint
    ) {
        guard let image = attachment.image else { return }
        let glyphIndex = glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        let maxWidth = max(container.size.width - firstLineRect.minX, 0)
        let frameWidth = min(MermaidBlockLayout.closedFrameWidth(forAttachmentSize: image.size), maxWidth)
        let frameHeight = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: image.size)
        let frameRect = NSRect(x: firstLineRect.minX, y: firstLineRect.minY, width: frameWidth, height: frameHeight)
            .offsetBy(dx: origin.x, dy: origin.y)
        guard frameRect.width > 0, frameRect.height > 0 else { return }

        MermaidBlockLayout.backgroundColor.setFill()
        frameRect.fill()

        let imageRect = MermaidBlockLayout.centeredImageRect(for: image.size, in: frameRect)
        image.draw(in: imageRect)

        let border = NSBezierPath(rect: frameRect.insetBy(dx: 0.5, dy: 0.5))
        MermaidBlockLayout.borderColor.setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    // MARK: - Source mermaid ouvert (gouttière + en-tête)

    /// Index (0-based) de la ligne portant `location` au sein du bloc mermaid
    /// `blockRange` — compte les `\n` entre le début du bloc et `location`.
    /// Un bloc mermaid tient sur une poignée de lignes (source d'un
    /// diagramme, pas un fichier) : ce comptage linéaire par ligne visitée
    /// reste négligeable, même philosophie que `TableControlLayout.
    /// placementForCursor` (balayage local borné).
    private func mermaidSourceLineIndex(forCharacterLocation location: Int, blockRange: NSRange, in ns: NSString) -> Int {
        guard location > blockRange.location else { return 0 }
        var count = 0
        var index = blockRange.location
        while index < location {
            if ns.character(at: index) == 0x0A { count += 1 }
            index += 1
        }
        return count
    }

    private func drawMermaidLineNumber(_ index: Int, lineFragmentRect: NSRect, origin: NSPoint) {
        let text = "\(index + 1)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: MermaidSourceLayout.gutterFont,
            .foregroundColor: MermaidSourceLayout.gutterColor
        ]
        let size = text.size(withAttributes: attrs)
        let point = MermaidSourceLayout.lineNumberOrigin(lineRect: lineFragmentRect, numberSize: size)
        text.draw(at: NSPoint(x: point.x + origin.x, y: point.y + origin.y), withAttributes: attrs)
    }

    /// Bande d'en-tête discrète au-dessus de la première ligne d'un bloc
    /// mermaid ouvert — étiquette `mermaid` à gauche (après la gouttière),
    /// bouton « Terminé » à droite (hit-testé par `EditorTextView.
    /// mermaidDoneButtonRange(at:)`, même géométrie — `MermaidSourceLayout.
    /// doneButtonRect`, un seul calcul partagé).
    private func drawMermaidHeader(above lineFragmentRect: NSRect, origin: NSPoint, containerWidth: CGFloat) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: MermaidSourceLayout.headerLabelFont,
            .foregroundColor: MermaidSourceLayout.headerLabelColor
        ]
        let headerRect = MermaidSourceLayout.headerRect(above: lineFragmentRect, containerWidth: containerWidth)
        let labelText = "mermaid" as NSString
        let labelSize = labelText.size(withAttributes: labelAttrs)
        labelText.draw(
            at: NSPoint(
                x: origin.x + MermaidSourceLayout.gutterWidth,
                y: origin.y + headerRect.minY + (headerRect.height - labelSize.height) / 2
            ),
            withAttributes: labelAttrs
        )

        let buttonRect = MermaidSourceLayout.doneButtonRect(above: lineFragmentRect, containerWidth: containerWidth)
            .offsetBy(dx: origin.x, dy: origin.y)
        let pill = NSBezierPath(roundedRect: buttonRect, xRadius: buttonRect.height / 2, yRadius: buttonRect.height / 2)
        NSColor.controlBackgroundColor.setFill()
        pill.fill()
        NSColor.separatorColor.setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let buttonAttrs: [NSAttributedString.Key: Any] = [
            .font: MermaidSourceLayout.doneButtonFont,
            .foregroundColor: NSColor.labelColor
        ]
        let buttonText = "Terminé" as NSString
        let textSize = buttonText.size(withAttributes: buttonAttrs)
        buttonText.draw(
            at: NSPoint(x: buttonRect.midX - textSize.width / 2, y: buttonRect.midY - textSize.height / 2),
            withAttributes: buttonAttrs
        )
    }
}
