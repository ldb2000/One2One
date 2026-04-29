import SwiftUI

struct AvatarCircle: View {
    let collaborator: Collaborator
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Text(initials(for: collaborator.name))
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(whereSeparator: { !$0.isLetter })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

struct AvatarMini: View {
    let collaborator: Collaborator
    let tint: Color
    var body: some View {
        AvatarCircle(collaborator: collaborator, size: 18, tint: tint)
    }
}

struct MeetingAvatarStack: View {
    let participants: [Collaborator]
    let max: Int
    let tint: (Collaborator) -> Color
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
