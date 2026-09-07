import SwiftUI

/// Le sélecteur de source de capture, 346 px (spec §5.1, capture
/// `4a-capture-selecteur.png`) : `Que capturer ? ⌘⇧S`, les lignes de source,
/// les deux bascules, la mention de confiance, `Capturer maintenant`.
///
/// Reprise de `TeamsCapture/Cockpit/SourcePopover.swift` pour la mise en page
/// (vignette 44 × 30, libellé, sous-titre, point `accent/ok`, bordure
/// `accent/action` sur la sélection, bouton primaire plein) ; les modèles et
/// les décisions sont ceux de OneToOne (`CaptureSourceCatalog`, `CaptureState`).
///
/// Remplace `ScreenCaptureConfigView`, qui demandait une fenêtre, une zone et
/// une sensibilité avant de laisser capturer quoi que ce soit.
struct CaptureSourcePopover: View {

    let coordinator: CaptureSessionCoordinator
    @ObservedObject var service: ScreenCaptureService

    private var state: CaptureState { coordinator.screen.capture }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete

            if state.permissionDenied {
                refusDAutorisation
            } else if let erreur = state.catalogError {
                message(erreur, ton: .warn)
            }

            VStack(spacing: 6) {
                ForEach(state.options) { option in
                    ligne(option)
                }
            }

            Divider().overlay(One2OneToken.hair)

            bascules

            Text("Rien n'est envoyé à Teams ou Zoom : One2One lit la fenêtre, comme une capture système.")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let panne = service.lastError {
                message(panne, ton: .warn)
            }

            Button("Capturer maintenant") {
                Task { await coordinator.captureNow() }
            }
            .buttonStyle(CapturePrimaryButtonStyle())
            .disabled(state.selected == nil && !state.options.contains(where: \.isActive))
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: One2OneToken.capturePopoverWidth)
        .background(One2OneToken.surface)
        .task { await coordinator.refreshOptions() }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 8) {
            SectionLabel("Que capturer ?")
            Spacer(minLength: 0)
            Text("⌘⇧S")
                .font(.plexMono(9.5, .medium))
                .foregroundStyle(One2OneToken.ink4)
            if state.isLoadingOptions {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// Le refus d'autorisation **remplace** la liste par une explication et un
    /// lien : sans permission, aucune ligne de source ne dirait la vérité.
    /// Jamais de boîte de dialogue en séance (spec §5.2).
    private var refusDAutorisation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OneToOne n'a pas l'autorisation d'enregistrer l'écran.")
                .font(.plexSans(12, .medium))
                .foregroundStyle(One2OneToken.warnInk)
            Button("Ouvrir les Réglages système…") {
                _ = ScreenRecordingSettingsLink.open()
            }
            .buttonStyle(.plain)
            .font(.plexSans(11.5, .medium))
            .foregroundStyle(One2OneToken.actionInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(One2OneToken.warnBg))
    }

    private func message(_ texte: String, ton: ChipTon) -> some View {
        Text(texte)
            .font(.plexSans(11.5))
            .foregroundStyle(ton.encre)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(ton.fond))
    }

    // MARK: - Une source

    private func ligne(_ option: CaptureSourceOption) -> some View {
        let choisie = state.selected?.source == option.source
        return Button {
            Task { await coordinator.select(option) }
        } label: {
            HStack(spacing: 10) {
                Text(option.badge)
                    .font(.plexMono(9, .semibold))
                    .foregroundStyle(One2OneToken.actionInk)
                    .frame(width: 44, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                            .fill(One2OneToken.actionBg))

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.plexSans(12, .medium))
                        .foregroundStyle(One2OneToken.ink1)
                        .lineLimit(1)
                    Text(option.subtitle)
                        .font(.plexSans(11))
                        .foregroundStyle(One2OneToken.ink4)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if option.isActive {
                    Circle().fill(One2OneToken.ok).frame(width: 6, height: 6)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                    .fill(choisie ? One2OneToken.actionBg2 : One2OneToken.surfaceAlt))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                    .strokeBorder(choisie ? One2OneToken.action : One2OneToken.cardBorder,
                                  lineWidth: choisie ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.subtitle)
    }

    // MARK: - Bascules

    @ViewBuilder
    private var bascules: some View {
        let indisponible = CaptureState.automaticUnavailableReason(for: state.selected)

        Toggle(isOn: Binding(get: { state.detectsAutomatically },
                             set: { coordinator.setAutomaticDetection($0) })) {
            Text("Capturer à chaque changement de partage")
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(indisponible != nil)

        // Spec §5.1 : « une source inactive rend la première bascule
        // indisponible **avec l'explication** ». Un contrôle grisé sans raison
        // est le défaut « contrôle sans effet » de `One2One-specs.md`.
        if let indisponible {
            Text(indisponible)
                .font(.plexSans(11))
                .foregroundStyle(One2OneToken.warnInk)
                .fixedSize(horizontal: false, vertical: true)
        }

        Toggle(isOn: Binding(get: { state.periodicCapture != nil },
                             set: { coordinator.setPeriodicCapture($0) })) {
            Text("Toutes les 2 minutes")
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)

        Text(coordinator.meeting.kind.captureHint)
            .font(.plexSans(11))
            .foregroundStyle(One2OneToken.ink4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Bouton primaire de la conception : fond plein `accent/action`, texte blanc,
/// rayon 6 (copie de `PrimaryButtonStyle` de Teams-Capture).
struct CapturePrimaryButtonStyle: ButtonStyle {
    var tint: Color = One2OneToken.action

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plexSans(12, .medium))
            .foregroundStyle(One2OneToken.onFilledButton)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                    .fill(tint.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}
