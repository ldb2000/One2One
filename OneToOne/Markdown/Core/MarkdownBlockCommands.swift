import AppKit

/// Change le type de bloc de la ligne portant le curseur, en mutant les
/// attributs du storage plutôt qu'en réécrivant du markdown littéral.
///
/// L'ancienne approche — insérer `## ` dans le texte puis tout reparser —
/// détruisait le gras, les liens et les images de la ligne : le storage ne
/// contient que du texte d'affichage, l'information de style vivant dans les
/// attributs, qu'un reparse du seul texte ne peut pas reconstituer.
enum MarkdownBlockCommands {

    /// Types de bloc atteignables par conversion d'une ligne existante.
    /// `.codeBlock` et `.thematicBreak` sont volontairement absents du type,
    /// pas seulement de la logique : les accepter ferait perdre l'inline de
    /// la ligne à la sérialisation. Mesuré :
    /// `MarkdownSerializer.fencedCodeBlock` émet `ns.substring(with:)` brut
    /// (le gras et les URLs d'image sont perdus, le placeholder `U+FFFC`
    /// survit tel quel), et `emitParagraph` renvoie `"---"` pour
    /// `.thematicBreak` sans jamais lire `inline` (la ligne entière est
    /// perdue). Les obtenir un jour restera possible, mais comme une
    /// opération d'**insertion** qui préserve l'inline — pas une conversion
    /// ligne à ligne comme celle-ci.
    enum LineBlockType {
        case paragraph, h1, h2, h3, h4, h5, h6, blockquote

        var blockType: BlockType {
            switch self {
            case .paragraph: return .paragraph
            case .h1: return .h1
            case .h2: return .h2
            case .h3: return .h3
            case .h4: return .h4
            case .h5: return .h5
            case .h6: return .h6
            case .blockquote: return .blockquote
            }
        }
    }

    /// Applique `type` à la ligne contenant `location`. Réappliquer le type
    /// déjà en place revient au paragraphe, ce qui rend le geste réversible
    /// — sauf si la ligne porte aussi une liste : dans ce cas le premier clic
    /// retire seulement la liste et garde le type, pour ne pas effacer les
    /// deux d'un coup. Le `.mdListInfo` éventuel est retiré : un titre n'est
    /// pas une liste. Ne fait rien si la ligne appartient à un bloc de code
    /// existant : scinder un bloc fencé par une conversion ligne à ligne
    /// n'est jamais ce que l'utilisateur veut, et c'est irréversible (mesuré :
    /// un titre appliqué à la ligne du milieu d'un bloc de trois lignes
    /// l'éclate en trois morceaux).
    static func setBlockType(_ type: LineBlockType, in storage: NSTextStorage, at location: Int) {
        let range = lineRange(in: storage, at: location)
        guard range.length > 0 else { return }

        let current = storage.attribute(.mdBlockType, at: range.location, effectiveRange: nil) as? BlockType
        guard current != .codeBlock else { return }
        let hasList = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) != nil
        let target: BlockType = (current == type.blockType && !hasList) ? .paragraph : type.blockType

        storage.beginEditing()
        storage.addAttribute(.mdBlockType, value: target, range: range)
        storage.removeAttribute(.mdListInfo, range: range)
        storage.removeAttribute(.mdCodeLanguage, range: range)
        storage.endEditing()
    }

    /// Applique une liste de type `kind` à la ligne contenant `location`.
    /// Réappliquer le même type revient au paragraphe. Le `.mdBlockType` est
    /// ramené à `.paragraph` : une liste n'est pas un titre. Ne fait rien si
    /// la ligne appartient à un bloc de code existant (même raison que
    /// `setBlockType`).
    static func setListKind(_ kind: ListInfo.Kind, in storage: NSTextStorage, at location: Int) {
        let range = lineRange(in: storage, at: location)
        guard range.length > 0 else { return }

        let currentBlockType = storage.attribute(.mdBlockType, at: range.location, effectiveRange: nil) as? BlockType
        guard currentBlockType != .codeBlock else { return }
        let current = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) as? ListInfo

        storage.beginEditing()
        storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: range)
        storage.removeAttribute(.mdCodeLanguage, range: range)
        if current?.kind == kind {
            storage.removeAttribute(.mdListInfo, range: range)
        } else {
            // `index` n'est pas fixé ici : `MarkdownSerializer.prefix(for:)`
            // retombe déjà sur 1 quand il est `nil`, et la numérotation
            // définitive d'une liste ordonnée est de toute façon établie par
            // le parser au reparse — pas par cette commande, qui ne pose
            // qu'un item à la fois et ne peut donc pas connaître son rang
            // parmi ses voisins.
            let info = ListInfo(kind: kind,
                                level: 0,
                                index: nil,
                                checked: kind == .task ? false : nil)
            storage.addAttribute(.mdListInfo, value: info, range: range)
        }
        storage.endEditing()
    }

    /// Plage de la ligne contenant `location`, **saut de ligne final exclu**.
    /// Ça n'a d'effet observable que sur `MarkdownSerializer.fencedCodeBlock`
    /// — seul chemin qui étend un run via `longestEffectiveRange` plutôt que
    /// de s'arrêter au premier `\n`, et seulement pour
    /// `.mdBlockType == .codeBlock` — donc aujourd'hui inatteignable depuis
    /// ces deux commandes : `LineBlockType` exclut `.codeBlock` et les deux
    /// gardes ci-dessus refusent d'opérer sur une ligne déjà `.codeBlock`.
    /// Conservé par défense en profondeur.
    ///
    /// `location` hors bornes est ramené à la première ou dernière ligne du
    /// storage plutôt que de crasher ou de ne rien faire : défendable pour
    /// une API pilotée par la position du curseur, qui peut légitimement
    /// déborder (ex. sélection vide juste après le dernier caractère).
    static func lineRange(in storage: NSTextStorage, at location: Int) -> NSRange {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let safe = min(max(0, location), ns.length)
        var range = ns.lineRange(for: NSRange(location: safe, length: 0))
        if range.length > 0, ns.character(at: range.location + range.length - 1) == 0x0A {
            range.length -= 1
        }
        return range
    }
}
