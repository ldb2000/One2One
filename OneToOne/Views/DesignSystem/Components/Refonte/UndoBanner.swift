import SwiftUI

/// Bannière d'annulation d'un enregistrement optimiste : « Modifications
/// enregistrées · Annuler », visible cinq secondes (spec §4.3).
///
/// Pourquoi une primitive et non un bout de la fiche projet : l'enregistrement
/// optimiste est un motif de la refonte, pas une particularité du panneau. Les
/// lots 6 (épinglage), 10 (engagements) et 15 (rapport) en auront besoin, et
/// une seconde bannière écrite ailleurs finirait par ne plus durer cinq
/// secondes.
///
/// La bannière ne sait **rien** de ce qu'elle annule : `onUndo` restaure
/// l'instantané, `onExpire` la retire. Séparer les deux est ce qui permet de
/// tester la restauration sans session graphique.
struct UndoBanner: View {

    /// Durée de la fenêtre d'annulation, spec §4.3.
    static let duration: TimeInterval = 5

    static let defaultMessage = "Modifications enregistrées"

    let message: String
    let onUndo: () -> Void
    let onExpire: () -> Void

    @Environment(\.one2OneTheme) private var theme

    init(message: String = UndoBanner.defaultMessage,
         onUndo: @escaping () -> Void,
         onExpire: @escaping () -> Void) {
        self.message = message
        self.onUndo = onUndo
        self.onExpire = onExpire
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.ok)
            Text(message)
                .font(.plexSans(12))
                .foregroundStyle(theme.colors.ink2)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Annuler", action: onUndo)
                .buttonStyle(.plain)
                .font(.plexSans(11, .medium))
                .foregroundStyle(theme.colors.action)
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.vertical, One2OneToken.cardPaddingMin)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(theme.colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(theme.colors.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Annuler pendant \(Int(Self.duration)) secondes.")
        // `task` et non un `Timer` : la tâche est annulée avec la vue, donc
        // l'expiration ne peut pas survenir après la fermeture du panneau.
        .task {
            try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onExpire()
        }
    }
}

#Preview("UndoBanner") {
    VStack(spacing: One2OneToken.cardGap) {
        UndoBanner(onUndo: {}, onExpire: {})
        UndoBanner(message: "Jalon supprimé", onUndo: {}, onExpire: {})
    }
    .frame(width: 404)
    .padding(20)
    .background(One2OneToken.bgCanvas)
}
