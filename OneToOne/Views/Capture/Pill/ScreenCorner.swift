import CoreGraphics

/// Un coin d'écran, pour la magnétisation de la pastille flottante (spec §5.4).
///
/// C'est le **coin** qui est mémorisé, jamais la position en pixels : un changement de
/// résolution ou le débranchement d'un écran externe replacerait sinon la pastille hors
/// champ, sans aucun moyen de la récupérer.
///
/// Coordonnées AppKit : l'origine est en **bas à gauche**, `y` croît vers le haut — ce
/// n'est pas la convention de `NormalizedRect`, qui parle d'images.
///
/// Copié de `Teams-Capture/Sources/CaptureDesign/ScreenCorner.swift` avec ses tests
/// (programme §2.5 : copier, jamais lier).
enum ScreenCorner: String, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    /// Le coin le plus proche d'un point — celui du centre du panneau relâché.
    static func nearest(to point: CGPoint, in frame: CGRect) -> ScreenCorner {
        let isTop = point.y > frame.midY
        let isTrailing = point.x > frame.midX
        switch (isTop, isTrailing) {
        case (true, true): return .topTrailing
        case (true, false): return .topLeading
        case (false, true): return .bottomTrailing
        case (false, false): return .bottomLeading
        }
    }

    /// Origine de la fenêtre pour se poser dans ce coin, marge comprise.
    ///
    /// Bornée aux limites du cadre : sur un écran plus petit que la pastille, mieux vaut
    /// une pastille qui dépasse d'un bord qu'une pastille placée hors de l'écran.
    func origin(for size: CGSize, in frame: CGRect, inset: CGFloat) -> CGPoint {
        let maxX = max(frame.minX, frame.maxX - size.width - inset)
        let maxY = max(frame.minY, frame.maxY - size.height - inset)
        let minX = min(frame.minX + inset, maxX)
        let minY = min(frame.minY + inset, maxY)

        switch self {
        case .topLeading: return CGPoint(x: minX, y: maxY)
        case .topTrailing: return CGPoint(x: maxX, y: maxY)
        case .bottomLeading: return CGPoint(x: minX, y: minY)
        case .bottomTrailing: return CGPoint(x: maxX, y: minY)
        }
    }
}
