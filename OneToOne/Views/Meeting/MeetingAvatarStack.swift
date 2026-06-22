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

/// Pile d'avatars superposés des participants ; au-delà de `max`, affiche une pastille « +N ».
struct MeetingAvatarStack: View {
    let participants: [Collaborator]
    /// Nombre maximal d'avatars affichés avant le badge de débordement « +N ».
    let max: Int
    /// Fournit la couleur de teinte de chaque collaborateur.
    let tint: (Collaborator) -> Color
    /// Couleur du liseré entourant chaque avatar.
    let borderColor: Color

    init(
        participants: [Collaborator],
        max: Int = 8,
        borderColor: Color = MeetingTheme.canvasCream,
        tint: @escaping (Collaborator) -> Color
    ) {
        self.participants = participants
        self.max = max
        self.borderColor = borderColor
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(participants.prefix(max).enumerated()), id: \.element.persistentModelID) { idx, p in
                AvatarCircle(collaborator: p, size: 26, tint: tint(p))
                    .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
                    .zIndex(Double(max - idx))
            }
            if participants.count > max {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.25))
                    Text("+\(participants.count - max)")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
            }
        }
    }
}

#Preview {
    let c1 = Collaborator(name: "Jimmy DUONG")
    let c2 = Collaborator(name: "Frederic NGUYEN")
    let c3 = Collaborator(name: "Manuel RIGAUT")
    return MeetingAvatarStack(
        participants: [c1, c2, c3],
        tint: { _ in .blue }
    )
    .padding()
    .background(MeetingTheme.canvasCream)
}
