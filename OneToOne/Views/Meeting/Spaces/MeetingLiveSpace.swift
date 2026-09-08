import SwiftUI

/// Le mode En séance de l'espace Réunion : « Notes ↔ transcription à parts
/// égales, KPI condensés en bandeau » (spec §2.2).
///
/// Une seule carte, `grid-template-columns: 1fr 1px 1fr` (spec §2.4), en-tête
/// « Notes & transcription · synchronisées sur l'audio » avec la bascule
/// `Speakers` et le bouton `Résumer`.
///
/// **Contenu provisoire** : les colonnes sont ici l'éditeur markdown et la vue
/// de transcription existants, injectés par `MeetingView` (les fonctions de
/// diarisation et de locuteurs restent dans ce fichier pour ce lot). Le lot 2
/// les remplace par `TimedNotesColumn` et `TranscriptColumn`, avec le
/// composeur `/action /décision /risque /citer` et la frise audio.
struct MeetingLiveSpace<Notes: View, Transcript: View>: View {

    /// Hauteur de l'en-tête de la carte.
    static var headerHeight: CGFloat { 34 }

    let screen: MeetingScreenModel
    /// Vrai si la transcription montre des locuteurs (mode diarisation) : la
    /// bascule `Speakers` n'a pas de sens sinon.
    let showsSpeakerToggle: Bool
    /// Lance la génération du résumé (`SummaryCard.generate` existant).
    let onSummarize: () -> Void
    @ViewBuilder let notes: Notes
    @ViewBuilder let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            GeometryReader { geo in
                let colonnes = MeetingSpaceLayout.evenSplit(width: geo.size.width)
                HStack(spacing: 0) {
                    colonne("MES NOTES", largeur: colonnes.0) { notes }
                    Rectangle()
                        .fill(One2OneToken.hair)
                        .frame(width: MeetingSpaceLayout.hairlineWidth)
                    colonne("TRANSCRIPTION", largeur: colonnes.1, fond: One2OneToken.surfaceAlt) {
                        transcript
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusCard))
    }

    private var entete: some View {
        HStack(spacing: 8) {
            Text("Notes & transcription")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("synchronisées sur l'audio")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
            Spacer(minLength: 8)
            if showsSpeakerToggle {
                Button {
                    screen.showSpeakers.toggle()
                } label: {
                    Text(screen.showSpeakers ? "Speakers ON" : "Speakers OFF")
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(screen.showSpeakers
                                         ? One2OneToken.actionInk
                                         : One2OneToken.ink3)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                                .fill(screen.showSpeakers
                                      ? One2OneToken.actionBg
                                      : One2OneToken.surfaceAlt)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Afficher les locuteurs identifiés dans la transcription")
            }
            Button(action: onSummarize) {
                Text("Résumer")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                            .fill(One2OneToken.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                            .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Générer le résumé en une phrase")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// Une colonne de la carte, avec son libellé mono en tête.
    @ViewBuilder
    private func colonne<Content: View>(_ libelle: String,
                                        largeur: CGFloat,
                                        fond: Color = One2OneToken.surface,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(libelle).sectionLabel()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 5)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: largeur)
        .background(fond)
    }
}
