import CoreGraphics
import Foundation

/// La géométrie du tracé « zone à la souris » (spec §5.1, source `Zone à la souris`).
///
/// Pure et hors de la fenêtre : `RegionSelectorWindow` n'est qu'un capteur de souris,
/// et une règle de cadrage qui vivrait dans un `NSPanel` ne serait testable qu'à la
/// main, sur un bureau — ce que la consigne du lot interdit.
enum RegionSelection {

    /// Sous cette fraction d'un côté, le tracé est un clic manqué et non une zone.
    ///
    /// 2 % : sur un écran de 1 920 px, 38 px. Plus haut, on refuserait de vraies petites
    /// zones (une cellule de tableau) ; plus bas, un simple clic ouvrirait une session
    /// sur quelques pixels, et chaque capture serait un carré illisible.
    static let minimumFraction: Double = 0.02

    /// Le rectangle **dessiné** pendant le glissement, dans les coordonnées de la vue.
    /// L'ordre des points est indifférent : on peut tracer de bas à droite vers le haut
    /// à gauche.
    static func drawnRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }

    /// La zone retenue, en fraction de l'écran (origine **haut-gauche**, convention de
    /// `NormalizedRect`), ou `nil` quand le tracé est trop petit pour être une zone.
    static func normalized(from start: CGPoint,
                           to end: CGPoint,
                           in size: CGSize,
                           minimumFraction: Double = minimumFraction) -> NormalizedRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let candidate = NormalizedRect(from: start, to: end, in: size)
        guard candidate.width >= minimumFraction, candidate.height >= minimumFraction else {
            return nil
        }
        return candidate
    }
}
