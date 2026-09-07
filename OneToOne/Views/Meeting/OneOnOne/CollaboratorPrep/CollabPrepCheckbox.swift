import SwiftUI

/// La case à cocher violette des deux blocs cochables de la capture 5b :
/// vide dans `RESTÉ SANS RÉPONSE`, cochée dans `CE QUE JE VEUX OBTENIR`.
///
/// Dessinée et non `Toggle` : la capture montre un carré de 15 px à bord
/// violet, là où un `Toggle(.checkbox)` de macOS rend une case système bleue
/// que rien ne permet de reteindre. Et `Button` plutôt que `onTapGesture` :
/// la ligne doit rester atteignable au clavier.
struct CollabPrepCheckbox: View {

    static let size: CGFloat = 15
    static let corner: CGFloat = 3.5

    let isOn: Bool
    let help: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(isOn ? One2OneToken.oneOnOne : One2OneToken.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .strokeBorder(One2OneToken.oneOnOne, lineWidth: 1.4)
                }
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(One2OneToken.onFilledButton)
                    }
                }
                .frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview("CollabPrepCheckbox") {
    HStack(spacing: 12) {
        CollabPrepCheckbox(isOn: false, help: "Cocher") {}
        CollabPrepCheckbox(isOn: true, help: "Décocher") {}
    }
    .padding(20)
    .background(One2OneToken.surface)
}
