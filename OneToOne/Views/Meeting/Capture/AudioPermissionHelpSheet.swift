// OneToOne/Views/Meeting/Capture/AudioPermissionHelpSheet.swift
import SwiftUI

/// « Refus d'autorisation microphone / audio système » (spec §1, ligne 4) :
/// explique, ouvre le bon volet des Réglages Système, donne le chemin manuel
/// si l'ouverture échoue. Même patron que `refusDAutorisation` du sélecteur
/// de capture.
struct AudioPermissionHelpSheet: View {

    let kind: AudioPermissionKind
    let onClose: () -> Void

    @State private var ouvertureEchouee = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.title)
                .font(.plexSans(17, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text(kind.explanation)
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pour autoriser OneToOne :")
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.warnInk)
                Text(kind.manualPath)
                    .font(.plexMono(11.5))
                    .foregroundStyle(One2OneToken.ink2)
                Text("Cochez OneToOne dans la liste, puis relancez l'enregistrement.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                if ouvertureEchouee {
                    Text("Les Réglages Système n'ont pas pu être ouverts automatiquement : suivez le chemin ci-dessus.")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.warnInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(One2OneToken.warnBg))

            HStack {
                Button("Fermer", action: onClose)
                    .buttonStyle(.plain)
                    .font(.plexSans(12.5, .medium))
                    .foregroundStyle(One2OneToken.ink3)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ouvrir les Réglages Système…") {
                    ouvertureEchouee = !kind.openSettings()
                }
                .buttonStyle(CapturePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(One2OneToken.surface)
    }
}
