import Foundation

/// Le document de la sonde : une **liste plate** de blocs. Pas d'arbre, pas de
/// types. Toutes les mutations structurantes passent par `replace`.
public struct ProbeDocument: Equatable {

    public private(set) var blocks: [ProbeBlock]

    /// Un document n'est jamais vide : il contient au minimum un bloc vide.
    public init(blocks: [ProbeBlock]) {
        self.blocks = blocks.isEmpty ? [ProbeBlock(text: "")] : blocks
    }

    public init(texts: [String]) {
        self.init(blocks: texts.map { ProbeBlock(text: $0) })
    }

    // MARK: - L'unique mutation structurante

    /// Remplace la plage couverte par `selection` par `text`, en scindant sur
    /// les sauts de ligne, et retourne la position du curseur après le texte
    /// inséré.
    ///
    /// Les quatre gestes destructifs de la sonde s'y ramènent :
    /// - frappe sur une sélection multi-blocs → `replace(selection, with: "a")` ;
    /// - ⏎ → `replace(caret, with: "\n")` ;
    /// - ⌫ en tête de bloc → `replace(fin du précédent … début du courant, with: "")` ;
    /// - collage → `replace(selection, with: pasteboard)`.
    ///
    /// L'identité du **premier** bloc touché est conservée : la pile de vues
    /// réutilise alors son `NSTextView` au lieu de le reconstruire.
    @discardableResult
    public mutating func replace(_ selection: ProbeSelection, with text: String) -> ProbePosition {
        let start = clamped(selection.start)
        let end = clamped(selection.end)

        let head = (blocks[start.blockIndex].text as NSString).substring(to: start.offset)
        let tail = (blocks[end.blockIndex].text as NSString).substring(from: end.offset)
        let pieces = text.components(separatedBy: "\n")
        let keptIdentity = blocks[start.blockIndex].id

        let replacement: [ProbeBlock]
        let caret: ProbePosition

        if pieces.count == 1 {
            replacement = [ProbeBlock(id: keptIdentity, text: head + pieces[0] + tail)]
            caret = ProbePosition(
                blockIndex: start.blockIndex,
                offset: (head as NSString).length + (pieces[0] as NSString).length)
        } else {
            var built = [ProbeBlock(id: keptIdentity, text: head + pieces[0])]
            for piece in pieces[1..<(pieces.count - 1)] {
                built.append(ProbeBlock(text: piece))
            }
            let last = pieces[pieces.count - 1]
            built.append(ProbeBlock(text: last + tail))
            replacement = built
            caret = ProbePosition(
                blockIndex: start.blockIndex + pieces.count - 1,
                offset: (last as NSString).length)
        }

        blocks.replaceSubrange(start.blockIndex...end.blockIndex, with: replacement)
        return caret
    }

    // MARK: - Bornes

    /// Ramène une position dans les bornes du document. Protège des positions
    /// périmées après une mutation venue de la vue.
    public func clamped(_ position: ProbePosition) -> ProbePosition {
        let index = Swift.min(Swift.max(position.blockIndex, 0), blocks.count - 1)
        let offset = Swift.min(Swift.max(position.offset, 0), blocks[index].length)
        return ProbePosition(blockIndex: index, offset: offset)
    }
}
