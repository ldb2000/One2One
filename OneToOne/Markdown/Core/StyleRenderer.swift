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
        storage.beginEditing()
        storage.removeAttribute(.font, range: renderRange)
        storage.removeAttribute(.foregroundColor, range: renderRange)
        storage.removeAttribute(.backgroundColor, range: renderRange)
        storage.removeAttribute(.underlineStyle, range: renderRange)
        storage.removeAttribute(.link, range: renderRange)
        storage.removeAttribute(.strikethroughStyle, range: renderRange)
        storage.removeAttribute(.paragraphStyle, range: renderRange)
        storage.removeAttribute(.obliqueness, range: renderRange)
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
                applyMermaidAttachment(to: storage, range: range, allowsOpen: allowsOpenMermaidBlock)
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
                cellBlock.setWidth(TableLayout.cellPadding, type: .absoluteValueType, for: .padding)
                if cellInfo.row == 0 {
                    cellBlock.backgroundColor = TableLayout.headerBackgroundColor
                }
                let para = NSMutableParagraphStyle()
                para.textBlocks = [cellBlock]
                para.alignment = TableLayout.textAlignment(for: cellInfo.alignment)
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

        storage.endEditing()
    }

    /// Pose l'attachment mermaid rendu (`MermaidAttachmentFactory`) sur toute
    /// la plage `range` d'un bloc de code dont `.mdCodeLanguage == "mermaid"`,
    /// puis bascule sa géométrie entre **fermé** (diagramme peint par
    /// `MarkdownLayoutManager.drawMermaidDiagram`, hauteur suivant l'image —
    /// voir `applyClosedMermaidGeometry`) et **ouverte** (source affiché en
    /// édition, interligne normal — voir `applyOpenMermaidGeometry`), selon
    /// que le curseur touche ou non `range` — `allowsOpen` transmis par
    /// l'appelant (voir sa doc dans `applyVisualStyle`). Le rendu proprement
    /// dit est asynchrone (voir `MermaidRenderer`) : `onUpdate` **ré-applique**
    /// la géométrie fermée (`refreshClosedMermaidGeometry`), pas seulement
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
    private static func applyMermaidAttachment(to storage: NSTextStorage, range: NSRange, allowsOpen: Bool) {
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
        let (attachment, selectionLocation) = MainActor.assumeIsolated { () -> (NSTextAttachment, Int) in
            let attachment = MermaidAttachmentFactory.attachment(for: source, isDark: isDark) {
                refreshClosedMermaidGeometry(in: storage, range: range)
            }
            let location = storage.layoutManagers.first?.firstTextView?.selectedRange().location ?? NSNotFound
            return (attachment, location)
        }
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: range)

        if allowsOpen, MermaidBlockLayout.selectionTouches(selectionLocation, blockRange: range) {
            applyOpenMermaidGeometry(to: storage, range: range)
        } else {
            applyClosedMermaidGeometry(to: storage, range: range, attachmentImageSize: attachment.image?.size)
        }
    }

    /// Ré-applique la géométrie **fermée** de `range` d'après la taille
    /// **actuelle** de l'attachment mermaid qui y est posé — appelée depuis
    /// `onUpdate` (voir sa doc dans `applyMermaidAttachment`) une fois le
    /// rendu asynchrone terminé (succès ou erreur). Ne fait rien si `range`
    /// ne pointe plus dans les bornes du storage (bloc retiré entre-temps)
    /// ou si le bloc est actuellement **ouvert** (curseur dedans) : la
    /// géométrie ouverte ne dépend pas de la taille de l'image, la rouvrir
    /// ici écraserait à tort son interligne d'édition.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests avec un attachment dont l'image a été substituée à la main
    /// (simule un rendu terminé sans dépendre du timing d'un vrai
    /// `WKWebView`) — même patron que `EditorTextView.mermaidDoneButtonRange`.
    static func refreshClosedMermaidGeometry(in storage: NSTextStorage, range: NSRange) {
        guard range.location >= 0, range.location + range.length <= storage.length else { return }
        let selectionLocation = storage.layoutManagers.first?.firstTextView?.selectedRange().location ?? NSNotFound
        guard !MermaidBlockLayout.selectionTouches(selectionLocation, blockRange: range) else { return }

        let attachment = storage.attribute(.mdMermaidAttachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        storage.beginEditing()
        applyClosedMermaidGeometry(to: storage, range: range, attachmentImageSize: attachment?.image?.size)
        storage.endEditing()

        for layoutManager in storage.layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
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
    /// `MarkdownLayoutManager.drawMermaidLineNumber`. La première ligne reçoit
    /// en plus `paragraphSpacingBefore` : l'espace où
    /// `MarkdownLayoutManager.drawMermaidHeader` peint l'étiquette `mermaid`
    /// et le bouton « Terminé ».
    private static func applyOpenMermaidGeometry(to storage: NSTextStorage, range: NSRange) {
        let ns = storage.string as NSString
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: range, in: ns)

        let firstLineStyle = NSMutableParagraphStyle()
        firstLineStyle.lineHeightMultiple = MermaidSourceLayout.lineHeightMultiple
        firstLineStyle.headIndent = MermaidSourceLayout.gutterWidth
        firstLineStyle.firstLineHeadIndent = MermaidSourceLayout.gutterWidth
        firstLineStyle.paragraphSpacingBefore = MermaidSourceLayout.headerHeight
        storage.addAttribute(.paragraphStyle, value: firstLineStyle, range: firstLine)

        if rest.length > 0 {
            let restStyle = NSMutableParagraphStyle()
            restStyle.lineHeightMultiple = MermaidSourceLayout.lineHeightMultiple
            restStyle.headIndent = MermaidSourceLayout.gutterWidth
            restStyle.firstLineHeadIndent = MermaidSourceLayout.gutterWidth
            storage.addAttribute(.paragraphStyle, value: restStyle, range: rest)
        }
    }

    private static func normalizedRenderRange(_ range: NSRange?, in storage: NSTextStorage) -> NSRange {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard let range else { return fullRange }

        let location = min(max(0, range.location), storage.length)
        let upperBound = min(max(location, range.location + range.length), storage.length)
        let clamped = NSRange(location: location, length: upperBound - location)
        let nsText = storage.string as NSString
        let lineRange = expandedForTable(nsText.lineRange(for: clamped), in: storage)
        return expandedForMermaidBlock(lineRange, in: storage)
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
