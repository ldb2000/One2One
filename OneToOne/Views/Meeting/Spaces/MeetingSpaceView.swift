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
/// deux rails dans le même écran, ou aucun selon le mode.
///
/// Le mode **Relire** est l'exception, et elle est entière : le poste de
/// pilotage (`1c-poste-de-pilotage.png`, lot 5) prend toute la surface — sa nav
/// latérale de 190 px remplace la barre d'espaces, ses actions sont un tableau
/// dense de la colonne principale, et il monte lui-même son dock d'assistant et
/// sa frise audio. Il n'y a donc ni bandeau d'indicateurs, ni rail, ni
/// `colonneFluide` dans ce mode.
struct MeetingSpaceView: View {
    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    let kpi: MeetingKPI
    let prepareContext: MeetingPrepareContext
    /// Réunions connues, pour les suggestions de l'assistant.
    let historique: [Meeting]
    /// Les actions secondaires de la réunion (export, édition audio, rapport),
    /// que l'en-tête et la frise du mode Relire réemploient. Source de vérité
    /// unique déjà partagée par le menu `⋯` et les menus natifs.
    let menuActions: MeetingMenuActions
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
    /// Ouvre la galerie de captures, ou sa configuration s'il n'y en a aucune.
    let onShowCaptures: () -> Void
    /// Ouvre le sélecteur de fichiers du tiroir Ressources. Porté par
    /// `MeetingView`, qui n'a qu'**un** `.fileImporter` dans sa hiérarchie.
    let onImportResources: () -> Void
    /// Le pilotage de la capture (lot 7), transmis à `MeetingLiveSpace` pour la
    /// bande de captures en pied de colonne. Optionnel : les aperçus et les
    /// tests montent cet écran sans session de capture.
    var capture: CaptureSessionCoordinator?

    /// Les collaborateurs, pour les sélecteurs de responsable du rail.
    /// Interrogés ici plutôt que passés en paramètre : c'est la vue qui monte
    /// le rail, et un `@Binding` traversant de plus est exactement ce que le
    /// programme §8 interdit.
    @Query(sort: \Collaborator.name) private var allCollaborators: [Collaborator]

    /// Le contexte, pour le coordinateur de ressources du lot 6. Le lot 5
    /// l'avait retiré — le mode Relire n'écrivait plus rien d'ici — mais le
    /// tiroir, lui, insère et sauvegarde des pièces.
    @Environment(\.modelContext) private var context

    /// Un glisser survole la fenêtre : la zone de dépôt du tiroir s'allume.
    @State private var isDropTargeted = false

    /// Le mode En séance du type Atelier est l'écran 6a, qui occupe **toute**
    /// la largeur : son dock de 314 px remplace le rail d'actions (plan §5,
    /// lot 16). Derrière `workshopEnabled` : sans le drapeau, l'atelier se
    /// comporte comme une réunion ordinaire.
    private var estAtelierEnSeance: Bool {
        meeting.kind == .workshop && settings.workshopEnabled && screen.mode == .live
    }

    var body: some View {
        contenu
            // Lot 6, spec §4.1 : le tiroir Ressources se **superpose** à la
            // séance sans la démonter — la colonne principale reste
            // interactive, et un dépôt de fichier est accepté de n'importe où
            // dans la fenêtre. Posé sur `contenu` et non dans une branche : le
            // tiroir s'ouvre aussi depuis le poste de pilotage du lot 5.
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                ResourceCoordinator(meeting: meeting, context: context,
                                    state: screen.resources,
                                    playhead: screen.playhead).handleDrop(providers)
            }
            .overlay(alignment: .trailing) { tiroirRessources }
            // Le point d'entrée du mode séance plein écran (lot 4, spec §2.6) :
            // une seule pose dans l'application. Il substitue le contenu de la
            // fenêtre, la barre du haut de `MeetingView` comprise — d'où sa
            // place ici et non dans une colonne. `estEligible` le réserve au
            // mode En séance : le poste de pilotage du lot 5 n'a pas de plein
            // écran, et l'offrir depuis Relire ouvrirait un écran de séance
            // sur une réunion terminée.
            .sessionFullscreen(meeting: meeting,
                               screen: screen,
                               settings: settings,
                               estEligible: screen.mode == .live,
                               onOpenMeeting: onOpenMeeting,
                               onDiarize: onDiarize,
                               onReidentify: onReidentify)
            // Le point d'entrée de la pastille flottante (lot 8, spec §5.4) : il
            // n'ajoute rien à l'écran, il inscrit cette réunion comme « réunion
            // active » pour la pastille, `⌘⇧S` et `⌘⇧N` — trois surfaces qui vivent
            // hors de toute hiérarchie de vues. Même place et même raison que le
            // modificateur du lot 4 juste au-dessus : c'est ici que se trouvent à la
            // fois la réunion, son modèle d'écran et le coordinateur de capture.
            .sessionPill(meeting: meeting,
                         screen: screen,
                         capture: capture,
                         estEligible: screen.mode == .live)
            // Lot 12, spec §3 : « `2b` s'ouvre par défaut en mode `Préparer` ».
            .onAppear(perform: appliquerModeInitial)
    }

    /// Impose le mode d'ouverture d'un 1:1 jamais ouvert (spec §3).
    ///
    /// Écrit la clé mémorisée **et** le mode, parce que l'ordre des `onAppear`
    /// de SwiftUI ne dit pas si `MeetingScreenModel.attach` a déjà relu
    /// `UserDefaults` : dans un sens c'est l'écriture du mode qui prend, dans
    /// l'autre c'est la clé que `attach` relira. Un choix déjà mémorisé fait
    /// toujours loi — `MeetingSpaceRouting.initialMode` rend `nil` dans ce cas.
    private func appliquerModeInitial() {
        let cle = MeetingScreenModel.modeKey(for: meeting.ensuredStableID)
        let memorise = UserDefaults.standard.string(forKey: cle)
        guard let mode = MeetingSpaceRouting.initialMode(
                persistedRaw: memorise,
                kind: meeting.kind,
                hasRecording: meeting.hasPlayableAudio || meeting.recordingStartedAt != nil)
        else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: cle)
        if screen.mode != mode { screen.mode = mode }
    }

    /// Le contenu de l'espace : le poste de pilotage seul en mode Relire, les
    /// deux colonnes — fluide et rail de 330 px — partout ailleurs.
    ///
    /// Ordre du routage, fixé à l'intégration de la vague 5 : **type Atelier**,
    /// puis **type 1:1** selon le mode, puis la disposition standard selon le
    /// mode. Les prédicats sont exclusifs deux à deux (l'atelier veut
    /// `.workshop`, le 1:1 veut `.oneToOne`, Relire veut `.review` quand les
    /// deux autres veulent `.live` ou `.prepare`) : l'ordre est donc une
    /// lecture, pas une priorité qui masquerait un cas.
    ///
    /// Extrait de `body` à l'intégration de la vague 4 : les points d'entrée
    /// des lots 4 et 6 se posent en modificateurs sur l'espace entier, et le
    /// mode Relire du lot 5 remplace le corps de la vue. Sans ce découpage,
    /// il faudrait répéter chaque modificateur dans les deux branches.
    @ViewBuilder
    private var contenu: some View {
        if estAtelierEnSeance {
            WorkshopSpaceView(meeting: meeting,
                              screen: screen,
                              isAssistantOpen: $isAssistantOpen)
        } else if MeetingSpaceRouting.usesOneOnOneManagerSession(kind: meeting.kind,
                                                                 mode: screen.mode) {
            // Lot 11, spec §3.1 et §3.3 : l'écran de séance du 1:1 mené monte
            // ses **trois** colonnes et rien d'autre — ni bandeau
            // d'indicateurs, ni rail d'actions, ni présence. Il porte sa propre
            // barre d'assistant, en pied de colonne gauche.
            ManagerSessionView(meeting: meeting,
                               screen: screen,
                               historique: historique,
                               isAssistantOpen: $isAssistantOpen,
                               onManageParticipants: onManageParticipants)
        } else if MeetingSpaceRouting.usesOneOnOnePreparation(kind: meeting.kind,
                                                             mode: screen.mode) {
            // Lot 12, spec §3.4 : la préparation d'un 1:1 côté manager prend
            // toute la surface, comme le poste de pilotage. Ni bandeau
            // d'indicateurs (rien n'a encore été dit), ni rail d'actions de
            // 330 px (spec §3.1 retire les projets affectés et les vues
            // Kanban) : elle porte ses six cartes et sa propre barre
            // d'assistant, dont le contexte est le **fil** et non la séance.
            preparation1a1
        } else if screen.mode == .review {
            posteDePilotage
        } else {
            GeometryReader { geo in
                let colonnes = MeetingSpaceLayout.columns(totalWidth: geo.size.width,
                                                          rail: One2OneToken.actionsRailWidth,
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
        }
    }

    /// Le tiroir Ressources de 396 px, glissant depuis la droite (lot 6).
    @ViewBuilder
    private var tiroirRessources: some View {
        if screen.resources.isDrawerOpen {
            ResourcesDrawer(items: ResourceItem.all(for: meeting),
                            state: screen.resources,
                            actions: ResourceCoordinator(
                                meeting: meeting, context: context,
                                state: screen.resources,
                                playhead: screen.playhead).tileActions(),
                            reportOptions: Binding(
                                get: { meeting.reportAttachmentOptions },
                                set: { meeting.reportAttachmentOptions = $0 }),
                            participantCount: MeetingSharingState.presentCount(for: meeting),
                            projectName: meeting.project?.name,
                            onImport: onImportResources,
                            onPaste: {
                                _ = ResourceCoordinator(
                                    meeting: meeting, context: context,
                                    state: screen.resources,
                                    playhead: screen.playhead).pasteFromClipboard()
                            },
                            onSaveOptions: { try? context.save() },
                            isDropTargeted: isDropTargeted)
                .animation(.easeOut(duration: 0.16), value: screen.resources.isDrawerOpen)
        }
    }

    /// L'écran de préparation du 1:1 côté manager (lot 12, capture 2b).
    private var preparation1a1: some View {
        ManagerPrepView(meeting: meeting,
                        screen: screen,
                        historique: historique,
                        menuActions: menuActions,
                        isAssistantOpen: $isAssistantOpen,
                        onOpenMeeting: onOpenMeeting)
    }

    /// Le mode Relire prend toute la surface : il porte sa propre navigation,
    /// son en-tête, son dock et sa frise (lot 5, capture 1c).
    private var posteDePilotage: some View {
        MeetingReviewSpace(meeting: meeting,
                           screen: screen,
                           settings: settings,
                           allCollaborators: allCollaborators,
                           historique: historique,
                           menuActions: menuActions,
                           isSummarizing: isSummarizing,
                           isAssistantOpen: $isAssistantOpen,
                           onSummarize: onSummarize,
                           onOpenMeeting: onOpenMeeting,
                           onToggleAction: onToggleAction,
                           onShowCaptures: onShowCaptures)
    }

    /// La colonne de gauche : indicateurs, contenu du mode, assistant.
    private var colonneFluide: some View {
        VStack(spacing: One2OneToken.cardGap) {
            // Le bandeau n'a pas de sens en préparation : rien n'a encore été
            // dit, et la spec §2.2 ne le mentionne que pour En séance
            // (« KPI condensés en bandeau »). Le mode Relire ne passe plus
            // ici : il a ses propres cartes.
            if screen.mode == .live {
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
                                onToggleAction: onToggleAction,
                                // Lot 9 : le résumé de la fiche projet mène au
                                // panneau, dont l'ouverture est un état de
                                // l'écran.
                                onOpenProjectCard: { screen.showProjectCard = true })
        case .live:
            MeetingLiveSpace(meeting: meeting,
                             screen: screen,
                             settings: settings,
                             showsSpeakerToggle: showsSpeakerToggle,
                             onSummarize: onSummarize,
                             onDiarize: onDiarize,
                             onReidentify: onReidentify,
                             onAddToManagerReport: onAddToManagerReport,
                             capture: capture)
                .padding(.horizontal, 14)
        case .review:
            // Inatteignable : le mode Relire est routé en amont, hors de la
            // colonne fluide. `MeetingScreenModel.Mode` étant exhaustive, le
            // compilateur exige tout de même le cas.
            EmptyView()
        }
    }
}
