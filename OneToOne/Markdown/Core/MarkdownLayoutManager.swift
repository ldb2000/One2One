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

    /// Plage du bloc **actuellement survolé** par la souris — mis à jour par
    /// `EditorTextView.mouseMoved` (via un `NSTrackingArea`), consommé ici pour
    /// peindre la gouttière (`⠿`/`+`) et un léger fond de survol sur ce bloc.
    /// `nil` : rien de survolé (souris hors éditeur, ou sur un bloc mermaid
    /// fermé/ouvert dont la géométrie propre remplace la gouttière — cas non
    /// implémenté ici, à voir step 4).
    var hoveredBlockRange: NSRange?

    /// Plage du bloc **sélectionné comme objet** (clic sur `⠿`) — dessiné avec
    /// un cadre `1.5 px #0a6cff` + fond `#f4f8ff`. Distinct du curseur texte
    /// dans le contenu (cf. spec Screen 4 « Distinction critique »).
    /// `nil` : pas de sélection de bloc active.
    var selectedBlockRange: NSRange?

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Fond de sélection/survol : AVANT super, pour que les glyphes se
        // superposent au calque de couleur.
        drawBlockSelectionBackground(at: origin)
        drawBlockHoverBackground(at: origin)
        drawOpenMermaidBackgrounds(forGlyphRange: glyphsToShow, at: origin)

        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
        drawBlockquoteRules(forGlyphRange: glyphsToShow, at: origin)

        drawTablePlaceholders(forGlyphRange: glyphsToShow, at: origin)
        drawMermaidDiagrams(forGlyphRange: glyphsToShow, at: origin)

        // Cadre de sélection : APRÈS super, pour rester au-dessus du contenu.
        // Les icônes de gouttière (⠿/+) sont peintes par `EditorTextView.draw`
        // et pas ici : `NSLayoutManager.drawGlyphs` est clippé au rect du
        // `NSTextContainer` (x ≥ textContainerOrigin.x), donc dessiner à
        // x < 58 (dans la gouttière réservée par `textContainerInset`) est
        // silencieusement ignoré. La bordure de sélection, elle, dépasse
        // seulement de quelques pixels (bodyPadding) et reste rendue.
        drawBlockSelectionBorder(at: origin)
    }

    // MARK: - Gouttière de bloc + sélection (step 1 handoff `editeur_blocs`)

    /// Rect englobant du corps du bloc `range` en coordonnées **vue**
    /// (`containerRect` + `origin`, où `origin` est déjà le
    /// `textContainerOrigin` de la vue courante). Retourne `nil` si la plage
    /// est vide ou si le container n'est pas disponible.
    func viewBodyRect(for range: NSRange, origin: NSPoint) -> NSRect? {
        guard let container = firstTextView?.textContainer,
              let container2 = textContainers.first,
              let rect = BlockGutterLayout.containerRect(
                for: range,
                layoutManager: self,
                container: container2
              ) ?? BlockGutterLayout.containerRect(
                for: range,
                layoutManager: self,
                container: container
              )
        else { return nil }
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    private func drawBlockSelectionBackground(at origin: NSPoint) {
        guard let range = selectedBlockRange,
              let bodyRect = viewBodyRect(for: range, origin: origin)
        else { return }
        let frame = BlockGutterLayout.selectionFrame(forBodyRect: bodyRect)
        let path = NSBezierPath(roundedRect: frame,
                                xRadius: BlockGutterLayout.bodyCornerRadius,
                                yRadius: BlockGutterLayout.bodyCornerRadius)
        BlockGutterLayout.selectionFillColor.setFill()
        path.fill()
    }

    private func drawBlockHoverBackground(at origin: NSPoint) {
        // Pas de survol si le bloc est déjà sélectionné (feedback sélection prime).
        guard let range = hoveredBlockRange, range != selectedBlockRange,
              let bodyRect = viewBodyRect(for: range, origin: origin)
        else { return }
        let frame = BlockGutterLayout.selectionFrame(forBodyRect: bodyRect)
        let path = NSBezierPath(roundedRect: frame,
                                xRadius: BlockGutterLayout.bodyCornerRadius,
                                yRadius: BlockGutterLayout.bodyCornerRadius)
        BlockGutterLayout.hoverFillColor.setFill()
        path.fill()
    }

    private func drawBlockSelectionBorder(at origin: NSPoint) {
        guard let range = selectedBlockRange,
              let bodyRect = viewBodyRect(for: range, origin: origin)
        else { return }
        let frame = BlockGutterLayout.selectionFrame(forBodyRect: bodyRect)
        let path = NSBezierPath(roundedRect: frame,
                                xRadius: BlockGutterLayout.bodyCornerRadius,
                                yRadius: BlockGutterLayout.bodyCornerRadius)
        BlockGutterLayout.accentColor.setStroke()
        path.lineWidth = BlockGutterLayout.selectionBorderWidth
        path.stroke()
    }

    /// Rect du corps du bloc `range` en coordonnées **vue**, exposé pour
    /// `EditorTextView.draw` qui peint les icônes de gouttière hors du
    /// container (zone clippée par `NSLayoutManager.drawGlyphs`). Reproduit
    /// exactement le calcul utilisé par les draw internes de cette classe
    /// (`drawBlockSelectionBackground`, etc.) — un seul chemin de géométrie.
    func viewBodyRect(for range: NSRange) -> NSRect? {
        guard let textView = firstTextView else { return nil }
        let origin = textView.textContainerOrigin
        return viewBodyRect(for: range, origin: origin)
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
    /// Peint les placeholders "Colonne 1", "Colonne 2" etc. dans les cellules
    /// d'en-tête vides.
    private func drawTablePlaceholders(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0 else { return }
        let ns = storage.string as NSString

        enumerateLineFragments(forGlyphRange: glyphsToShow) { [weak self] lineRect, _, _, lineGlyphRange, _ in
            guard let self else { return }
            let charRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard charRange.location < ns.length else { return }

            guard let info = storage.attribute(.mdTableCell, at: charRange.location, effectiveRange: nil) as? TableCellInfo,
                  info.row == 0 else { return }

            // Une cellule est vide si elle ne contient que son caractère \n de fin
            let cellLineRange = ns.lineRange(for: NSRange(location: charRange.location, length: 0))
            guard cellLineRange.length == 1, ns.character(at: cellLineRange.location) == 0x0A else { return }

            let placeholderText = "Colonne \(info.column + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.3)
            ]
            let size = placeholderText.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: origin.x + lineRect.minX,
                y: origin.y + lineRect.minY + (lineRect.height - size.height) / 2
            )
            placeholderText.draw(at: drawPoint, withAttributes: attrs)
        }
    }



    // MARK: - Diagrammes mermaid

    private func drawOpenMermaidBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0,
              let textView = firstTextView, let container = textView.textContainer,
              storage.length > 0
        else { return }

        let visibleCharacters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let selectedLocation = textView.selectedRange().location
        var drawnStarts = Set<Int>()

        storage.enumerateAttribute(.mdMermaidAttachment, in: visibleCharacters) { value, range, _ in
            guard value != nil,
                  let blockRange = MermaidBlockLayout.blockRange(in: storage, at: range.location),
                  MermaidBlockLayout.selectionTouches(selectedLocation, blockRange: blockRange),
                  drawnStarts.insert(blockRange.location).inserted
            else { return }

            let firstGlyph = self.glyphIndexForCharacter(at: blockRange.location)
            let lastCharacter = max(blockRange.location, NSMaxRange(blockRange) - 1)
            let lastGlyph = self.glyphIndexForCharacter(at: lastCharacter)
            let firstLine = self.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let lastLine = self.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let frame = MermaidSourceLayout.frameRect(
                firstLineRect: firstLine,
                lastLineRect: lastLine,
                containerWidth: container.size.width,
                previewHeight: 0
            ).offsetBy(dx: origin.x, dy: origin.y)
            let header = MermaidSourceLayout.headerRect(
                above: firstLine,
                containerWidth: container.size.width,
                previewHeight: 0
            ).offsetBy(dx: origin.x, dy: origin.y)
            let body = MermaidSourceLayout.bodyRect(
                firstLineRect: firstLine,
                lastLineRect: lastLine,
                containerWidth: container.size.width,
                previewHeight: 0
            ).offsetBy(dx: origin.x, dy: origin.y)

            let card = NSBezierPath(
                roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                xRadius: MermaidSourceLayout.cornerRadius,
                yRadius: MermaidSourceLayout.cornerRadius
            )
            MermaidSourceLayout.frameBackgroundColor.setFill()
            card.fill()

            NSGraphicsContext.current?.saveGraphicsState()
            card.addClip()
            MermaidSourceLayout.headerBackgroundColor.setFill()
            header.fill()
            MermaidSourceLayout.gutterBackgroundColor.setFill()
            NSRect(x: body.minX, y: body.minY, width: MermaidSourceLayout.gutterWidth, height: body.height).fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            MermaidSourceLayout.dividerColor.setFill()
            NSRect(x: header.minX, y: header.maxY - 1, width: header.width, height: 1).fill()
            NSRect(x: body.minX + MermaidSourceLayout.gutterWidth, y: body.minY, width: 1, height: body.height).fill()

            MermaidSourceLayout.borderColor.setStroke()
            card.lineWidth = MermaidSourceLayout.borderWidth
            card.stroke()
        }
    }

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
    /// en « letterbox » dans cette zone bien plus grande qu'elle). L'image
    /// porte déjà son propre cadre (fond + liseré composés dans les pixels
    /// par `MermaidAttachmentFactory`) : aucun fond ni liseré n'est repeint
    /// ici, jamais un double cadre.
    ///
    /// La position vient de la **première ligne** du bloc (`lineFragmentRect`,
    /// dont la hauteur a été réservée exactement à `image.size.height` par
    /// `StyleRenderer.applyClosedMermaidGeometry`) — jamais de
    /// `boundingRect(forGlyphRange:)` sur tout le bloc : avec le texte source
    /// masqué (couleur `.clear`), un tel rect dégénérerait vers la largeur
    /// quasi nulle des glyphes invisibles, pas la largeur voulue du cadre.
    /// La largeur est réduite (`MermaidBlockLayout.fittedSize`, jamais
    /// agrandie) si le conteneur est plus étroit que ce que
    /// `MermaidAttachmentFactory` a pu anticiper (« la colonne de texte »).
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
        let drawSize = MermaidBlockLayout.fittedSize(for: image.size, maxWidth: maxWidth)
        guard drawSize.width > 0, drawSize.height > 0 else { return }

        let rect = NSRect(x: firstLineRect.minX, y: firstLineRect.minY, width: drawSize.width, height: drawSize.height)
            .offsetBy(dx: origin.x, dy: origin.y)
        image.draw(in: rect)

        if blockRange == hoveredBlockRange {
            drawMermaidActionBar(in: rect)
        }
    }

    private func drawMermaidActionBar(in drawnRect: NSRect) {
        let geo = MermaidBlockLayout.actionBarGeometry(forDrawnRect: drawnRect)

        let path = NSBezierPath(roundedRect: geo.barRect, xRadius: MermaidBlockLayout.actionBarCornerRadius, yRadius: MermaidBlockLayout.actionBarCornerRadius)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.07)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3

        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        MermaidBlockLayout.actionBarBackgroundColor.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        MermaidBlockLayout.actionBarBorderColor.setStroke()
        path.lineWidth = MermaidBlockLayout.actionBarBorderWidth
        path.stroke()

        let editAttrs: [NSAttributedString.Key: Any] = [
            .font: MermaidBlockLayout.actionButtonFont,
            .foregroundColor: MermaidBlockLayout.actionButtonTextColor
        ]
        let editLabel = MermaidBlockLayout.editButtonLabel as NSString
        let editSize = editLabel.size(withAttributes: editAttrs)
        let editOrigin = NSPoint(
            x: geo.editButtonRect.minX + (geo.editButtonRect.width - editSize.width) / 2,
            y: geo.editButtonRect.minY + (geo.editButtonRect.height - editSize.height) / 2
        )
        editLabel.draw(at: editOrigin, withAttributes: editAttrs)

        MermaidBlockLayout.separatorColor.setFill()
        geo.separatorRect.fill()

        let duplicateAttrs: [NSAttributedString.Key: Any] = [
            .font: MermaidBlockLayout.actionButtonFont,
            .foregroundColor: MermaidBlockLayout.actionButtonTextColor
        ]
        let duplicateLabel = "Dupliquer" as NSString
        let duplicateSize = duplicateLabel.size(withAttributes: duplicateAttrs)
        duplicateLabel.draw(
            at: NSPoint(
                x: geo.copyButtonRect.minX + (geo.copyButtonRect.width - duplicateSize.width) / 2,
                y: geo.copyButtonRect.minY + (geo.copyButtonRect.height - duplicateSize.height) / 2
            ),
            withAttributes: duplicateAttrs
        )
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
        let sourceLineRect = MermaidSourceLayout.sourceLineRect(for: index, lineFragmentRect: lineFragmentRect)
        let point = MermaidSourceLayout.lineNumberOrigin(lineRect: sourceLineRect, numberSize: size)
        text.draw(at: NSPoint(x: point.x + origin.x, y: point.y + origin.y), withAttributes: attrs)
    }

    /// Bande d'en-tête discrète au-dessus de la première ligne d'un bloc
    /// mermaid ouvert — étiquette `mermaid` à gauche (après la gouttière),
    /// bouton « Terminé » à droite (hit-testé par `EditorTextView.
    /// mermaidDoneButtonRange(at:)`, même géométrie — `MermaidSourceLayout.
    /// doneButtonRect`, un seul calcul partagé).
    private func drawMermaidHeader(above lineFragmentRect: NSRect, origin: NSPoint, containerWidth: CGFloat) {
        // `drawGlyphs(forGlyphRange:)` peut fournir un clip limité à la ligne
        // courante. L'en-tête est volontairement au-dessus de la première
        // ligne : sans élargir temporairement le clip au conteneur, l'en-tête
        // du bloc Mermaid suivant est peint hors clip et disparaît derrière
        // le cadre du bloc précédent.
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }
        let clipHeight = firstTextView?.bounds.height ?? containerWidth
        NSBezierPath(
            rect: NSRect(x: origin.x, y: 0, width: containerWidth, height: clipHeight)
        ).addClip()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: MermaidSourceLayout.headerLabelFont,
            .foregroundColor: MermaidSourceLayout.headerLabelColor
        ]
        let headerRect = MermaidSourceLayout.headerRect(above: lineFragmentRect, containerWidth: containerWidth, previewHeight: 0)
        let labelText = "mermaid" as NSString
        let labelSize = labelText.size(withAttributes: labelAttrs)
        labelText.draw(
            at: NSPoint(
                x: origin.x + 12,
                y: origin.y + headerRect.minY + (headerRect.height - labelSize.height) / 2
            ),
            withAttributes: labelAttrs
        )

        let buttonRect = MermaidSourceLayout.doneButtonRect(above: lineFragmentRect, containerWidth: containerWidth, previewHeight: 0)
            .offsetBy(dx: origin.x, dy: origin.y)
        let pill = NSBezierPath(roundedRect: buttonRect, xRadius: 5, yRadius: 5)
        NSColor.textBackgroundColor.setFill()
        pill.fill()
        MermaidSourceLayout.borderColor.setStroke()
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
