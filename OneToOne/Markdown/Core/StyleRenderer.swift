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
                applyMermaidAttachment(to: storage, range: range)
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
    /// et réserve une hauteur de ligne minimale (`MermaidBlockLayout`) pour
    /// que `MarkdownLayoutManager.drawMermaidDiagrams` ait la place d'y
    /// inscrire le diagramme. Le rendu proprement dit est asynchrone (voir
    /// `MermaidRenderer`) : `onUpdate` ne fait qu'invalider l'**affichage**
    /// des `NSLayoutManager` attachés à `storage` une fois l'attachment mis à
    /// jour en place — jamais le storage, jamais une re-sérialisation, jamais
    /// une pile d'annulation (voir `MermaidAttachmentFactoryTests`).
    private static func applyMermaidAttachment(to storage: NSTextStorage, range: NSRange) {
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
        let attachment = MainActor.assumeIsolated {
            MermaidAttachmentFactory.attachment(for: source, isDark: isDark) {
                for layoutManager in storage.layoutManagers {
                    layoutManager.invalidateDisplay(forCharacterRange: range)
                }
            }
        }
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: range)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = MermaidBlockLayout.minimumLineHeight(
            forLineCount: MermaidBlockLayout.lineCount(in: source)
        )
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }

    private static func normalizedRenderRange(_ range: NSRange?, in storage: NSTextStorage) -> NSRange {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard let range else { return fullRange }

        let location = min(max(0, range.location), storage.length)
        let upperBound = min(max(location, range.location + range.length), storage.length)
        let clamped = NSRange(location: location, length: upperBound - location)
        let nsText = storage.string as NSString
        return expandedForTable(nsText.lineRange(for: clamped), in: storage)
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
