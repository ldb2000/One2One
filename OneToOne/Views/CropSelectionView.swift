import CoreGraphics
import SwiftUI

/// Aperçu de la fenêtre source sur lequel l'utilisateur trace la zone du slide.
///
/// Astuce de coordonnées : le `GeometryReader` porte lui-même le ratio de l'image, donc
/// `geometry.size` **est** la taille d'affichage de l'image. Aucun décalage aspect-fit à
/// calculer ; les coordonnées du glissement se convertissent directement en fractions.
/// Si ce modificateur était mal placé, tous les tracés seraient décalés du même offset,
/// erreur invisible au centre de l'image.
struct CropSelectionView: View {
    let image: CGImage
    @Binding var rect: NormalizedRect
    /// Vrai pendant une session : le geste reste reconnu mais ne modifie plus `rect`.
    var isLocked: Bool = false

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private var aspectRatio: CGFloat {
        guard image.height > 0 else { return 16 / 9 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    var body: some View {
        GeometryReader { geometry in
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay { selectionOverlay(in: geometry.size) }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(isLocked ? 0.85 : 1)
    }

    /// La zone retenue reste nette, tout ce qui l'entoure est assombri.
    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        let displayed = displayedRect(in: size)
        ZStack {
            Color.black.opacity(0.45)
                .reverseMask { Rectangle().path(in: displayed).fill(style: FillStyle()) }
            Rectangle()
                .path(in: displayed)
                .stroke(isLocked ? Color.secondary : Color.accentColor, lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    /// Le glissement en cours s'il y en a un, sinon la zone retenue.
    private func displayedRect(in size: CGSize) -> CGRect {
        if let start = dragStart, let current = dragCurrent {
            return CGRect(
                x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y)
            )
        }
        return rect.displayRect(in: size)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !isLocked else { return }
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil }
                guard !isLocked else { return }
                rect = NormalizedRect.fromDrag(from: value.startLocation, to: value.location, in: size, current: rect)
            }
    }
}

private extension View {
    /// Découpe un trou dans la vue à l'endroit du masque.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
