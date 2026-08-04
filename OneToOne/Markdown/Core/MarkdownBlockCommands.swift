import AppKit

/// Change le type de bloc de la ligne portant le curseur, en mutant les
/// attributs du storage plutôt qu'en réécrivant du markdown littéral.
///
/// L'ancienne approche — insérer `## ` dans le texte puis tout reparser —
/// détruisait le gras, les liens et les images de la ligne : le storage ne
/// contient que du texte d'affichage, l'information de style vivant dans les
/// attributs, qu'un reparse du seul texte ne peut pas reconstituer.
enum MarkdownBlockCommands {

    /// Applique `type` à la ligne contenant `location`. Réappliquer le type
    /// déjà en place revient au paragraphe, ce qui rend le geste réversible.
    /// Le `.mdListInfo` éventuel est retiré : un titre n'est pas une liste.
    static func setBlockType(_ type: BlockType, in storage: NSTextStorage, at location: Int) {
        let range = lineRange(in: storage, at: location)
        guard range.length > 0 else { return }

        let current = storage.attribute(.mdBlockType, at: range.location, effectiveRange: nil) as? BlockType
        let hasList = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) != nil
        let target: BlockType = (current == type && !hasList) ? .paragraph : type

        storage.beginEditing()
        storage.addAttribute(.mdBlockType, value: target, range: range)
        storage.removeAttribute(.mdListInfo, range: range)
        storage.endEditing()
    }

    /// Applique une liste de type `kind` à la ligne contenant `location`.
    /// Réappliquer le même type revient au paragraphe. Le `.mdBlockType` est
    /// ramené à `.paragraph` : une liste n'est pas un titre.
    static func setListKind(_ kind: ListInfo.Kind, in storage: NSTextStorage, at location: Int) {
        let range = lineRange(in: storage, at: location)
        guard range.length > 0 else { return }

        let current = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) as? ListInfo

        storage.beginEditing()
        storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: range)
        if current?.kind == kind {
            storage.removeAttribute(.mdListInfo, range: range)
        } else {
            let info = ListInfo(kind: kind,
                                level: 0,
                                index: kind == .ordered ? 1 : nil,
                                checked: kind == .task ? false : nil)
            storage.addAttribute(.mdListInfo, value: info, range: range)
        }
        storage.endEditing()
    }

    /// Plage de la ligne contenant `location`, **saut de ligne final exclu** :
    /// l'inclure ferait porter l'attribut de bloc au séparateur, que le
    /// sérialiseur traite comme la frontière entre deux paragraphes.
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
