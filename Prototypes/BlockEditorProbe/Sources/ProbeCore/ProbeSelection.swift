import Foundation

/// Un point du document : un bloc, et un décalage **UTF-16** dans son texte.
public struct ProbePosition: Equatable, Hashable, Comparable {

    public var blockIndex: Int
    public var offset: Int

    public init(blockIndex: Int, offset: Int) {
        self.blockIndex = blockIndex
        self.offset = offset
    }

    public static func < (lhs: ProbePosition, rhs: ProbePosition) -> Bool {
        (lhs.blockIndex, lhs.offset) < (rhs.blockIndex, rhs.offset)
    }
}

/// Une sélection orientée : l'ancre est posée au `mouseDown` et ne bouge plus,
/// la tête suit le glissement ou les flèches. L'orientation compte pour
/// l'extension au clavier ; `start`/`end` la normalisent pour les mutations.
public struct ProbeSelection: Equatable {

    public var anchor: ProbePosition
    public var head: ProbePosition

    public init(anchor: ProbePosition, head: ProbePosition) {
        self.anchor = anchor
        self.head = head
    }

    public init(caret: ProbePosition) {
        self.anchor = caret
        self.head = caret
    }

    public var isCollapsed: Bool { anchor == head }
    public var start: ProbePosition { Swift.min(anchor, head) }
    public var end: ProbePosition { Swift.max(anchor, head) }

    /// Vrai si la sélection déborde d'un bloc. C'est le seul cas où le
    /// coordinateur reprend la main sur `NSTextView`.
    public var spansBlocks: Bool { start.blockIndex != end.blockIndex }
}
