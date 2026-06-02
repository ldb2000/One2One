import SwiftUI

/// Layout en « flot » (type tags / chips) : place les sous-vues de gauche à
/// droite et passe à la ligne suivante dès que la largeur disponible est
/// dépassée. Utile pour des collections d'éléments de taille variable.
struct FlowLayout: Layout {
    /// Écart appliqué à la fois entre deux éléments d'une même ligne
    /// (horizontal) et entre deux lignes (vertical).
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    /// Cœur de l'algorithme : parcourt les sous-vues une fois, accumule la
    /// position de chacune et passe à la ligne quand l'élément déborderait de
    /// `width` (sauf en début de ligne). Renvoie la taille totale occupée et la
    /// position de chaque sous-vue, réutilisé tel quel par `sizeThatFits` et
    /// `placeSubviews`.
    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, maxH: CGFloat = 0, maxW: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > width && x > 0 {
                x = 0; y += maxH + spacing; maxH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxH = max(maxH, sz.height)
            x += sz.width + spacing
            maxW = max(maxW, x)
        }
        return (CGSize(width: maxW, height: y + maxH), positions)
    }
}
