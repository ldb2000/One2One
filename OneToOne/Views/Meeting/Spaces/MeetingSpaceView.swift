import SwiftUI
import SwiftData

/// L'espace `Réunion` : bandeau d'indicateurs, contenu du mode, rail d'actions
/// permanent à droite, barre d'invocation de l'assistant en pied (spec §2.2,
/// §2.3 et §2.5, capture `1a-cockpit.png`).
///
/// Aiguille sur `MeetingScreenModel.mode` et ne connaît rien du métier. Depuis
/// le lot 2, le mode En séance monte ses propres colonnes (`MeetingLiveSpace`,
/// notes et transcription) ; depuis le lot 3, c'est aussi elle qui monte le
/// rail. Plus aucun générique : la vue ne reçoit plus de colonne injectée.
///
/// **C'est ici, et nulle part ailleurs, que le rail est monté.** Le lot 1
/// l'avait esquissé dans `MeetingPrepareSpace` ; deux montages produiraient
/// deux rails dans le même écran, ou aucun selon le mode. Le mode Relire fait
/// exception : la capture `1c-poste-de-pilotage.png` n'a pas de rail — les
/// actions y sont un tableau dense de la colonne principale (lot 5).
struct MeetingSpaceView: View {
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

    /// Les collaborateurs, pour les sélecteurs de responsable du rail.
    /// Interrogés ici plutôt que passés en paramètre : c'est la vue qui monte
    /// le rail, et un `@Binding` traversant de plus est exactement ce que le
    /// programme §8 interdit.
    @Query(sort: \Collaborator.name) private var allCollaborators: [Collaborator]

    @Environment(\.modelContext) private var context

    /// La largeur souhaitée du rail, `nil` quand il n'y en a pas.
    private var largeurDuRail: CGFloat? {
        screen.mode == .review ? nil : One2OneToken.actionsRailWidth
    }

    var body: some View {
        GeometryReader { geo in
            let colonnes = MeetingSpaceLayout.columns(totalWidth: geo.size.width,
                                                      rail: largeurDuRail,
                                                      sideNav: nil)
            HStack(alignment: .top, spacing: 0) {
                colonneFluide
                    .frame(width: colonnes.fluid)
                if colonnes.rail > 0 {
                    Rectangle()
                        .fill(One2OneToken.hair)
                        .frame(width: MeetingSpaceLayout.hairlineWidth)
                    ActionsRail(meeting: meeting,
                                screen: screen,
                                allCollaborators: allCollaborators,
                                onSeek: { screen.playhead.seek(to: $0) },
                                reduit: screen.mode == .prepare)
                        .frame(width: colonnes.rail - MeetingSpaceLayout.hairlineWidth)
                }
            }
        }
        .background(One2OneToken.bgCanvas)
        // Le point d'entrée du mode séance plein écran (lot 4, spec §2.6) :
        // une seule pose dans l'application. Il substitue le contenu de la
        // fenêtre, la barre du haut de `MeetingView` comprise — d'où sa place
        // ici et non dans une colonne.
        .sessionFullscreen(meeting: meeting,
                           screen: screen,
                           settings: settings,
                           estEligible: screen.mode == .live,
                           onOpenMeeting: onOpenMeeting,
                           onDiarize: onDiarize,
                           onReidentify: onReidentify)
    }

    /// La colonne de gauche : indicateurs, contenu du mode, assistant.
    private var colonneFluide: some View {
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
        .frame(maxHeight: .infinity, alignment: .top)
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
                               actions: {
                                   // Sans rail en mode Relire, c'est la même
                                   // liste éditable qui sert — le tableau
                                   // dense de la capture 1c arrive au lot 5.
                                   ActionsRailList(meeting: meeting,
                                                   allCollaborators: allCollaborators,
                                                   onSeek: { screen.playhead.seek(to: $0) },
                                                   onToggle: { onToggleAction($0.id) },
                                                   onSave: { try? context.save() })
                               })
        }
    }
}
