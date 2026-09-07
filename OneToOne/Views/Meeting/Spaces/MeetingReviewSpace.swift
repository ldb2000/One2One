import SwiftUI
import SwiftData

/// Le mode Relire de l'espace Réunion : le **poste de pilotage** de la capture
/// `1c-poste-de-pilotage.png` (spec §2.7, décision D0 du programme).
///
/// « Les onglets deviennent un rail latéral, l'écran devient un tableau de bord
/// tabulaire dense, l'audio est une frise en pied d'écran commune à tout
/// l'écran. » La disposition est donc : nav latérale de 190 px à gauche
/// (qui **remplace** la barre d'espaces dans ce mode), colonne principale
/// fluide à droite — en-tête, `EN UNE PHRASE` et `DÉCISIONS PRISES` côte à
/// côte, tableau d'actions —, barre d'assistant puis frise audio en pied.
///
/// Rien n'est monté deux fois : la vue ne fabrique aucune carte elle-même, elle
/// assemble `ReviewSidebarNav`, `ReviewHeader`, `OneSentenceCard`,
/// `DecisionsCard`, `ActionsTable`, `MeetingAssistantDock` et
/// `ReviewAudioTimeline`. Le contenu provisoire du lot 1 — trois cartes locales
/// et une liste d'actions injectée par `MeetingView` — a disparu.
struct MeetingReviewSpace: View {

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    /// Les collaborateurs, pour les sélecteurs de responsable du tableau.
    let allCollaborators: [Collaborator]
    /// Réunions connues : le bloc projet de la nav et les suggestions de
    /// l'assistant.
    let historique: [Meeting]
    /// Les actions secondaires de la réunion (export, édition audio, rapport).
    let menuActions: MeetingMenuActions
    /// Vrai pendant la génération du résumé court.
    let isSummarizing: Bool
    /// Le panneau d'assistant est ouvert (partagé avec `⌘K`).
    @Binding var isAssistantOpen: Bool

    let onSummarize: () -> Void
    let onOpenMeeting: (PersistentIdentifier) -> Void
    let onToggleAction: (PersistentIdentifier) -> Void
    /// Ouvre la galerie de captures, ou sa configuration s'il n'y en a aucune.
    let onShowCaptures: () -> Void

    @Environment(\.modelContext) private var context

    /// Les captures de la réunion : elles vivent sous les pièces jointes de
    /// type `slides`, pas directement sur la réunion.
    private var capturesCount: Int {
        meeting.attachments.flatMap(\.slides).count
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ReviewSidebarNav(meeting: meeting,
                             screen: screen,
                             historique: historique,
                             onOpenMeeting: onOpenMeeting,
                             onOpenAssistant: { isAssistantOpen = true })
            Rectangle()
                .fill(One2OneToken.cardBorder)
                .frame(width: MeetingSpaceLayout.hairlineWidth)
            colonnePrincipale
        }
        .background(One2OneToken.bgCanvas)
    }

    // MARK: - Colonne principale

    private var colonnePrincipale: some View {
        VStack(spacing: 0) {
            ReviewHeader(meeting: meeting,
                         screen: screen,
                         menuActions: menuActions,
                         capturesCount: capturesCount,
                         onShowCaptures: onShowCaptures)
            corps
            MeetingAssistantDock(meeting: meeting,
                                 historique: historique,
                                 isOpen: $isAssistantOpen)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            ReviewAudioTimeline(meeting: meeting,
                                screen: screen,
                                menuActions: menuActions)
        }
        // `min-width: 0` de la spec §1.2 : sans cela l'ellipsis du titre et des
        // intitulés d'action ne fonctionne pas, et la colonne pousse la nav
        // hors de l'écran.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Le corps défilant. Les ancres portent les sections de la nav latérale :
    /// cliquer `Notes` ou `Actions` amène la carte correspondante sous les
    /// yeux, au lieu de changer d'écran.
    private var corps: some View {
        ScrollViewReader { defilement in
            ScrollView {
                VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                    hautDeColonne
                        .id(ReviewState.Section.synthese)
                    ActionsTable(meeting: meeting,
                                 screen: screen,
                                 allCollaborators: allCollaborators,
                                 onSeek: { screen.playhead.seek(to: $0) },
                                 onToggle: { onToggleAction($0.persistentModelID) },
                                 onSave: { try? context.save() })
                        .id(ReviewState.Section.actions)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .onChange(of: screen.review.section) { _, section in
                // Deux ancres seulement : `Notes` et `Transcription` ne
                // défilent pas, elles ramènent en mode En séance
                // (`Section.changeDeMode`), et les autres entrées changent
                // d'espace ou ouvrent le dock.
                let cible: ReviewState.Section = (section == .actions) ? .actions : .synthese
                withAnimation(.easeInOut(duration: 0.2)) {
                    defilement.scrollTo(cible, anchor: .top)
                }
            }
        }
    }

    /// `EN UNE PHRASE` et `DÉCISIONS PRISES` côte à côte, comme la capture. En
    /// dessous de 900 px, elles s'empilent : deux cartes de 430 px dans une
    /// colonne fluide de 520 px (le plancher du critère n° 5) ne laisseraient
    /// lire ni l'une ni l'autre.
    private var hautDeColonne: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: One2OneToken.cardGap) {
                OneSentenceCard(meeting: meeting,
                                settings: settings,
                                isSummarizing: isSummarizing,
                                onSummarize: onSummarize)
                    .frame(minWidth: 420)
                DecisionsCard(meeting: meeting,
                              onSeek: { screen.playhead.seek(to: $0) })
                    .frame(minWidth: 340)
            }
            VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                OneSentenceCard(meeting: meeting,
                                settings: settings,
                                isSummarizing: isSummarizing,
                                onSummarize: onSummarize)
                DecisionsCard(meeting: meeting,
                              onSeek: { screen.playhead.seek(to: $0) })
            }
        }
    }
}
