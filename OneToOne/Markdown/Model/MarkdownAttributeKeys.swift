import Foundation
import AppKit

/// Custom `NSAttributedString.Key`s used by the WYSIWYG markdown editor.
/// Keep names prefixed with `md` so they cannot clash with AppKit defaults.
public extension NSAttributedString.Key {
    static let mdBold          = NSAttributedString.Key("mdBold")
    static let mdItalic        = NSAttributedString.Key("mdItalic")
    static let mdInlineCode    = NSAttributedString.Key("mdInlineCode")
    static let mdStrikethrough = NSAttributedString.Key("mdStrikethrough")
    /// Value: `URL`
    static let mdLink          = NSAttributedString.Key("mdLink")
    /// Value: `BlockType`
    static let mdBlockType     = NSAttributedString.Key("mdBlockType")
    /// Value: `ListInfo`
    static let mdListInfo      = NSAttributedString.Key("mdListInfo")
    /// Value: `String` — the info-string of a fenced code block, used as the
    /// language hint after the opening ``` fence (e.g. "swift", "json"). Empty
    /// or absent means an unlabelled fence.
    static let mdCodeLanguage  = NSAttributedString.Key("mdCodeLanguage")
    /// Value: `URL` — destination d'une image inline. Portée par l'unique
    /// caractère `U+FFFC` qui représente l'image dans le texte.
    static let mdImageURL      = NSAttributedString.Key("mdImageURL")
    /// Value: `String` — texte alternatif de l'image, réémis entre crochets.
    static let mdImageAlt      = NSAttributedString.Key("mdImageAlt")
    /// Value: `TableCellInfo`. Marque un paragraphe comme une cellule d'un
    /// tableau GFM — posé sur **tout** le texte de la cellule, retour à la
    /// ligne terminal inclus (contrairement à `mdBlockType`, qui exclut ce
    /// `\n` : une cellule vide n'a alors aucun autre caractère pour porter
    /// l'attribut). Volontairement séparé de `mdBlockType` plutôt que d'y
    /// ajouter un cas `.tableCell` : `BlockType` est un `enum` non-Codable-
    /// par-défaut avec des `switch` exhaustifs dans `OneToOne/Markdown/Slash/`
    /// (zone hors périmètre de cette tâche), qu'un nouveau cas casserait à la
    /// compilation. Voir `MarkdownParser.emitTable` / `MarkdownSerializer`
    /// (fonction `tableBlock`) / `StyleRenderer` (construction de
    /// `NSTextTable`/`NSTextTableBlock`).
    static let mdTableCell     = NSAttributedString.Key("mdTableCell")
    /// Value: `NSTextAttachment` — diagramme mermaid rendu pour un bloc de
    /// code dont `.mdCodeLanguage == "mermaid"`. Posé **en plus** de
    /// `.mdBlockType`/`.mdCodeLanguage` sur la même plage, jamais à leur
    /// place : purement une métadonnée d'affichage lue par
    /// `MarkdownLayoutManager` pour peindre le diagramme par-dessus le texte
    /// source quand le curseur n'y est pas (voir `drawMermaidDiagrams`) — le
    /// texte source reste le seul contenu réellement stocké, voir
    /// `StyleRenderer.applyMermaidAttachment`.
    static let mdMermaidAttachment = NSAttributedString.Key("mdMermaidAttachment")
}

/// Block-level kind applied to a whole paragraph range.
/// `paragraph` is the default body text; `h1`-`h6` are heading levels;
/// `blockquote` is a `>` quote; `codeBlock` is a fenced block whose language is
/// carried by `mdCodeLanguage`; `thematicBreak` is a horizontal rule (`---`).
public enum BlockType: String, Codable, Hashable {
    case paragraph
    case h1, h2, h3, h4, h5, h6
    case blockquote
    case codeBlock
    case thematicBreak
    /// Bloc dont ce module ne modélise pas la structure (tableau GFM, bloc
    /// HTML brut…). Le run porte le **markdown source littéral** du bloc,
    /// réémis tel quel à la sérialisation sans être réinterprété — même
    /// mécanisme de passthrough que `codeBlock`, voir
    /// `MarkdownParser.emitRawBlock` / `MarkdownSerializer.rawBlock(in:at:ns:)`.
    /// Garantit que le contenu survive même quand rien ne sait l'afficher
    /// finement (rendu en texte brut monospace).
    case rawBlock
}

/// Metadata attached to list items.
public struct ListInfo: Codable, Hashable {
    public enum Kind: String, Codable { case bullet, ordered, task }
    public let kind: Kind
    public let level: Int        // nesting depth, 0-based
    /// 1-based ordinal — relevant only when `kind == .ordered`; ignored otherwise.
    public let index: Int?
    /// Checkbox state — relevant only when `kind == .task`; ignored otherwise.
    public let checked: Bool?

    /// Creates list metadata. `index` is meaningful only for `.ordered` items
    /// and `checked` only for `.task` items; both should be left `nil` for the
    /// kinds they don't apply to.
    public init(kind: Kind, level: Int = 0, index: Int? = nil, checked: Bool? = nil) {
        self.kind = kind
        self.level = level
        self.index = index
        self.checked = checked
    }
}

/// Metadata attached to a table-cell paragraph (`.mdTableCell`). One value
/// per cell — `row`/`column` are 0-based and absolute within the table
/// (`row == 0` is the GFM header row, `row >= 1` is a body row), matching
/// directly `NSTextTableBlock(startingRow:startingColumn:)` — see
/// `StyleRenderer`. `tableID` groups every cell of the same logical table:
/// consecutive cell paragraphs sharing it are one table, read back that way
/// by `MarkdownSerializer`.
public struct TableCellInfo: Codable, Hashable {
    /// Alignement GFM d'une colonne. Distinct de `NSTextAlignment` : porte
    /// aussi l'absence d'alignement explicite (`nil` sur la propriété
    /// `alignment` ci-dessous, réémis en séparateur `---` sans `:`), que
    /// `NSTextAlignment` ne sait pas représenter (son `.natural` n'est pas
    /// «pas de colonne prononcée dans le GFM source», c'est un réglage
    /// d'affichage) — cf. `MarkdownSerializer.alignmentMarker`.
    public enum Alignment: String, Codable, Hashable {
        case left, center, right
    }

    public let tableID: UUID
    public let row: Int
    public let column: Int
    /// Nombre de colonnes de la table entière — constant sur toutes les
    /// cellules d'une même `tableID`, dupliqué sur chacune pour que
    /// `StyleRenderer` puisse construire `NSTextTable.numberOfColumns` sans
    /// avoir à consulter une autre cellule.
    public let columnCount: Int
    /// `nil` = pas de `:` dans le séparateur GFM de cette colonne (alignement
    /// par défaut du moteur de rendu, pas nécessairement gauche).
    public let alignment: Alignment?

    public init(tableID: UUID, row: Int, column: Int, columnCount: Int, alignment: Alignment?) {
        self.tableID = tableID
        self.row = row
        self.column = column
        self.columnCount = columnCount
        self.alignment = alignment
    }
}
