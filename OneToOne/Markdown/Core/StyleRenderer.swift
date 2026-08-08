import AppKit

/// Translates custom markdown attributes (`mdBold`, `mdBlockType`, etc.) into
/// AppKit display attributes. The storage string stays marker-free while the
/// serializer keeps persisting markdown syntax.
enum StyleRenderer {
    static let baseFontSize: CGFloat = 13

    static func applyVisualStyle(to storage: NSTextStorage) {
        applyVisualStyle(to: storage, affectedRange: nil)
    }

    static func applyVisualStyle(to storage: NSTextStorage, affectedRange: NSRange?) {
        guard storage.length > 0 else { return }

        let renderRange = normalizedRenderRange(affectedRange, in: storage)
        // Un bloc mermaid ne peut être « ouvert » (source affiché en
        // édition) qu'à l'occasion d'un restylage **ciblé** — une frappe
        // (`affectedRange` = la plage éditée) ou un déplacement de sélection
        // qui touche/quitte le bloc (voir `EditorRepresentable.Coordinator.
        // updateMermaidBlockGeometryIfNeeded`). Un restylage du document
        // **entier** (`affectedRange == nil` : chargement initial, rechargement
        // externe) ignore volontairement la sélection courante et referme
        // toujours le bloc : `NSTextStorage.setAttributedString` déplace le
        // curseur en fin de document *avant* que `applyVisualStyle` ne
        // s'exécute (effet de bord AppKit non notifié au délégué, voir
        // `Tests/EditorTextViewMermaidClickTests.swift`) — sans cette garde,
        // un document se terminant par un bloc mermaid s'ouvrirait par
        // erreur à chaque chargement.
        let allowsOpenMermaidBlock = affectedRange != nil
        // Position du curseur, lue **une seule fois** ici et transmise aux
        // deux endroits qui décident de l'état ouvert/fermé d'un bloc
        // mermaid : `applyMermaidAttachment` (quelle géométrie poser) et
        // `applyBlockSpacing` (le bloc ouvert porte un padding interne en bas,
        // auquel l'écart inter-blocs doit s'ajouter). Deux lectures
        // indépendantes pourraient diverger — la carte se fermerait d'un côté
        // et pas de l'autre. `nil` quand aucun bloc ne peut être ouvert
        // (restylage du document entier, voir ci-dessus).
        //
        // `MainActor.assumeIsolated` : `applyVisualStyle` n'est jamais appelée
        // que depuis le fil d'édition AppKit (même justification que dans
        // `applyMermaidAttachment`).
        let openMermaidSelection: Int? = allowsOpenMermaidBlock
            ? MainActor.assumeIsolated {
                storage.layoutManagers.first?.firstTextView?.selectedRange().location
              }
            : nil
        storage.beginEditing()
        storage.removeAttribute(.font, range: renderRange)
        storage.removeAttribute(.foregroundColor, range: renderRange)
        storage.removeAttribute(.backgroundColor, range: renderRange)
        storage.removeAttribute(.underlineStyle, range: renderRange)
        storage.removeAttribute(.link, range: renderRange)
        storage.removeAttribute(.strikethroughStyle, range: renderRange)
        storage.removeAttribute(.paragraphStyle, range: renderRange)
        storage.removeAttribute(.obliqueness, range: renderRange)
        storage.removeAttribute(.baselineOffset, range: renderRange)
        storage.removeAttribute(.attachment, range: renderRange)

        // Une `NSTextTable` doit être **partagée** par toutes les cellules
        // d'un même tableau pour que la grille s'aligne (colonnes cohérentes
        // entre rangées) — `NSTextTable` calcule la géométrie des colonnes
        // sur l'instance, pas par cellule. Ce dictionnaire, local à cet appel
        // et peuplé au fil de `enumerateAttributes` ci-dessous, garantit que
        // toute cellule rencontrée dans le `renderRange` courant réutilise la
        // même instance que ses voisines déjà vues dans ce même appel — voir
        // `normalizedRenderRange`, qui étend `renderRange` à la totalité d'un
        // tableau dès qu'une seule de ses cellules est touchée, pour que
        // « toutes les cellules déjà vues » couvre bien tout le tableau et
        // pas seulement une ligne.
        var tableInstances: [UUID: NSTextTable] = [:]
        var tableMaximumRows: [UUID: Int] = [:]
        storage.enumerateAttribute(.mdTableCell, in: renderRange) { value, _, _ in
            guard let cell = value as? TableCellInfo else { return }
            tableMaximumRows[cell.tableID] = max(tableMaximumRows[cell.tableID] ?? cell.row, cell.row)
        }

        storage.enumerateAttributes(in: renderRange, options: []) { attrs, range, _ in
            let block = attrs[.mdBlockType] as? BlockType ?? .paragraph
            let listInfo = attrs[.mdListInfo] as? ListInfo
            let tableCell = attrs[.mdTableCell] as? TableCellInfo
            let isBold = (attrs[.mdBold] as? Bool) == true
            let isItalic = (attrs[.mdItalic] as? Bool) == true
            let isCode = (attrs[.mdInlineCode] as? Bool) == true
            let isStrike = (attrs[.mdStrikethrough] as? Bool) == true
            let link = attrs[.mdLink] as? URL

            var font = baseFont(for: block)
            // La rangée d'en-tête (row 0) d'un tableau est toujours en gras
            // — visuel uniquement : ne pose pas `.mdBold`, qui ferait
            // réémettre `**...**` à la sérialisation et changerait le
            // contenu markdown d'une cellule d'en-tête qui n'en portait pas.
            if isBold || tableCell?.row == 0 {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if isItalic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            if isCode {
                font = NSFont.monospacedSystemFont(ofSize: baseFontSize - 0.5, weight: .regular)
            }
            storage.addAttribute(.font, value: font, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)

            if isCode {
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.quaternaryLabelColor.withAlphaComponent(0.4),
                    range: range
                )
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }

            if let link {
                // Chantier 2 de `docs/superpowers/specs/2026-08-05-dates-et-rappels.md` :
                // une mention, une date et un lien externe se distinguent
                // désormais en lisant le schéma/l'hôte de l'URL — voir
                // `LinkVisualStyle`. Tout reste purement visuel : posé ici,
                // effacé et redérivé à chaque frappe (`removeAttribute`
                // ci-dessus en tête de fonction), rien n'entre dans le
                // storage ni dans `MarkdownSerializer.emitInline` (qui ne lit
                // que `.mdLink`, jamais `.foregroundColor`/`.backgroundColor`/
                // `.underlineStyle`).
                let style = LinkVisualStyle.style(for: link)
                storage.addAttribute(.foregroundColor, value: style.foreground, range: range)
                if let background = style.background {
                    storage.addAttribute(.backgroundColor, value: background, range: range)
                }
                if style.underline {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
                // Attribut natif AppKit, distinct de `.mdLink` (source de
                // vérité markdown, lue par `MarkdownSerializer` — cf.
                // `MarkdownSerializer.emitInline`). `.link` ne pilote que
                // l'affichage/l'interaction : `EditorTextView` en dépend
                // pour reconnaître un clic sur un lien, mais la
                // sérialisation ne lit jamais cette clé, donc sa présence ne
                // peut pas fuiter dans le markdown produit.
                storage.addAttribute(.link, value: link, range: range)
            }

            if isStrike {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

            switch block {
            case .h1, .h2, .h3:
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            case .h6:
                // Voir la doc de `baseFont` : `.h6` est la seule des trois
                // (`.h4`/`.h5`/`.h6`) à recevoir une couleur distincte — sa
                // taille (11,5 pt) passe sous celle du corps de texte
                // (`baseFontSize`, 13 pt), `.secondaryLabelColor` la garde
                // lisible comme un titre plutôt que comme du texte réduit.
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .codeBlock, .rawBlock:
                // `.rawBlock` (bloc HTML passthrough — les tableaux GFM ont
                // leur propre rendu en grille, voir `tableCell` plus bas)
                // partage le rendu du bloc de code : texte brut monospace,
                // cf. la contrainte de conception du plan
                // parser-pertes-de-données — un bloc HTML affiché en texte
                // brut est acceptable, un bloc HTML effacé ne l'est pas.
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.quaternaryLabelColor.withAlphaComponent(0.3),
                    range: range
                )
            case .thematicBreak:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .h4, .h5, .paragraph, .blockquote:
                break
            }

            if block == .codeBlock, (attrs[.mdCodeLanguage] as? String) == "mermaid" {
                applyMermaidAttachment(to: storage, range: range, openSelection: openMermaidSelection)
            }

            if let info = listInfo {
                // `firstLineHeadIndent` == `headIndent` : le texte de l'item
                // (seul contenu de la ligne, le storage ne porte aucun
                // marqueur) démarre au même endroit sur sa première ligne et
                // sur ses lignes de repli. `MarkdownLayoutManager` dessine le
                // marqueur dans la marge ainsi libérée, à gauche de cette
                // position — voir `ListMarkerLayout.textIndent(for:)`.
                let para = NSMutableParagraphStyle()
                let indent = ListMarkerLayout.textIndent(for: info)
                para.headIndent = indent
                para.firstLineHeadIndent = indent
                storage.addAttribute(.paragraphStyle, value: para, range: range)
            } else if block == .blockquote {
                // Même mécanisme que pour un item de liste ci-dessus, mais
                // pour le filet d'une citation (voir `MarkdownLayoutManager`
                // et `BlockquoteRuleLayout`) : la marge ainsi réservée à
                // gauche du texte reçoit le trait, pas un marqueur. Un item
                // de liste l'emporte si les deux attributs coexistent
                // (`listInfo` ci-dessus) — combinaison hors du périmètre de
                // ce chantier (liste imbriquée dans une citation).
                let para = NSMutableParagraphStyle()
                let indent = BlockquoteRuleLayout.textIndent
                para.headIndent = indent
                para.firstLineHeadIndent = indent
                storage.addAttribute(.paragraphStyle, value: para, range: range)
            } else if let cellInfo = tableCell {
                // Grille réelle : `NSTextTableBlock` par cellule, posé sur un
                // `NSTextTable` **partagé** (via `tableInstances`, voir plus
                // haut) entre toutes les cellules de la même `tableID`
                // rencontrées dans cet appel — indispensable pour que les
                // colonnes s'alignent entre rangées. Mesuré hors écran avant
                // ce chantier (`Tests/NSTextTableProbeTests.swift`, sonde de
                // l'étape zéro) : `NSTextTable`/`NSTextTableBlock` peint
                // effectivement des bordures sur cette même pile TextKit 1
                // (`NSTextStorage` → `MarkdownLayoutManager` →
                // `NSTextContainer`), contrairement à `NSTextList` (aucun
                // marqueur peint, d'où `MarkdownLayoutManager` qui dessine
                // les puces à la main) — pas besoin ici d'un dessin manuel
                // équivalent, `NSLayoutManager.drawBackground(forGlyphRange:
                // at:)` (hérité, non redéfini par `MarkdownLayoutManager`)
                // peint déjà fond et bordures de bloc.
                let table = tableInstances[cellInfo.tableID] ?? {
                    let newTable = NSTextTable()
                    newTable.numberOfColumns = cellInfo.columnCount
                    newTable.layoutAlgorithm = .fixedLayoutAlgorithm
                    newTable.collapsesBorders = true
                    tableInstances[cellInfo.tableID] = newTable
                    return newTable
                }()
                let cellBlock = NSTextTableBlock(
                    table: table,
                    startingRow: cellInfo.row,
                    rowSpan: 1,
                    startingColumn: cellInfo.column,
                    columnSpan: 1
                )
                cellBlock.setBorderColor(TableLayout.borderColor)
                cellBlock.setWidth(TableLayout.borderWidth, type: .absoluteValueType, for: .border)
                cellBlock.setWidth(TableLayout.cellHorizontalPadding, type: .absoluteValueType, for: .padding, edge: .minX)
                cellBlock.setWidth(TableLayout.cellHorizontalPadding, type: .absoluteValueType, for: .padding, edge: .maxX)
                cellBlock.setWidth(TableLayout.cellVerticalPadding, type: .absoluteValueType, for: .padding, edge: .minY)
                cellBlock.setWidth(TableLayout.cellVerticalPadding, type: .absoluteValueType, for: .padding, edge: .maxY)
                if cellInfo.row == 0 {
                    cellBlock.backgroundColor = TableLayout.headerBackgroundColor
                }
                let para = NSMutableParagraphStyle()
                para.textBlocks = [cellBlock]
                para.alignment = TableLayout.textAlignment(for: cellInfo.alignment)
                para.minimumLineHeight = TableLayout.cellMinimumLineHeight
                if cellInfo.row == tableMaximumRows[cellInfo.tableID],
                   cellInfo.column == cellInfo.columnCount - 1 {
                    para.paragraphSpacing = TableLayout.footerReservedHeight
                }
                storage.addAttribute(.paragraphStyle, value: para, range: range)
            }

            // `mdImageURL` marque un run, pas forcément un seul caractère :
            // dans `NSTextView`, du texte tapé juste après une image hérite
            // de l'attribut via les `typingAttributes` du caractère
            // précédent, sans être lui-même une image (même défaut que
            // documenté et testé côté sérialisation, voir
            // `MarkdownSerializer.expandingImagePlaceholders`). On ne pose
            // donc l'attachment / la couleur d'échec que sur les caractères
            // `U+FFFC` du run ; le reste garde le style normal posé ci-dessus
            // (police, gras, paragraphStyle…).
            if let imageURL = attrs[.mdImageURL] as? URL {
                let nsText = storage.string as NSString
                var remaining = range
                while remaining.length > 0 {
                    let placeholder = nsText.range(of: "\u{FFFC}", options: [], range: remaining)
                    guard placeholder.location != NSNotFound else { break }
                    if let attachment = ImageAttachmentFactory.attachment(for: imageURL) {
                        storage.addAttribute(.attachment, value: attachment, range: placeholder)
                    } else {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: placeholder)
                    }
                    let nextLocation = placeholder.location + placeholder.length
                    remaining = NSRange(
                        location: nextLocation,
                        length: remaining.location + remaining.length - nextLocation
                    )
                }
            }
        }

        applyBlockSpacing(to: storage, in: renderRange, openMermaidSelection: openMermaidSelection)

        storage.endEditing()
    }

    /// Pose l'espace sur le dernier paragraphe de chaque bloc logique. Le
    /// faire à cet endroit préserve les styles spécialisés déjà construits
    /// pour les listes, citations, tableaux et blocs Mermaid.
    private static func applyBlockSpacing(
        to storage: NSTextStorage, in renderRange: NSRange, openMermaidSelection: Int?
    ) {
        let text = storage.string as NSString
        let renderEnd = min(NSMaxRange(renderRange), storage.length)
        var location = min(renderRange.location, renderEnd)

        while location < renderEnd {
            let block = BlockRange.of(in: storage, at: location).range
            let physicalLine = text.lineRange(for: NSRange(location: location, length: 0))
            let blockAdvance = block.length > 0 ? NSMaxRange(block) : location
            let nextLocation = min(
                renderEnd,
                max(location + 1, max(blockAdvance + 1, NSMaxRange(physicalLine)))
            )

            if block.length > 0 {
                let lastCharacter = NSMaxRange(block) - 1
                let terminalParagraph = NSIntersectionRange(
                    text.lineRange(for: NSRange(location: lastCharacter, length: 0)),
                    block
                )
                if terminalParagraph.length > 0 {
                    // L'écart large dès qu'un des deux voisins dessine un
                    // cadre : une carte doit avoir la même respiration
                    // au-dessus qu'en dessous, et seul `paragraphSpacing` la
                    // porte — poser en plus `paragraphSpacingBefore` sur la
                    // carte suivante ferait 56 pt (TextKit additionne les
                    // deux).
                    // Le séparateur entre deux blocs logiques n'est pas
                    // toujours un seul caractère : `MarkdownParser.parse`
                    // normalise à un unique `\n`, mais le storage **vivant**
                    // ne l'est jamais renormalisé — un utilisateur qui tape
                    // deux fois Retour insère une vraie ligne vide, donc un
                    // second `\n` avant le début réel du bloc suivant.
                    // `NSMaxRange(block) + 1` retomberait alors sur ce `\n`
                    // de la ligne vide (qui porte `.mdBlockType == .paragraph`,
                    // donc `isCardBlock` répondrait `false` à tort) au lieu
                    // du prochain bloc : on avance donc tant qu'on lit un
                    // saut de ligne, borné par la fin du storage.
                    var nextBlockStart = NSMaxRange(block)
                    while nextBlockStart < storage.length, text.character(at: nextBlockStart) == 0x0A {
                        nextBlockStart += 1
                    }
                    let touchesACard = BlockGutterLayout.isCardBlock(in: storage, at: block.location)
                        || BlockGutterLayout.isCardBlock(in: storage, at: nextBlockStart)
                    let spacing = touchesACard
                        ? BlockGutterLayout.cardBlockSpacing
                        : BlockGutterLayout.blockSpacing

                    let existing = storage.attribute(
                        .paragraphStyle,
                        at: terminalParagraph.location,
                        effectiveRange: nil
                    ) as? NSParagraphStyle
                    let style = (existing?.mutableCopy() as? NSMutableParagraphStyle)
                        ?? NSMutableParagraphStyle()
                    // L'écart demandé s'**ajoute** au padding interne que le
                    // bloc porte déjà en bas (voir `interiorBottomPadding`),
                    // puis le `max` protège les styles spécialisés qui posent
                    // déjà davantage (zone de contrôles d'un tableau).
                    let interior = interiorBottomPadding(
                        ofBlock: block, in: storage, openMermaidSelection: openMermaidSelection
                    )
                    style.paragraphSpacing = max(style.paragraphSpacing, spacing + interior)
                    storage.addAttribute(.paragraphStyle, value: style, range: terminalParagraph)
                }
            }

            location = nextLocation
        }
    }

    /// Espace que le dernier paragraphe de `block` occupe **à l'intérieur** de
    /// sa propre carte — celui sous lequel le cadre se referme, par opposition
    /// à l'écart inter-blocs, qui sépare deux cartes voisines. L'un doit
    /// s'ajouter à l'autre, sinon l'écart **visible** sous la carte vaut la
    /// différence des deux : mesuré, 18 pt en dessous contre 28 au-dessus
    /// (`max(10, 28) = 28`, dont 10 restent dans le cadre).
    ///
    /// Seul le bloc mermaid **ouvert** en porte un
    /// (`MermaidSourceLayout.bodyBottomPadding`, posé par
    /// `applyOpenMermaidGeometry` sur sa dernière ligne). Le `paragraphSpacing`
    /// d'un tableau (`TableLayout.footerReservedHeight`) est d'une autre
    /// nature — une bande réservée **sous** la grille pour ses contrôles, pas
    /// un padding de cadre : il reste protégé par le `max` de l'appelant,
    /// jamais additionné. Un bloc mermaid **fermé** n'a rien non plus : sa
    /// carte est l'image, dessinée à sa taille native.
    private static func interiorBottomPadding(
        ofBlock block: NSRange, in storage: NSTextStorage, openMermaidSelection: Int?
    ) -> CGFloat {
        guard let selection = openMermaidSelection,
              block.location < storage.length,
              storage.attribute(.mdMermaidAttachment, at: block.location, effectiveRange: nil) != nil,
              MermaidBlockLayout.selectionTouches(selection, blockRange: block)
        else { return 0 }
        return MermaidSourceLayout.bodyBottomPadding
    }

    /// Pose l'attachment mermaid rendu (`MermaidAttachmentFactory`) sur toute
    /// la plage `range` d'un bloc de code dont `.mdCodeLanguage == "mermaid"`,
    /// puis bascule sa géométrie entre **fermé** (diagramme peint par
    /// `MarkdownLayoutManager.drawMermaidDiagram`, hauteur suivant l'image —
    /// voir `applyClosedMermaidGeometry`) et **ouverte** (source affiché en
    /// édition, interligne normal — voir `applyOpenMermaidGeometry`), selon
    /// que le curseur touche ou non `range` — `openSelection` transmis par
    /// l'appelant (voir sa doc dans `applyVisualStyle`) : la position du
    /// curseur, ou `nil` quand aucun bloc ne peut être ouvert. Le rendu proprement
    /// dit est asynchrone (voir `MermaidRenderer`) : `onUpdate` **ré-applique**
    /// la géométrie fermée (`refreshMermaidGeometry`), pas seulement
    /// n'invalide la mise en page — `NSParagraphStyle.minimumLineHeight` est
    /// une valeur figée dans l'attribut posé ci-dessous, `invalidateLayout`
    /// seul ne la recalcule pas depuis la taille (nouvelle, une fois le rendu
    /// livré) de l'image : sans ce ré-calcul, la ligne réservée reste à la
    /// taille du placeholder (104pt) alors que l'image dessinée (à sa taille
    /// native, voir `MarkdownLayoutManager.drawMermaidDiagram`) peut être plus
    /// grande — le cadre d'erreur (132pt, toujours plus haut que le
    /// placeholder) déborde alors systématiquement sur les lignes de source
    /// suivantes, dont le masquage (`.foregroundColor = .clear`) reste
    /// correct mais dont l'espace, désormais insuffisant, ne les couvre plus
    /// visuellement (constat de tâche : source dessiné « en travers » du
    /// cadre d'erreur). Jamais le storage textuel, jamais une
    /// re-sérialisation, jamais une pile d'annulation (voir
    /// `MermaidAttachmentFactoryTests`) : seuls des attributs d'affichage
    /// sont mutés, comme partout ailleurs dans `StyleRenderer`.
    private static func applyMermaidAttachment(to storage: NSTextStorage, range: NSRange, openSelection: Int?) {
        guard range.length > 0 else { return }
        let source = (storage.string as NSString).substring(with: range)
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        // `MermaidAttachmentFactory` est `@MainActor` (elle pilote un
        // `WKWebView`) ; `applyVisualStyle` ne l'est pas elle-même, mais
        // n'est jamais appelée que depuis le fil d'édition AppKit (délégués
        // `NSTextView`, `SlashController`, `ShortcutDetector`…), toujours le
        // fil principal — `assumeIsolated` rend cette hypothèse explicite
        // plutôt que de propager `@MainActor` à `StyleRenderer` tout entier
        // et, avec lui, à tous ses appelants.

        if let selectionLocation = openSelection,
           MermaidBlockLayout.selectionTouches(selectionLocation, blockRange: range) {
            // Bloc **en édition** : ne jamais relancer de rendu ici. Le
            // source est en cours de frappe — le plus souvent invalide —
            // et chaque frappe relançait un rendu (`WKWebView` à chaque
            // caractère, le natif jetant sur un source incomplet) dont la
            // completion asynchrone, armée d'une plage capturée avant les
            // frappes suivantes, refermait la géométrie du bloc en pleine
            // édition (superposition carte/erreur/source mesurée à
            // l'écran). L'attachment déjà posé (dernier rendu abouti ou
            // placeholder) est reposé tel quel sur toute la plage — même
            // instance, donc un seul run uniforme pour
            // `longestEffectiveRange`. Le rendu du source final part à la
            // fermeture (curseur sorti → restylage ciblé, branche fermée
            // ci-dessous).
            let existing = storage.attribute(
                .mdMermaidAttachment, at: range.location, effectiveRange: nil
            ) as? NSTextAttachment
            let attachment: NSTextAttachment = existing ?? MainActor.assumeIsolated {
                MermaidAttachmentFactory.placeholder(for: source)
            }
            storage.addAttribute(.mdMermaidAttachment, value: attachment, range: range)

            // Largeur de la colonne réellement affichée : la bande d'aperçu
            // est réduite pour y tenir, et la hauteur réservée ici doit être
            // calculée sur la **même** largeur que le dessin, sinon un vide
            // subsiste sous l'aperçu. Repli sur `columnWidth` quand aucune vue
            // n'est attachée (cas des tests).
            let containerWidth = MainActor.assumeIsolated {
                storage.layoutManagers.first?.firstTextView?.textContainer?.size.width
            } ?? 0
            applyOpenMermaidGeometry(
                to: storage, range: range,
                attachmentImageSize: attachment.image?.size,
                containerWidth: containerWidth > 0 ? containerWidth : MermaidBlockLayout.columnWidth
            )
            return
        }

        let attachment = MainActor.assumeIsolated {
            MermaidAttachmentFactory.attachment(for: source, isDark: isDark) { updated in
                refreshMermaidGeometry(in: storage, attachment: updated)
            }
        }
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: range)
        applyClosedMermaidGeometry(to: storage, range: range, attachmentImageSize: attachment.image?.size)
    }

    /// Ré-applique la géométrie du bloc d'après la taille **actuelle** de
    /// l'attachment mermaid qui y est posé — appelée depuis `onUpdate` (voir
    /// sa doc dans `applyMermaidAttachment`) une fois le rendu asynchrone
    /// terminé (succès ou erreur). Ne fait rien si l'attachment n'est plus
    /// dans le storage (bloc retiré, ou attachment remplacé entre-temps :
    /// completion périmée).
    ///
    /// **Réagit** à un rendu qui aboutit ; n'en déclenche jamais.
    ///
    /// Bloc **fermé** : `applyClosedMermaidGeometry` recalcule la ligne
    /// réservée (l'image dessinée à sa taille native déborderait sinon).
    ///
    /// Bloc **ouvert** : seule la **réservation** de la bande est recalculée
    /// (`applyOpenMermaidReservation`), pas toute la géométrie ouverte. Elle
    /// dépend bien de la taille de l'image (la bande contient l'aperçu figé),
    /// et le scénario est réel : éditer un bloc, cliquer « Terminé »,
    /// recliquer dedans avant la fin du rendu — la réservation avait été
    /// calculée sur le placeholder (960×104, bande 110,3) tandis que le
    /// dessin relit l'image courante (960×450, bande 254,5), soit 144 pt de
    /// débord jusqu'à la frappe suivante (mesuré). Rejouer toute la géométrie
    /// ouverte serait faux dans l'autre sens : elle repose
    /// `paragraphSpacing = bodyBottomPadding` sur la dernière ligne, écrasant
    /// l'écart inter-blocs qu'`applyBlockSpacing` y a posé **après** elle.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests avec un attachment dont l'image a été substituée à la main
    /// (simule un rendu terminé sans dépendre du timing d'un vrai
    /// `WKWebView`) — même patron que `EditorTextView.mermaidDoneButtonRange`.
    static func refreshMermaidGeometry(in storage: NSTextStorage, attachment: NSTextAttachment) {
        // Retrouve la plage **actuelle** du bloc par l'identité de son
        // attachment — jamais une plage capturée au lancement du rendu : le
        // bloc a pu grandir, se déplacer, être supprimé ou son attachment
        // remplacé pendant le rendu asynchrone. Une plage périmée faisait
        // croire le bloc fermé (curseur au-delà de son ancienne borne) et
        // refermait sa géométrie en pleine édition — la superposition
        // carte/erreur/source mesurée à l'écran. Attachment absent = rendu
        // périmé : ne rien faire.
        var currentRange: NSRange?
        storage.enumerateAttribute(
            .mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)
        ) { value, runRange, stop in
            guard (value as? NSTextAttachment) === attachment else { return }
            currentRange = MermaidBlockLayout.blockRange(in: storage, at: runRange.location)
            stop.pointee = true
        }
        guard let range = currentRange else { return }

        let textView = storage.layoutManagers.first?.firstTextView
        let selectionLocation = textView?.selectedRange().location ?? NSNotFound

        storage.beginEditing()
        if MermaidBlockLayout.selectionTouches(selectionLocation, blockRange: range) {
            // Même repli que dans `applyMermaidAttachment` : la largeur
            // réellement affichée, sinon `columnWidth` (cas des tests, aucune
            // vue attachée). Les deux doivent lire la même largeur, sans quoi
            // la réservation et le dessin divergent.
            let containerWidth = textView?.textContainer?.size.width ?? 0
            applyOpenMermaidReservation(
                to: storage, range: range,
                attachmentImageSize: attachment.image?.size,
                containerWidth: containerWidth > 0 ? containerWidth : MermaidBlockLayout.columnWidth
            )
        } else {
            applyClosedMermaidGeometry(to: storage, range: range, attachmentImageSize: attachment.image?.size)
        }
        storage.endEditing()

        for layoutManager in storage.layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        (storage.layoutManagers.first?.firstTextView as? EditorTextView)?
            .invalidateMermaidPresentation(for: [range])
    }

    /// Géométrie **fermée** (état 1/2/4) : tout le bloc devient invisible
    /// (`.foregroundColor = .clear`, pas de fond — le fond gris standard des
    /// blocs de code, posé juste avant pour `.codeBlock`, est explicitement
    /// retiré ici : il débordait sur toute la largeur, voir le constat de
    /// tâche) ; seule la première ligne réserve une hauteur
    /// (`MermaidBlockLayout.closedFrameHeight`, celle de l'image réelle une
    /// fois connue, sinon `placeholderHeight`) — les lignes suivantes sont
    /// plafonnées à un filet quasi nul (`hiddenLineMaximumHeight`), jamais
    /// étalées : la mise en page tient sur une seule ligne, jamais sur
    /// `lineCount` lignes comme l'ancien défaut.
    private static func applyClosedMermaidGeometry(to storage: NSTextStorage, range: NSRange, attachmentImageSize: NSSize?) {
        storage.removeAttribute(.backgroundColor, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)

        let ns = storage.string as NSString
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: range, in: ns)

        let firstLineStyle = NSMutableParagraphStyle()
        firstLineStyle.minimumLineHeight = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: attachmentImageSize)
        storage.addAttribute(.paragraphStyle, value: firstLineStyle, range: firstLine)

        if rest.length > 0 {
            let restStyle = NSMutableParagraphStyle()
            restStyle.maximumLineHeight = MermaidBlockLayout.hiddenLineMaximumHeight
            storage.addAttribute(.paragraphStyle, value: restStyle, range: rest)
        }
    }

    /// Géométrie **ouverte** (état 3, curseur dans le bloc) : le fond gris
    /// standard du bloc de code (déjà posé par le switch principal) et la
    /// police monospace normale restent — c'est un bloc de code en édition
    /// comme un autre, juste avec un interligne plus aéré
    /// (`MermaidSourceLayout.lineHeightMultiple`) et une marge à gauche
    /// (`gutterWidth`) pour la gouttière de numéros de ligne peinte par
    /// `MarkdownLayoutManager.drawMermaidLineNumber`.
    ///
    /// La première ligne reçoit `paragraphSpacingBefore` : l'espace où
    /// `MarkdownLayoutManager` peint l'étiquette `mermaid`, le bouton
    /// « Terminé » **et** la bande d'aperçu figé (l'image déjà posée sur
    /// l'attachment, jamais un rendu relancé — voir `applyMermaidAttachment`).
    /// Toujours l'espacement de paragraphe, jamais `minimumLineHeight` :
    /// gonfler la hauteur de la première ligne produirait un curseur vertical
    /// surdimensionné.
    private static func applyOpenMermaidGeometry(
        to storage: NSTextStorage, range: NSRange,
        attachmentImageSize: NSSize?, containerWidth: CGFloat
    ) {
        storage.removeAttribute(.backgroundColor, range: range)
        let ns = storage.string as NSString
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: range, in: ns)

        let firstLineStyle = NSMutableParagraphStyle()
        firstLineStyle.lineHeightMultiple = MermaidSourceLayout.lineHeightMultiple
        let codeIndent = MermaidSourceLayout.gutterWidth + MermaidSourceLayout.codeHorizontalPadding
        firstLineStyle.headIndent = codeIndent
        firstLineStyle.firstLineHeadIndent = codeIndent
        firstLineStyle.minimumLineHeight = MermaidSourceLayout.sourceLineHeight
        firstLineStyle.paragraphSpacingBefore = MermaidSourceLayout.reservedBandHeight(
            forAttachmentSize: attachmentImageSize, containerWidth: containerWidth
        )
        storage.addAttribute(.paragraphStyle, value: firstLineStyle, range: firstLine)

        if rest.length > 0 {
            let restStyle = NSMutableParagraphStyle()
            restStyle.lineHeightMultiple = MermaidSourceLayout.lineHeightMultiple
            restStyle.headIndent = codeIndent
            restStyle.firstLineHeadIndent = codeIndent
            storage.addAttribute(.paragraphStyle, value: restStyle, range: rest)
        }

        let lastLocation = max(range.location, NSMaxRange(range) - 1)
        let lastLine = NSIntersectionRange(
            ns.lineRange(for: NSRange(location: lastLocation, length: 0)),
            range
        )
        if lastLine.length > 0,
           let existing = storage.attribute(.paragraphStyle, at: lastLine.location, effectiveRange: nil) as? NSParagraphStyle,
           let lastStyle = existing.mutableCopy() as? NSMutableParagraphStyle {
            lastStyle.paragraphSpacing = MermaidSourceLayout.bodyBottomPadding
            storage.addAttribute(.paragraphStyle, value: lastStyle, range: lastLine)
        }
    }

    /// Recalcule la **seule** réservation de bande (`paragraphSpacingBefore`
    /// sur la première ligne) d'un bloc déjà ouvert, en laissant intact tout
    /// le reste de son style de paragraphe — c'est ce qui permet à
    /// `refreshMermaidGeometry` de réagir à un rendu qui aboutit sur un bloc
    /// en édition sans écraser le `paragraphSpacing` qu'`applyBlockSpacing` a
    /// posé après coup sur sa dernière ligne (l'écart qui sépare la carte du
    /// bloc suivant).
    ///
    /// La hauteur vient du même point d'entrée que celui posé par
    /// `applyOpenMermaidGeometry` (`MermaidSourceLayout.reservedBandHeight`) :
    /// un seul calcul de bande, partagé aussi par le dessin du cadre, celui
    /// de l'en-tête et le hit-test de « Terminé ».
    private static func applyOpenMermaidReservation(
        to storage: NSTextStorage, range: NSRange,
        attachmentImageSize: NSSize?, containerWidth: CGFloat
    ) {
        let (firstLine, _) = MermaidBlockLayout.splitFirstLine(of: range, in: storage.string as NSString)
        guard firstLine.length > 0 else { return }
        let existing = storage.attribute(
            .paragraphStyle, at: firstLine.location, effectiveRange: nil
        ) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.paragraphSpacingBefore = MermaidSourceLayout.reservedBandHeight(
            forAttachmentSize: attachmentImageSize, containerWidth: containerWidth
        )
        storage.addAttribute(.paragraphStyle, value: style, range: firstLine)
    }

    /// Point d'entrée `internal` sur `applyOpenMermaidGeometry`, pour les
    /// tests : exercer la géométrie ouverte sans passer par
    /// `applyVisualStyle`, qui déclencherait un vrai `WKWebView` en tâche de
    /// fond (voir la doc de tête de `StyleRendererMermaidTests`). Même patron
    /// que `refreshMermaidGeometry`/`EditorTextView.mermaidDoneButtonRange`.
    static func applyOpenMermaidGeometryForTesting(
        to storage: NSTextStorage, range: NSRange,
        attachmentImageSize: NSSize?, containerWidth: CGFloat
    ) {
        applyOpenMermaidGeometry(
            to: storage, range: range,
            attachmentImageSize: attachmentImageSize, containerWidth: containerWidth
        )
    }

    private static func normalizedRenderRange(_ range: NSRange?, in storage: NSTextStorage) -> NSRange {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard let range else { return fullRange }

        let location = min(max(0, range.location), storage.length)
        let upperBound = min(max(location, range.location + range.length), storage.length)
        let clamped = NSRange(location: location, length: upperBound - location)
        let nsText = storage.string as NSString
        let lineRange = expandedForTable(nsText.lineRange(for: clamped), in: storage)
        return expandedForPreviousBlock(expandedForMermaidBlock(lineRange, in: storage), in: storage)
    }

    /// Étend `range` vers le haut jusqu'à englober le **bloc précédent**.
    ///
    /// L'écart inter-blocs n'est pas porté par le bloc qui apparaît : il est
    /// posé par `applyBlockSpacing` sur le **dernier paragraphe du bloc du
    /// dessus** (`paragraphSpacing`, jamais `paragraphSpacingBefore` — voir sa
    /// doc). Un restylage ciblé qui s'arrête au bloc courant ne le touche donc
    /// jamais : après un `/tableau` ou un `/diagramme` inséré sur une ligne
    /// neuve, la carte recevait bien ses 28 pt en dessous, mais le paragraphe
    /// au-dessus gardait ses 10 pt jusqu'à ce qu'autre chose le restyle ;
    /// symétriquement, supprimer une carte y laissait 28 pt périmés.
    ///
    /// Étendre la **plage restylée** (et pas seulement celle qu'`applyBlockSpacing`
    /// balaie) est nécessaire dans les deux sens : le `removeAttribute(
    /// .paragraphStyle, range: renderRange)` de tête d'`applyVisualStyle` est
    /// ce qui permet à `max(style.paragraphSpacing, spacing)` de repartir de
    /// zéro. Sans lui, un écart de 28 pt déjà posé ne pourrait jamais
    /// redescendre à 10.
    ///
    /// Restyler un bloc mermaid voisin ne relance **aucun** rendu :
    /// `MermaidAttachmentFactory.attachment(for:isDark:onUpdate:)` sert
    /// l'attachment déjà en cache pour la même clé (source, apparence) sans
    /// rouvrir de `WKWebView`.
    private static func expandedForPreviousBlock(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        guard range.location > 0 else { return range }
        let nsText = storage.string as NSString

        // Le séparateur entre deux blocs n'est pas toujours un seul `\n` : le
        // storage vivant n'est jamais renormalisé (voir le commentaire jumeau
        // dans `applyBlockSpacing`). On remonte donc les sauts de ligne
        // jusqu'au dernier caractère réel du bloc précédent.
        var probe = range.location - 1
        while probe > 0, nsText.character(at: probe) == 0x0A {
            probe -= 1
        }

        let previous = BlockRange.of(in: storage, at: probe).range
        let start = min(range.location, previous.length > 0 ? previous.location : probe)
        return NSRange(location: start, length: NSMaxRange(range) - start)
    }

    /// Si `lineRange` tombe dans un bloc de code mermaid (`.mdBlockType ==
    /// .codeBlock` + `.mdCodeLanguage == "mermaid"`), étend le résultat à la
    /// totalité de **ce** bloc. `.mdBlockType`/`.mdCodeLanguage` sont posés
    /// par le parseur comme un seul run continu sur tout le bloc (fences
    /// comprises) — contrairement aux cellules de tableau (voir
    /// `expandedForTable`, qui doit reconstituer la plage à la main car
    /// chaque cellule y est un run distinct), une seule lecture
    /// d'`effectiveRange` suffit ici.
    ///
    /// Nécessaire pour une raison différente d'`expandedForTable` mais tout
    /// aussi bloquante : `applyMermaidAttachment` recalcule `source` en
    /// relisant la plage reçue (`substring(with: range)`) — une frappe sur
    /// la 3ᵉ ligne d'un bloc mermaid de 10 lignes ne doit jamais lui passer
    /// cette seule ligne comme si c'était tout le source (attachment/rendu
    /// mermaid faux, et géométrie fermée recalculée sur une « première
    /// ligne » qui n'en est pas une).
    private static func expandedForMermaidBlock(_ lineRange: NSRange, in storage: NSTextStorage) -> NSRange {
        guard lineRange.location < storage.length,
              storage.attribute(.mdBlockType, at: lineRange.location, effectiveRange: nil) as? BlockType == .codeBlock,
              storage.attribute(.mdCodeLanguage, at: lineRange.location, effectiveRange: nil) as? String == "mermaid"
        else { return lineRange }

        // `longestEffectiveRange(_:in:)` — jamais le simple `effectiveRange:` —
        // pour la même raison que `MermaidBlockLayout.blockRange(in:at:)` : un
        // bloc déjà stylé une première fois porte un `.paragraphStyle`
        // différent sur sa première ligne et le reste (voir
        // `applyOpenMermaidGeometry`/`applyClosedMermaidGeometry`), ce qui
        // scinde la représentation interne du storage à cette frontière —
        // `effectiveRange:` s'y arrêterait même si `.mdBlockType` porte la
        // même valeur des deux côtés.
        var blockRange = NSRange(location: 0, length: 0)
        _ = storage.attribute(
            .mdBlockType, at: lineRange.location,
            longestEffectiveRange: &blockRange, in: NSRange(location: 0, length: storage.length)
        )
        // Union plutôt que remplacement pur : `lineRange` peut déborder
        // légèrement `blockRange` (retour à la ligne terminal compris dans
        // l'un mais pas l'autre), même précaution qu'`expandedForTable`.
        let start = min(lineRange.location, blockRange.location)
        let end = max(lineRange.location + lineRange.length, blockRange.location + blockRange.length)
        return NSRange(location: start, length: end - start)
    }

    /// Si `lineRange` touche une cellule de tableau (`.mdTableCell`), étend
    /// le résultat à la totalité de **ce** tableau (toutes les lignes qui
    /// partagent le même `tableID`, avant et après). Nécessaire parce
    /// qu'`NSTextTable` exige la même instance partagée entre toutes ses
    /// cellules pour que la grille s'aligne (voir le commentaire sur
    /// `tableInstances` dans `applyVisualStyle`) : un rafraîchissement
    /// partiel qui ne reconstruirait qu'une seule ligne créerait, pour
    /// cette ligne, une nouvelle `NSTextTable` déconnectée de celles déjà
    /// posées sur les lignes voisines (non retouchées par cet appel-là),
    /// disloquant visuellement le tableau à la frappe suivante. Un tableau
    /// des notes réelles ne dépasse pas quelques rangées (cf. vérification
    /// sur `~/Documents/OneToOne-sauvegarde-notes-2026-08-05/`) : le coût
    /// d'un ré-étalement systématique du tableau entier à chaque frappe dans
    /// une de ses cellules reste négligeable.
    private static func expandedForTable(_ lineRange: NSRange, in storage: NSTextStorage) -> NSRange {
        guard lineRange.location < storage.length,
              let id = (storage.attribute(.mdTableCell, at: lineRange.location, effectiveRange: nil) as? TableCellInfo)?.tableID
        else { return lineRange }

        let nsText = storage.string as NSString
        var start = lineRange.location
        var end = lineRange.location + lineRange.length

        func tableID(at location: Int) -> UUID? {
            guard location < storage.length else { return nil }
            return (storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)?.tableID
        }

        while start > 0 {
            let previousLine = nsText.lineRange(for: NSRange(location: start - 1, length: 0))
            guard tableID(at: previousLine.location) == id else { break }
            start = previousLine.location
        }

        while end < storage.length {
            let nextLine = nsText.lineRange(for: NSRange(location: end, length: 0))
            guard tableID(at: nextLine.location) == id else { break }
            end = nextLine.location + nextLine.length
        }

        return NSRange(location: start, length: end - start)
    }

    /// `.h4`/`.h5`/`.h6` avaient jusqu'ici la même taille (13,5 pt semibold,
    /// aucune ne s'en distinguait), sans conséquence tant qu'aucune entrée du
    /// menu `/` ne les rendait atteignables — l'utilisateur ne pouvait
    /// produire ces trois titres qu'en tapant `####`/`#####`/`######` à la
    /// main (`ShortcutDetector`), un geste rare. Depuis que le menu `/` les
    /// propose, les trois seraient sinon indiscernables l'une de l'autre à
    /// l'écran. Différenciées ici par une taille strictement décroissante
    /// (14 → 12,5 → 11,5 pt), qui prolonge la progression déjà en place pour
    /// `.h1`/`.h2`/`.h3` (22 → 18 → 15 pt) plutôt que de sauter d'un palier
    /// disjoint ; `.h6` reçoit en plus `.secondaryLabelColor` (ci-dessous,
    /// dans `applyVisualStyle`) pour rester lisible comme titre malgré une
    /// taille passée sous celle du corps de texte (`baseFontSize`, 13 pt).
    private static func baseFont(for block: BlockType) -> NSFont {
        switch block {
        case .h1: return NSFont.systemFont(ofSize: 22, weight: .bold)
        case .h2: return NSFont.systemFont(ofSize: 18, weight: .bold)
        case .h3: return NSFont.systemFont(ofSize: 15, weight: .bold)
        case .h4: return NSFont.systemFont(ofSize: 14, weight: .semibold)
        case .h5: return NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        case .h6: return NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        case .codeBlock, .rawBlock: return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        case .blockquote, .paragraph, .thematicBreak:
            return NSFont.systemFont(ofSize: baseFontSize)
        }
    }
}

/// Rendu visuel d'un lien `.mdLink`, choisi en lisant le schéma/l'hôte de son
/// URL — chantier 2 de
/// `docs/superpowers/specs/2026-08-05-dates-et-rappels.md` : « une mention,
/// une date et une URL externe s'affichent aujourd'hui identiquement (bleu
/// souligné) ; `StyleRenderer` ne lit jamais le schéma de l'URL ». Une
/// mention (`onetoone://collaborator/<uuid>`, voir `MentionCatalog`) et une
/// date (`onetoone://date/…`, voir `DateLinkCatalog`) reçoivent chacune un
/// fond teinté et pas de soulignement (repère de « pastille », sobre : pas
/// d'icône — hors périmètre de ce chantier, voir la spec) ; tout le reste
/// (schéma différent de `onetoone`, ou hôte `onetoone` non reconnu — un futur
/// hôte encore inconnu de cette version, par prudence plutôt qu'un crash ou
/// un rendu halluciné) garde le rendu historique : couleur de lien, souligné,
/// aucun fond.
///
/// Couleurs choisies parmi les couleurs système dynamiques
/// (`NSColor.systemOrange`/`.systemIndigo`), pas des constantes RVB fixes :
/// elles s'adaptent déjà nativement au mode sombre, comme `.labelColor`/
/// `.linkColor` ailleurs dans ce fichier — mêmes objets `NSColor` comparés
/// directement par les tests d'attribut (`test_heading6_getsSecondaryLabelColor…`
/// compare déjà `NSColor.secondaryLabelColor` sans rendu offscreen), donc pas
/// concernées par le piège des tests pixel (`NSColor.labelColor` résolu en
/// blanc peint sur fond blanc en apparence sombre, voir la doc de
/// `StyleRendererTests.renderToOffscreenBitmap`) : ce piège ne touche que les
/// tests qui *peignent* et lisent des pixels, pas ceux qui comparent
/// l'attribut `NSColor` posé.
private struct LinkVisualStyle {
    let foreground: NSColor
    /// `nil` pour le rendu historique (lien externe) : `applyVisualStyle` ne
    /// pose alors aucun `.backgroundColor`, exactement comme avant ce
    /// chantier.
    let background: NSColor?
    let underline: Bool

    private static let externalLink = LinkVisualStyle(foreground: .linkColor, background: nil, underline: true)

    static func style(for url: URL) -> LinkVisualStyle {
        guard url.scheme == "onetoone" else { return externalLink }
        switch url.host {
        case "date":
            return LinkVisualStyle(
                foreground: .systemOrange,
                background: NSColor.systemOrange.withAlphaComponent(0.14),
                underline: false
            )
        case "collaborator":
            return LinkVisualStyle(
                foreground: .systemIndigo,
                background: NSColor.systemIndigo.withAlphaComponent(0.14),
                underline: false
            )
        default:
            return externalLink
        }
    }
}
