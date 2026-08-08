import AppKit
import ProbeCore

/// Empile un `BlockTextView` par bloc, à disposition **manuelle**.
///
/// Ni `NSStackView` ni Auto Layout : à 200 blocs on veut mesurer le coût des
/// vues éditables, pas celui du moteur de contraintes.
final class BlockStackView: NSView {

    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 24
    static let blockSpacing: CGFloat = 8

    private unowned let coordinator: SelectionCoordinator

    /// Vues dans l'ordre du document.
    private(set) var orderedViews: [BlockTextView] = []
    /// Réemploi par identité de bloc : un bloc qui survit à une mutation garde
    /// sa vue, donc son curseur et son état de saisie.
    private var viewsByIdentity: [UUID: BlockTextView] = [:]

    init(coordinator: SelectionCoordinator) {
        self.coordinator = coordinator
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    override var isFlipped: Bool { true }

    // MARK: - Synchronisation avec le document

    /// Reconstruit la liste des vues à partir du document, en réutilisant
    /// celles dont le bloc a survécu.
    func reload(document: ProbeDocument) {
        var reused: [UUID: BlockTextView] = [:]
        var ordered: [BlockTextView] = []

        for (index, block) in document.blocks.enumerated() {
            let view = viewsByIdentity[block.id] ?? BlockTextView(owner: coordinator)
            view.blockIndex = index
            if view.string != block.text {
                view.string = block.text
            }
            if view.superview !== self {
                addSubview(view)
            }
            reused[block.id] = view
            ordered.append(view)
        }

        for (identity, view) in viewsByIdentity where reused[identity] == nil {
            view.removeFromSuperview()
        }

        viewsByIdentity = reused
        orderedViews = ordered
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func view(at index: Int) -> BlockTextView? {
        orderedViews.indices.contains(index) ? orderedViews[index] : nil
    }

    /// Bloc situé sous un point exprimé dans les coordonnées de cette vue.
    /// Au-dessus du premier bloc renvoie 0, en dessous du dernier renvoie le
    /// dernier : c'est ce qui rend un glissement au-delà des bords utilisable.
    func blockIndex(atContentPoint point: NSPoint) -> Int? {
        guard !orderedViews.isEmpty else { return nil }
        if point.y <= orderedViews[0].frame.minY { return 0 }
        for (index, view) in orderedViews.enumerated() where point.y <= view.frame.maxY {
            return index
        }
        return orderedViews.count - 1
    }

    // MARK: - Disposition

    override func layout() {
        super.layout()

        let contentWidth = max(bounds.width - Self.horizontalInset * 2, 40)
        var y = Self.verticalInset

        for view in orderedViews {
            let height = view.measuredHeight(forWidth: contentWidth)
            view.frame = NSRect(x: Self.horizontalInset, y: y, width: contentWidth, height: height)
            y += height + Self.blockSpacing
        }

        let neededHeight = y - Self.blockSpacing + Self.verticalInset
        if abs(frame.height - neededHeight) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: neededHeight))
        }
    }
}
