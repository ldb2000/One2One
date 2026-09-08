import SwiftUI

/// Pastille ronde d'un collaborateur : sa photo si disponible, sinon ses
/// initiales sur fond teinté.
struct AvatarCircle: View {
    let collaborator: Collaborator
    /// Diamètre de la pastille en points.
    let size: CGFloat
    /// Couleur de fond de la pastille (fallback initiales).
    let tint: Color

    var body: some View {
        Group {
            if let url = collaborator.photoURL(),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(tint)
                    Text(initials(for: collaborator.name))
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Calcule jusqu'à deux initiales en majuscules à partir des deux premiers mots du nom.
    private func initials(for name: String) -> String {
        let parts = name
            .split(whereSeparator: { !$0.isLetter })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

/// Variante compacte d'`AvatarCircle` (18 pt) pour les listes denses.
struct AvatarMini: View {
    let collaborator: Collaborator
    let tint: Color
    var body: some View {
        AvatarCircle(collaborator: collaborator, size: 18, tint: tint)
    }
}
