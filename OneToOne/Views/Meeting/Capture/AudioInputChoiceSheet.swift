// OneToOne/Views/Meeting/Capture/AudioInputChoiceSheet.swift
import SwiftUI

/// « Micro de pré-réunion indisponible » (spec §1, ligne 1) : le micro préféré
/// n'est pas branché, voici les sources détectées. Le choix vaut pour cette
/// réunion seulement (D2). Mise en page reprise du sélecteur de capture :
/// lignes à sous-titre, bouton primaire plein, jetons `One2OneToken`.
struct AudioInputChoiceSheet: View {

    let request: AudioInputChoiceRequest
    let onUse: (AudioInputDevice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Micro indisponible")
                .font(.plexSans(17, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("Le micro préféré n'est pas branché. Choisissez une autre source pour cette réunion ; le réglage n'est pas modifié.")
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(request.candidates) { device in
                    ligne(device)
                }
            }

            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.plexSans(12.5, .medium))
                    .foregroundStyle(One2OneToken.ink3)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(One2OneToken.surface)
    }

    private func ligne(_ device: AudioInputDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.isBuiltIn ? "laptopcomputer" : "mic")
                .font(.plexSans(13))
                .foregroundStyle(One2OneToken.ink3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.plexSans(13, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                Text(sousTitre(device))
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
            Spacer()
            Button("Utiliser") { onUse(device) }
                .buttonStyle(CapturePrimaryButtonStyle())
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(One2OneToken.surfaceAlt))
        .overlay(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).stroke(One2OneToken.cardBorder))
    }

    private func sousTitre(_ device: AudioInputDevice) -> String {
        switch (device.isBuiltIn, device.isSystemDefault) {
        case (true, true): return "Micro intégré · entrée par défaut du système"
        case (true, false): return "Micro intégré"
        case (false, true): return "Entrée par défaut du système"
        case (false, false): return "Entrée externe"
        }
    }
}
