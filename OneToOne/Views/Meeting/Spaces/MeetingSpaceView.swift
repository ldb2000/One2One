import SwiftUI
import SwiftData

/// L'espace `Réunion` : bandeau d'indicateurs, contenu du mode, barre
/// d'invocation de l'assistant en pied (spec §2.2 et §2.3, capture
/// `1a-cockpit.png`).
///
/// Aiguille sur `MeetingScreenModel.mode` et ne connaît rien du métier. Depuis
/// le lot 2, le mode En séance monte ses propres colonnes
/// (`MeetingLiveSpace`) : seule la liste d'actions du mode Relire reste
/// injectée par `MeetingView`, jusqu'au rail du lot 3.
struct MeetingSpaceView<Actions: View>: View {
    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
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
    let onDiarize: () -> Void
    let onReidentify: () -> Void
    let onAddToManagerReport: (NSRange, String, String) -> Void

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
            MeetingLiveSpace(meeting: meeting,
                             screen: screen,
                             settings: settings,
                             showsSpeakerToggle: showsSpeakerToggle,
                             onSummarize: onSummarize,
                             onDiarize: onDiarize,
                             onReidentify: onReidentify,
                             onAddToManagerReport: onAddToManagerReport)
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
