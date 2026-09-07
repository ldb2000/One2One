import SwiftUI

/// Le mode En séance de l'espace Réunion : « Notes ↔ transcription à parts
/// égales, KPI condensés en bandeau » (spec §2.2).
///
/// Une seule carte, `grid-template-columns: 1fr 1px 1fr` (spec §2.4), en-tête
/// « Notes & transcription · synchronisées sur l'audio » avec la bascule
/// `Speakers` et le bouton `Résumer`, et la **frise audio de 22 px** en pied.
///
/// Le lot 1 y injectait les vues provisoires de `MeetingView` (éditeur markdown
/// et ancienne transcription). Le lot 2 monte les composants définitifs :
/// `TimedNotesColumn` (avec son `NoteComposer`), `TranscriptColumn` et
/// `AudioTimelineStrip`. Plus rien n'est injecté depuis `MeetingView`, qui ne
/// garde que la diarisation et la ré-identification.
struct MeetingLiveSpace: View {

    /// Hauteur de l'en-tête de la carte.
    static var headerHeight: CGFloat { 34 }

    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    /// Vrai si la transcription montre des locuteurs (mode diarisation) : la
    /// bascule `Speakers` n'a pas de sens sinon.
    let showsSpeakerToggle: Bool
    /// Lance la génération du résumé (`SummaryCard.generate` existant).
    let onSummarize: () -> Void
    /// Diarisation VAD, orchestrée par `MeetingView` (tâches longues, phases).
    let onDiarize: () -> Void
    /// Ré-identification des locuteurs, même raison.
    let onReidentify: () -> Void
    /// Ajout d'un extrait de transcription au CR manager.
    let onAddToManagerReport: (NSRange, String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
            // Lot 6, spec §4.2 : la carte « À l'écran » n'existe que **pendant
            // un partage**. Sans document présenté elle disparaît de la
            // colonne au lieu de laisser un cadre vide — même règle que la
            // pilule de la barre du haut.
            if let presentee {
                OnScreenCard(meeting: meeting, screen: screen, item: presentee)
            }
            carteNotes
        }
    }

    /// La ressource à l'écran, `nil` quand rien n'est partagé — ou quand la
    /// pièce présentée a disparu de la liste (retirée, réunion rechargée) :
    /// l'identifiant est alors périmé et la carte s'efface d'elle-même, plutôt
    /// que d'afficher un cadre sans document.
    private var presentee: ResourceItem? {
        guard let id = screen.resources.presentedResourceID else { return nil }
        return ResourceItem.all(for: meeting).first { $0.id == id }
    }

    private var carteNotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            GeometryReader { geo in
                let colonnes = MeetingSpaceLayout.evenSplit(width: geo.size.width)
                HStack(spacing: 0) {
                    colonne("MES NOTES", largeur: colonnes.0) {
                        TimedNotesColumn(meeting: meeting, screen: screen)
                    }
                    Rectangle()
                        .fill(One2OneToken.hair)
                        .frame(width: MeetingSpaceLayout.hairlineWidth)
                    colonne("TRANSCRIPTION", largeur: colonnes.1, fond: One2OneToken.surfaceAlt) {
                        TranscriptColumn(meeting: meeting,
                                         screen: screen,
                                         settings: settings,
                                         onDiarize: onDiarize,
                                         onReidentify: onReidentify,
                                         onAddToManagerReport: onAddToManagerReport)
                    }
                }
            }
            AudioTimelineStrip(meeting: meeting, screen: screen)
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
        .task(id: marqueursSignature) { rafraichirMarqueurs() }
    }

    /// Signature des repères : recalculer à chaque rendu relirait toutes les
    /// notes et toutes les captures pour rien, mais un repère manquant après
    /// une prise de note serait un défaut visible.
    private var marqueursSignature: String {
        "\(meeting.timedNotes.count)-\(meeting.attachments.flatMap(\.slides).count)"
            + "-\(meeting.pinnedAttachments.count)"
    }

    private func rafraichirMarqueurs() {
        // `allMarkers` et non `markers` : le lot 6 ajoute les pièces épinglées
        // (`MeetingTimelineMarkers+Pins.swift`), et chaque lot y ajoutera la
        // sienne sans que cette vue ait à connaître la liste.
        screen.playhead.markers = MeetingTimelineMarkers.allMarkers(for: meeting)
        // Sans fichier chargé, l'axe temps est celui de la réunion : sinon la
        // frise et les timecodes de notes n'auraient aucune échelle.
        if screen.playhead.duration <= 0 {
            screen.playhead.duration = Double(meeting.durationSeconds)
        }
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
