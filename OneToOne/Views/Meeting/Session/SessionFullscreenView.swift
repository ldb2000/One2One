import SwiftUI
import SwiftData

/// Le **mode séance plein écran** (écran 1b, spec §2.6, capture
/// `1b-mode-seance.png`).
///
/// « Palette sombre `dark/*`. Grille `78px | 1fr | 400px`. Aucun chrome hors la
/// barre d'état. »
///
/// Trois colonnes, une barre d'état, rien d'autre : ni barre d'espaces, ni
/// bandeau d'indicateurs, ni rail d'actions, ni fil d'Ariane. Le rail de 330 px
/// du lot 3 n'est pas là non plus — pas par oubli : en séance, la liste des
/// douze actions du projet est un appel à faire autre chose que d'écouter. Ce
/// qui en reste est le bandeau `EN ATTENTE`, et il ne concerne que ce qui vient
/// d'être décidé.
///
/// Tout le contenu est réemployé : `TimedNotesColumn` et `NoteComposer`
/// (lot 2), `TranscriptColumn` (lot 2), `OwnerPickerMenu` et
/// `ActionCardEditing` (lot 3) — en thème `.session`, qu'ils lisent dans
/// l'environnement sans le choisir.
struct SessionFullscreenView: View {

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    /// Ouvre une autre réunion (source citée par l'assistant).
    let onOpenMeeting: (UUID, Double?) -> Void
    /// Diarisation et ré-identification, orchestrées par `MeetingView`.
    let onDiarize: () -> Void
    let onReidentify: () -> Void
    /// Sortie du mode.
    let onExit: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Collaborator.name) private var allCollaborators: [Collaborator]
    @ObservedObject private var recorder = AudioRecorderService.shared

    /// L'assistant du panneau. Vit ici et non dans `SessionFullscreenState` :
    /// c'est un contrôleur, pas un état d'écran, et il ne doit pas survivre à
    /// la fermeture du mode avec une requête en vol.
    @State private var assistant = MeetingAssistantController()

    private var theme: One2OneTheme { .session }
    private var c: One2OneColors { theme.colors }

    private var isRecording: Bool {
        recorder.isRecording(for: meeting.ensuredStableID)
    }

    /// Le début de la séance, origine du bloc `CAPTURÉ CETTE SÉANCE`.
    private var debutDeSeance: Date {
        SessionCapturedSummary.debutDeSeance(
            recordingStartedAt: meeting.recordingStartedAt,
            ouvertureDuMode: screen.session.enteredAt ?? meeting.date
        )
    }

    private var enAttente: [ActionTask] {
        PendingAssignment.sansResponsable(meeting.tasks)
    }

    private var locuteur: SessionCurrentSpeaker.Locuteur? {
        SessionCurrentSpeaker.locuteur(segments: meeting.transcriptSegments,
                                       t: screen.playhead.t)
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionStatusBar(meeting: meeting,
                             screen: screen,
                             isRecording: isRecording,
                             locuteur: locuteur,
                             onClose: onExit)
            Rectangle().fill(c.hair).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                TimeRailColumn(meeting: meeting, screen: screen)
                filet
                colonneDesNotes
                filet
                colonneDeDroite
                    .frame(width: One2OneToken.sessionTranscriptWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .background(c.base)
        .one2OneTheme(theme)
        .task(id: signatureDesReperes) { rafraichirLesReperes() }
        // `Esc` : sortie directe, ou confirmation si l'enregistrement tourne
        // (spec §2.6). La règle est `SessionExitPolicy`, testée à part.
        .onExitCommand { echapper() }
        .confirmationDialog(SessionExitPolicy.confirmationTitre,
                            isPresented: Binding(get: { screen.session.isConfirmingExit },
                                                 set: { screen.session.isConfirmingExit = $0 })) {
            Button("Quitter le mode séance") { onExit() }
            Button("Rester", role: .cancel) { screen.session.isConfirmingExit = false }
        } message: {
            Text(SessionExitPolicy.confirmationMessage)
        }
        .sheet(isPresented: Binding(get: { screen.session.isAssigning },
                                    set: { screen.session.isAssigning = $0 })) {
            AssignmentQueueSheet(actions: enAttente,
                                 allCollaborators: allCollaborators,
                                 onClose: { screen.session.isAssigning = false })
                .one2OneTheme(theme)
        }
    }

    private var filet: some View {
        Rectangle().fill(c.hair).frame(width: 1).frame(maxHeight: .infinity)
    }

    // MARK: - Colonne des notes

    /// La colonne centrale : libellé, notes horodatées, composeur, et le
    /// bandeau `EN ATTENTE` en pied.
    private var colonneDesNotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Notes").sectionLabel()
                MonoMeta("enregistrement auto · liées au temps")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            TimedNotesColumn(meeting: meeting, screen: screen)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SessionPendingBand(actions: enAttente,
                               onAssign: { screen.session.isAssigning = true })
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c.base)
    }

    // MARK: - Colonne de droite

    /// `TRANSCRIPTION LIVE` + `Suivre`, puis l'assistant, puis les compteurs.
    ///
    /// La transcription prend la hauteur restante et les deux blocs de pied
    /// sont fixes : c'est la répartition de la capture, et c'est aussi la
    /// bonne — la réponse de l'assistant doit rester lisible quand la
    /// transcription s'allonge.
    private var colonneDeDroite: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Transcription live").sectionLabel()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            TranscriptColumn(meeting: meeting,
                             screen: screen,
                             settings: settings,
                             onDiarize: onDiarize,
                             onReidentify: onReidentify,
                             // Le CR manager se compose en relecture, pas en
                             // séance : ce chemin n'a pas de surface ici.
                             onAddToManagerReport: { _, _, _ in })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SessionAssistantPanel(meeting: meeting,
                                  screen: screen,
                                  settings: settings,
                                  assistant: assistant,
                                  onOpenMeeting: onOpenMeeting)

            SessionCapturedBlock(
                compteurs: SessionCapturedSummary.compteurs(meeting: meeting,
                                                            depuis: debutDeSeance)
            )
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(c.canvas)
    }

    // MARK: - Repères

    /// Même signature que `MeetingLiveSpace` : recalculer à chaque rendu
    /// relirait toutes les notes pour rien, un repère manquant après une prise
    /// de note serait un défaut visible.
    private var signatureDesReperes: String {
        "\(meeting.timedNotes.count)-\(meeting.attachments.flatMap(\.slides).count)"
    }

    private func rafraichirLesReperes() {
        screen.playhead.markers = MeetingTimelineMarkers.markers(for: meeting)
        if screen.playhead.duration <= 0 {
            screen.playhead.duration = Double(meeting.durationSeconds)
        }
    }

    private func echapper() {
        switch SessionExitPolicy.escape(isRecording: isRecording,
                                        isConfirming: screen.session.isConfirmingExit) {
        case .sortir:
            onExit()
        case .demanderConfirmation:
            screen.session.isConfirmingExit = true
        case .fermerLaConfirmation:
            screen.session.isConfirmingExit = false
        }
    }
}
