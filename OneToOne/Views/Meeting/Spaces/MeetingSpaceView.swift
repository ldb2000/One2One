import SwiftUI
import SwiftData

/// L'espace `Réunion` : bandeau d'indicateurs, contenu du mode, barre
/// d'invocation de l'assistant en pied (spec §2.2 et §2.3, capture
/// `1a-cockpit.png`).
///
/// Aiguille sur `MeetingScreenModel.mode` et ne connaît rien du métier : les
/// colonnes lui sont injectées par `MeetingView`, qui garde la transcription,
/// la diarisation et la liste d'actions pour ce lot.
struct MeetingSpaceView<Notes: View, Transcript: View, Actions: View>: View {
    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let kpi: MeetingKPI
    let prepareContext: MeetingPrepareContext
    /// Réunions connues, pour les suggestions de l'assistant.
    let historique: [Meeting]
    /// Vrai si la transcription montre des locuteurs (mode diarisation).
    let showsSpeakerToggle: Bool
    /// Vrai pendant la génération du résumé.
    let isSummarizing: Bool
    /// L'assistant est ouvert. Partagé avec `⌘K`
    /// (`MeetingMenuActions.openAssistant`).
    @Binding var isAssistantOpen: Bool

    let onSummarize: () -> Void
    let onManageParticipants: () -> Void
    let onFilterDecisions: () -> Void
    let onOpenRisks: () -> Void
    let onOpenMeeting: (PersistentIdentifier) -> Void
    let onToggleAction: (PersistentIdentifier) -> Void

    @ViewBuilder let notes: Notes
    @ViewBuilder let transcript: Transcript
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: One2OneToken.cardGap) {
            // Le bandeau n'a pas de sens en préparation : rien n'a encore été
            // dit, et la spec §2.2 ne le mentionne que pour En séance
            // (« KPI condensés en bandeau ») et Relire.
            if screen.mode != .prepare {
                MeetingKPIBand(
                    kpi: kpi,
                    onManageParticipants: onManageParticipants,
                    onFilterDecisions: onFilterDecisions,
                    onOpenRisks: onOpenRisks
                )
                .padding(.horizontal, 14)
            }

            contenuDuMode
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            MeetingAssistantDock(meeting: meeting,
                                 historique: historique,
                                 isOpen: $isAssistantOpen)
                .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
        .background(One2OneToken.bgCanvas)
    }

    @ViewBuilder
    private var contenuDuMode: some View {
        switch screen.mode {
        case .prepare:
            MeetingPrepareSpace(meeting: meeting,
                                contexte: prepareContext,
                                onOpenMeeting: onOpenMeeting,
                                onToggleAction: onToggleAction)
        case .live:
            MeetingLiveSpace(screen: screen,
                             showsSpeakerToggle: showsSpeakerToggle,
                             onSummarize: onSummarize,
                             notes: { notes },
                             transcript: { transcript })
                .padding(.horizontal, 14)
        case .review:
            MeetingReviewSpace(meeting: meeting,
                               kpi: kpi,
                               isSummarizing: isSummarizing,
                               onSummarize: onSummarize,
                               onShowTranscript: { screen.mode = .live },
                               actions: { actions })
        }
    }
}
