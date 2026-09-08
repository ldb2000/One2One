import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

/// Pipeline phases surfaced to the UI during a transcription run.
enum TranscriptionPhase: Equatable, Sendable {
    case idle
    case loadingModel        // first-call HuggingFace download / MLX kernel load
    case transcribing        // Cohere STT
    case diarizing           // Pyannote + WeSpeaker embeddings
    case matching            // SpeakerMatcher cosine + persist
    case reidentifying       // toolbar "Re-identifier les speakers"
    case error(String)

    var isActive: Bool {
        if case .idle = self { return false }
        if case .error = self { return false }
        return true
    }

    var label: String {
        switch self {
        case .idle:           return ""
        case .loadingModel:   return "Chargement du modèle…"
        case .transcribing:   return "Transcription en cours…"
        case .diarizing:      return "Diarisation des locuteurs…"
        case .matching:       return "Identification des speakers…"
        case .reidentifying:  return "Ré-identification des speakers…"
        case .error(let msg): return "Erreur: \(msg)"
        }
    }
}

/// Écran de détail d'une réunion : en-tête, onglets (préparation, notes live,
/// transcription, rapport, documents), barre d'enregistrement et sidebar
/// contextuelle. Orchestre enregistrement audio, transcription STT/diarisation,
/// génération de rapport IA et gestion des speakers.
struct MeetingView: View {
    @Bindable var meeting: Meeting
    /// Vrai quand l'écran a été **poussé** dans une pile — depuis la fiche d'un
    /// collaborateur. Un chevron de retour apparaît alors dans le fil
    /// d'Ariane. Faux par défaut : ouverte seule, la réunion n'a rien derrière.
    var isPushed: Bool = false
    /// Démarre automatiquement le recorder à `onAppear` (déclenché par
    /// quick-launch 1:1). Consommé une seule fois grâce à `didAutoStart`.
    var autoStartRecording: Bool = false

    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var allCollaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    /// Toutes les réunions : le mode Préparer y prend les trois derniers
    /// points du projet, et l'assistant y date sa seconde suggestion.
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @Environment(\.modelContext) private var context

    // MARK: - Services

    @StateObject private var recorder = AudioRecorderService.shared
    @ObservedObject private var liveService = LiveTranscriptionService.shared
    @StateObject private var stt = TranscriptionService.shared
    /// Tête de lecture **partagée** de la réunion (lot 0B) : c'est elle qui
    /// possède l'unique `AudioPlayerService`, désormais commun à la barre du
    /// haut, à la barre d'enregistrement et à la frise de l'éditeur audio.
    /// Résolue par le registre à chaque lecture : il retient l'instance, la
    /// vue n'a rien à retenir.
    private var playhead: MeetingPlayhead { screen.playhead }
    private var player: AudioPlayerService { playhead.player }
    @StateObject private var captureService = ScreenCaptureService()

    // MARK: - Local state

    /// L'état d'écran de cette réunion : espace, moment, brouillon d'action,
    /// bascules d'affichage. Remplace treize `@State` dont huit descendaient en
    /// `@Binding` sur deux niveaux, à travers le dashboard et son panneau
    /// d'actions — tous deux retirés au lot 19. Cf. `MeetingScreenModel`.
    /// Rattaché à la réunion dans `.onAppear`.
    @State private var screen = MeetingScreenModel()
    @State private var showDetailsSheet = false
    /// L'assistant est ouvert (barre d'invocation ou `⌘K`, spec §1.4).
    @State private var showAssistant = false
    /// Une génération de résumé en une phrase est en cours (mode Relire).
    @State private var isSummarizing = false
    @State private var isGeneratingReport = false
    @State private var isGenerating: Bool = false
    @State private var reportEditMode: Bool = false
    @State private var reportError: String?
    @State private var transcribeError: String?
    @State private var transcriptionPhase: TranscriptionPhase = .idle
    @State private var transcriptionProgress: Double? = nil   // 0.0–1.0 when known
    @State private var transcriptionProgressStatus: String? = nil
    /// Cible du sélecteur de fichiers UNIFIÉ. On n'utilise qu'un seul
    /// `.fileImporter` : macOS/SwiftUI ne présente pas fiablement plusieurs
    /// `.fileImporter` coexistant dans la même hiérarchie (l'un masque l'autre,
    /// d'où « impossible d'importer »).
    enum FileImportTarget { case wav, documents }
    @State private var fileImportTarget: FileImportTarget?
    @State private var showCalendarImporter = false
    @State private var calendarImportError: String?
    @State private var wavImportError: String?
    @State private var reportProgressChars: Int = 0
    @State private var reportElapsedSeconds: Int = 0
    @State private var reportActivity = AIReportProgress()
    @State private var saveDebounceTask: Task<Void, Never>?
    @State private var didAutoStart = false
    @State private var audioEditMode: AudioEditMode?
    @State private var showDeleteConfirm = false
    /// Vrai dès l'entrée dans `deleteMeeting()`, avant `dismiss()`. Empêche
    /// `.onDisappear` de réindexer une réunion que l'on est en train de
    /// supprimer : `indexAll`/`index(meeting:)` n'élaguent jamais l'index,
    /// donc un réindexage après suppression laisserait un orphelin définitif
    /// (aucun chemin ne rappelle `remove(meeting:)` pour un modèle qui n'existe
    /// plus).
    @State private var isBeingDeleted = false
    @State private var showParticipantsSheet = false
    @State private var isSuggestingTags = false
    @Environment(\.dismiss) private var dismiss
    // MARK: - Manager report sheet
    /// Identifiable wrapper around the pending selection. Using `.sheet(item:)`
    /// instead of `.sheet(isPresented:)` avoids a SwiftUI race where the sheet
    /// content closure could evaluate before `pendingMgrSelection` was visible
    /// and render an empty modal.
    struct PendingMgrSelection: Identifiable {
        let id = UUID()
        let range: NSRange
        let snippet: String
        let field: String
    }
    @State private var pendingMgrSelection: PendingMgrSelection?
    @State private var mgrSuggestedCategory: String?
    @State private var isMgrSuggestingCategory = false
    @State private var mgrSuggestedElaboration: String?
    @State private var isMgrElaborating = false
    @State private var mgrInitialElaboration: String = ""
    @State private var mgrElaborationFromAI: Bool = false
    @State private var mgrElaborationFallbackReason: String = ""

    // Speaker view toggle + rename popover state
    /// Si défini, la prochaine `stop()` concatène le nouveau WAV avec celui-ci.
    @State private var pendingAppendBaseURL: URL?

    /// Vrai si l'enregistrement en cours est celui **de cette réunion**.
    /// `AudioRecorderService` est un singleton observé par toutes les fenêtres :
    /// tout affichage d'enregistrement (vumètre, chrono, pastille) doit passer
    /// par ici, sinon il apparaît dans toutes les fenêtres ouvertes.
    private var isRecordingThisMeeting: Bool {
        recorder.isRecording(for: meeting.stableID)
    }

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            MeetingTopChromeBar(
                meeting: meeting,
                recorder: recorder,
                stt: stt,
                captureService: captureService,
                playhead: playhead,
                isRecordingThisMeeting: isRecordingThisMeeting,
                isGeneratingReport: isGeneratingReport,
                reportElapsedSeconds: reportElapsedSeconds,
                reportStatus: reportActivity.label,
                reportWaitWarning: reportActivity.warning(),
                actions: makeMenuActions(),
                capturedSlidesCount: captureCoordinator.captureCount,
                resources: screen.resources,
                capture: captureCoordinator,
                onTogglePlay: { if let wav = meeting.wavFileURL { togglePlay(url: wav); screen.showPlayback = true } },
                onShowCaptureSetup: { screen.capture.showPopover = true },
                // Lot 6, spec §4.1 : le bouton `Capture` ouvre le tiroir
                // Ressources sur le filtre Captures — une vignette par
                // capture, avec `Présenter` et, au clic droit, le retrait.
                // Le popover `MeetingSlidesPopover` n'a donc plus d'appelant ;
                // il attend la bande de captures du lot 7 plutôt que d'offrir
                // une seconde galerie au même endroit.
                onShowSlides: { screen.resources.open(filter: .captures) },
                // Lot 9 : le segment projet ouvre la fiche en panneau de
                // 430 px (spec §4.3), plus la feuille « Détails ».
                onOpenProject: { screen.showProjectCard = true },
                onCreateMeeting: createMeeting,
                onBack: isPushed ? { dismiss() } : nil
            )
            .confirmationDialog("Supprimer la réunion ?", isPresented: $showDeleteConfirm) {
                Button("Supprimer", role: .destructive) { deleteMeeting() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Notes, transcription et rapport seront supprimés définitivement. Le fichier audio sur disque est conservé.")
            }

            HStack {
                MeetingPrepBadge(etat: MeetingPrepBadge.etat(for: meeting),
                                 onPrepare: { screen.space = .meeting; screen.mode = .prepare })
                Spacer()
            }
            .padding(.horizontal, MeetingTopChromeBar.paddingHorizontal)
            .padding(.vertical, 2)

            if isGeneratingReport, let warning = reportActivity.warning() {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            MeetingContextualRecorderBar(
                recorder: recorder,
                isRecordingThisMeeting: isRecordingThisMeeting,
                stt: stt,
                player: player,
                captureService: captureService,
                hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
                showPlayback: screen.showPlayback,
                onSnapshot: { captureService.snapshot() },
                onStopCapture: { captureService.stop() },
                onResumeCapture: { captureService.resume() },
                onSeek: { player.seek(to: $0) },
                onSkip: { player.skip(by: $0) },
                errors: [
                    recorder.lastError,
                    transcribeError,
                    reportError,
                    captureService.lastError,
                    screen.resources.importError,
                    calendarImportError,
                    wavImportError
                ].compactMap { $0 }.filter { !$0.isEmpty },
                onDismissErrors: {
                    recorder.lastError = nil
                    transcribeError = nil
                    reportError = nil
                    captureService.lastError = nil
                    screen.resources.importError = nil
                    calendarImportError = nil
                    wavImportError = nil
                }
            )
            .animation(.easeInOut(duration: 0.15), value: isRecordingThisMeeting)
            .animation(.easeInOut(duration: 0.15), value: captureService.hasOpenSession)
            .animation(.easeInOut(duration: 0.15), value: screen.showPlayback)

            // Le drapeau vit sur le singleton : sans `isRecordingThisMeeting`
            // le bandeau s'afficherait dans *toutes* les fenêtres réunion, et
            // survivrait à l'arrêt de l'enregistrement.
            if isRecordingThisMeeting, recorder.systemAudioUnavailable {
                Label("Audio Teams non capturé — enregistrement du micro seul. " +
                      "Autorisez l'enregistrement de l'écran dans Réglages Système pour capter les participants distants.",
                      systemImage: "speaker.slash")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

            transcriptionPhaseBanner

            mainPanel
        }
        .navigationTitle(meeting.title.isEmpty
                         ? (meeting.kind == .note ? "Note" : "Réunion")
                         : meeting.title)
        .textSelection(.enabled)
        .sheet(isPresented: $showCalendarImporter) {
            CalendarEventImportSheet(anchorDate: meeting.date) { event in
                importCalendarEvent(event)
            }
        }
        .sheet(item: $pendingMgrSelection) { pending in
            ManagerClassificationSheet(
                snippet: pending.snippet,
                projectName: meeting.project?.name,
                categories: settings.managerCategories,
                suggestedCategory: mgrSuggestedCategory,
                suggestedElaboration: mgrSuggestedElaboration,
                initialElaboration: mgrInitialElaboration,
                isLoadingSuggestion: isMgrSuggestingCategory,
                isLoadingElaboration: isMgrElaborating,
                elaborationFromAI: mgrElaborationFromAI,
                elaborationFallbackReason: mgrElaborationFallbackReason,
                onCancel: {
                    pendingMgrSelection = nil
                },
                onConfirm: { category, tag, elaboratedText, aiSuggested in
                    confirmManagerItem(pending: pending,
                                        category: category,
                                        tag: tag,
                                        elaboratedText: elaboratedText,
                                        aiSuggested: aiSuggested)
                }
            )
        }
        .sheet(item: $audioEditMode) { mode in
            AudioEditorSheet(meeting: meeting, mode: mode, playhead: playhead) { _ in }
        }
        .sheet(isPresented: $showAssistant) {
            MeetingAssistantPanel(meeting: meeting, onClose: { showAssistant = false })
        }
        .sheet(isPresented: $showDetailsSheet) {
            MeetingDetailsBlock(
                meeting: meeting,
                projects: projects,
                calendarImportError: $calendarImportError,
                saveContext: saveContext,
                onClose: { showDetailsSheet = false },
                screen: screen,
                isSuggestingTags: isSuggestingTags,
                onRequestTagSuggestions: { Task { await suggestTags() } }
            )
        }
        .sheet(isPresented: $showParticipantsSheet) {
            ManageParticipantsSheet(
                meeting: meeting, settings: settings,
                availableCollaborators: availableCollaborators,
                collaboratorsCount: allCollaborators.count,
                screen: screen,
                addParticipant: addParticipant,
                removeParticipant: removeParticipant,
                removeAllParticipants: removeAllParticipants,
                setParticipantStatus: { status, c in setParticipantStatus(status, for: c) },
                participantStatus: { c in participantStatus(for: c) },
                addAdhoc: addAdhocParticipant,
                onResync: { resyncFromCalendarInMeetingView() },
                onClose: { showParticipantsSheet = false })
        }
        .fileImporter(
            isPresented: Binding(
                get: { fileImportTarget != nil },
                set: { if !$0 { fileImportTarget = nil } }
            ),
            allowedContentTypes: fileImportAllowedTypes,
            allowsMultipleSelection: fileImportTarget == .documents
        ) { result in
            let target = fileImportTarget
            fileImportTarget = nil
            switch target {
            case .wav:       Task { await importExistingWAV(result: result) }
            case .documents: Task { await resourceCoordinator.importPicked(result) }
            case .none:      break
            }
        }
        .onAppear {
            screen.attach(meetingID: meeting.ensuredStableID)
            screen.attachPlayhead(meeting: meeting)
            MeetingScreenRegistry.shared.screenAppeared(meeting.persistentModelID)
            // Reprise unique des notes markdown en notes horodatées (lot 0B).
            // Idempotent : le drapeau `notesMigrated` fait de ce `onAppear`,
            // rejoué à chaque remontage, un no-op après la première fois.
            MeetingNoteStore.importLiveNotesIfNeeded(meeting, in: context)
            applyActionDraftDefaultsIfNeeded()
            consumeTeamsRequestIfAny()
            guard autoStartRecording, !didAutoStart, !recorder.isRecording else { return }
            didAutoStart = true
            Task { await startRecording() }
        }
        // Une demande déposée alors que cette fenêtre est déjà montée.
        .onReceive(NotificationCenter.default.publisher(
            for: TeamsAutoRecordCoordinator.meetingRequestNotification)) { _ in
            consumeTeamsRequestIfAny()
        }
        .focusedSceneValue(\.meetingMenu, makeMenuActions())
        // Indexation Spotlight à la fermeture, pas à la sauvegarde : l'éditeur
        // de notes live appelle saveContext() à chaque frappe, ce qui
        // martèlerait CoreSpotlight si on indexait à chaque save.
        // Court-circuité pendant une suppression : voir isBeingDeleted, et
        // MeetingScreenRegistry pour celle prononcée par un autre écran.
        .onDisappear {
            let id = meeting.persistentModelID
            // En dernier, une fois les lectures faites : jusque-là, l'écran
            // qui interroge se compte lui-même.
            defer { MeetingScreenRegistry.shared.screenDisappeared(id) }
            guard !isBeingDeleted, !MeetingScreenRegistry.shared.isDeleted(id) else {
                // Réunion supprimée : la cascade emporte l'attachment de capture, il n'y a
                // rien à sauvegarder ni à réindexer. On abandonne la session — boucle et
                // OCR annulés, tout relâché : `stop()` la laisserait ouverte, et la
                // prochaine capture se heurterait à `sessionAlreadyOpen`.
                captureService.abandon()
                return
            }
            adoptPendingLiveNotes()
            guard !discardEmptyNoteIfNeeded() else { return }
            // Une session de capture ouverte est close avec l'écran : rien ne reste en
            // vol, le lot est réindexé. Après les gardes : une réunion en cours de
            // suppression ne doit pas être sauvegardée ni réindexée pendant sa cascade.
            if captureService.hasOpenSession { Task { await captureService.finish() } }
            SpotlightIndexService.shared.index(meeting: meeting)
        }
    }

    /// Reprend une note fermée sans qu'elle porte rien : les chemins de
    /// création insèrent, sauvegardent et indexent d'emblée, donc un clic
    /// malheureux laisserait sinon une note vide persistée **et** dans l'index
    /// Spotlight. Ce que « ne porte rien » recouvre exactement, et pourquoi ce
    /// n'est pas « ce que l'écran d'une note permet de remplir », est établi
    /// par `NoteFactory.isDiscardableEmptyNote` — la portée réelle du
    /// nettoyage y est décrite, elle est plus étroite que ces cinq chemins.
    ///
    /// Articulation avec le reste du cycle de vie :
    /// - ne supprime rien tant qu'un **autre** écran est monté sur la même
    ///   réunion (`MeetingScreenRegistry`) : la même note s'ouvre dans la pile
    ///   de navigation et dans la fenêtre autonome `1to1-meeting`, et
    ///   supprimer le modèle pendant que l'autre l'observe fait crasher
    ///   SwiftData — différer d'un tour de boucle n'y suffit pas, l'autre
    ///   écran ne se démonte pas ;
    /// - pose `isBeingDeleted` **avant** de supprimer, comme `deleteMeeting()` :
    ///   c'est ce drapeau qui empêche un second `.onDisappear` de réindexer —
    ///   ou de re-supprimer — un modèle disparu. C'est un `@State`, donc il ne
    ///   vaut que pour cette instance de vue ; la suppression est en plus
    ///   consignée dans `MeetingScreenRegistry`, que les autres écrans lisent
    ///   à leur fermeture ;
    /// - renvoie `true` pour que l'appelant saute l'indexation : réindexer ici
    ///   laisserait l'orphelin permanent que la tâche 4 a justement supprimé ;
    /// - annule la sauvegarde différée de l'éditeur, devenue sans objet ;
    /// - diffère le `delete` d'un tour de boucle, comme `deleteMeeting()` :
    ///   supprimer le modèle pendant que la vue l'observe encore fait crasher
    ///   SwiftData.
    /// - Returns: `true` si la note a été reprise.
    /// Identifiant d'enregistrement de l'éditeur du corps dans
    /// `MarkdownEditorRegistry`, **propre à cette réunion** : deux fenêtres
    /// ouvertes sur deux réunions différentes s'y écraseraient sinon l'une
    /// l'autre, et la reprise ci-dessous écrirait le corps de l'une dans
    /// l'autre.
    private var liveNotesEditorID: String {
        "meetingLiveNotes-\(meeting.persistentModelID)"
    }

    /// Reprend le texte encore à l'écran que l'éditeur n'a pas eu le temps de
    /// pousser dans le modèle : il écrit après un débounce de 0,3 s, annulé et
    /// reprogrammé à chaque touche, et son démontage ne vide pas l'écriture en
    /// attente. Fermer la fenêtre dans la foulée d'une frappe laisse donc
    /// `meeting.liveNotes` en retard d'une phrase — que
    /// `discardEmptyNoteIfNeeded` prendrait pour une note vide.
    ///
    /// Repose sur l'ordre de démontage : `.onDisappear` de cet écran avant le
    /// `dismantleNSView` de l'éditeur, faute de quoi il n'y a plus rien à
    /// reprendre dans le registre. SwiftUI ne le documente pas — c'est un des
    /// contrôles à dérouler à l'écran.
    private func adoptPendingLiveNotes() {
        guard let onScreen = PendingEditorText.onScreen(editorID: liveNotesEditorID),
              onScreen != meeting.liveNotes
        else { return }
        meeting.liveNotes = onScreen
        try? context.save()
        NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
    }

    private func discardEmptyNoteIfNeeded() -> Bool {
        let id = meeting.persistentModelID
        guard !MeetingScreenRegistry.shared.isPresentedElsewhere(id) else { return false }
        guard NoteFactory.isDiscardableEmptyNote(meeting) else { return false }
        isBeingDeleted = true
        MeetingScreenRegistry.shared.markDeleted(id)
        TeamsAutoRecordCoordinator.shared.meetingWasDeleted(meetingID: meeting.ensuredStableID)
        saveDebounceTask?.cancel()
        let target = meeting
        let ctx = context
        SpotlightIndexService.shared.remove(meeting: target)
        Task { @MainActor in
            ctx.delete(target)
            do { try ctx.save() } catch { print("[MeetingView] discard empty note FAILED: \(error)") }
        }
        return true
    }

    /// Construit la source d'actions partagée par le « ⋯ » et les menus natifs
    /// (réutilise les mêmes closures que le call-site du chrome bar).
    private func makeMenuActions() -> MeetingMenuActions {
        MeetingMenuActions(
            meetingTitle: meeting.title,
            kind: meeting.kind,
            isRecording: isRecordingThisMeeting,
            isPaused: recorder.isPaused,
            isTranscribing: stt.isTranscribing,
            isGeneratingReport: isGeneratingReport,
            hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
            hasPlayableAudio: meeting.hasPlayableAudio,
            hasReport: !meeting.summary.isEmpty,
            hasTranscript: !meeting.rawTranscript.isEmpty,
            startRecording: { Task { await startRecording() } },
            stopRecording: { Task { await stopRecordingAndTranscribe() } },
            appendRecording: { Task { await startAppendRecording() } },
            togglePause: { if recorder.isPaused { recorder.resume() } else { recorder.pause() } },
            retranscribe: { if let wav = meeting.wavFileURL { Task { await retranscribe(wavURL: wav) } } },
            generateReport: { Task { await startReportFlow() } },
            toggleCustomPrompt: { showDetailsSheet = true },
            importCalendar: { showCalendarImporter = true },
            importExistingWAV: { fileImportTarget = .wav },
            editAudio: { audioEditMode = .trimStart },
            revealWAV: {
                if let url = meeting.wavFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            deleteMeeting: { showDeleteConfirm = true },
            exportMarkdown: {
                let md = ExportService().exportMeetingMarkdown(meeting: meeting)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(md, forType: .string)
            },
            exportPDF: {
                let name = "Reunion_\(meeting.date.formatted(.iso8601.year().month().day()))_\(meeting.title).pdf"
                ExportService().exportMeetingPDF(meeting: meeting, fileName: name)
            },
            exportMail: { opts in ExportService().exportMeetingMail(meeting: meeting, options: opts) },
            exportOutlook: { opts in ExportService().exportMeetingOutlook(meeting: meeting, options: opts) },
            exportAppleNotes: { opts in ExportService().exportMeetingToAppleNotes(meeting: meeting, options: opts) },
            // `⌘K` : l'assistant se pose sur la réunion courante. La surface
            // arrive avec la branche 1b (`MeetingAssistantDock`) ; le
            // raccourci est déclaré ici pour que le menu ne mente pas.
            openAssistant: { showAssistant = true },
            // `⌘M` : marqueur au `t` courant de la tête de lecture partagée.
            addPlayheadMarker: { playhead.addMarker(at: playhead.t, kind: .note) },
            pasteResource: { _ = resourceCoordinator.pasteFromClipboard() },
            openResources: { screen.resources.open() },
            // `⌘⇧S` : le sélecteur la première fois, une capture directe
            // ensuite (spec §5.1) — la décision est dans `CaptureState`.
            captureNow: { Task { await captureCoordinator.handleShortcut() } }
        )
    }

    // MARK: - Main panel

    /// Types autorisés du sélecteur unifié, selon la cible active.
    private var fileImportAllowedTypes: [UTType] {
        switch fileImportTarget {
        case .documents:
            var types: [UTType] = [.pdf, .plainText, .text, .presentation, .spreadsheet, .content, .item]
            for ext in ["docx", "pptx", "xlsx"] {
                if let t = UTType(filenameExtension: ext) { types.append(t) }
            }
            return types
        default:
            return [.audio, .wav, .mp3, .mpeg4Audio, .aiff, .mpeg4Movie, .movie]
        }
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Les sept onglets ont cédé la place aux trois espaces de la spec
            // §1.1 et au sous-mode temporel du §2.2 : la préparation est
            // devenue le mode Préparer, le chat la barre d'assistant. Le
            // dashboard (`OverviewDashboard`) a été retiré au lot 19 ;
            // `MeetingChatView` vit désormais dans `MeetingAssistantPanel`.
            MeetingSpacesBar(
                screen: screen,
                kind: meeting.kind,
                hasReport: !meeting.summary.isEmpty,
                documentsCount: meeting.attachments.count,
                date: meeting.date
            )
            spaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // La colonne principale passe à 55 % d'opacité quand la fiche
                // est ouverte (spec §4.3) et **reste consultable** : pas de
                // `allowsHitTesting(false)`, la spec insiste.
                .opacity(screen.showProjectCard ? One2OneToken.dimmedOpacity : 1)
        }
        .background(One2OneToken.bgCanvas)
        // Le panneau se superpose à n'importe quel espace et à n'importe quel
        // mode : l'overlay vit donc ici, au-dessus de `spaceContent`, et non
        // dans `MeetingSpaceView`, qui ne connaît que l'espace Réunion.
        .overlay(alignment: .trailing) { projectCardOverlay }
        .onAppear { normalizeSpace() }
        .onChange(of: meeting.kind) { _, _ in normalizeSpace() }
    }

    /// La fiche projet en panneau, glissant depuis la droite.
    @ViewBuilder
    private var projectCardOverlay: some View {
        if screen.showProjectCard, let projet = meeting.project {
            ProjectCardPanel(project: projet,
                             meeting: meeting,
                             meetings: allMeetings,
                             settings: settings,
                             isPresented: Binding(get: { screen.showProjectCard },
                                                  set: { screen.showProjectCard = $0 }))
                .transition(.move(edge: .trailing))
                .animation(.easeOut(duration: 0.18), value: screen.showProjectCard)
        }
    }

    /// Écarte un espace ou un mode que le type courant ne propose pas.
    /// Remplace les deux `onChange` qui remettaient `activeSection` sur le
    /// premier onglet visible.
    private func normalizeSpace() {
        let repli = MeetingSpaceRouting.fallback(space: screen.space,
                                                 mode: screen.mode,
                                                 for: meeting.kind)
        if screen.space != repli.space { screen.space = repli.space }
        if screen.mode != repli.mode { screen.mode = repli.mode }
    }

    /// Contenu de l'espace actif. Aucun état ici : c'est du routage.
    @ViewBuilder
    private var spaceContent: some View {
        switch screen.space {
        case .meeting:
            meetingSpace
        case .report:
            MeetingReportSpace(
                meeting: meeting,
                settings: settings,
                playhead: screen.playhead,
                editMode: $reportEditMode,
                debouncedSave: { debouncedSave() },
                saveNow: saveContext,
                onGenerate: { Task { await startReportFlow() } },
                toolbar: { generateToolbar }
            )
        case .resources:
            MeetingResourcesSpace(
                meeting: meeting,
                screen: screen,
                onImport: { fileImportTarget = .documents }
            )
        }
    }

    /// L'espace `Réunion` : bandeau d'indicateurs, contenu du mode, barre
    /// d'assistant. Tout est dans `MeetingSpaceView` — ici il ne reste que le
    /// câblage des données et des closures.
    ///
    /// Une note (`MeetingKind.note`) garde **exactement** son éditeur markdown
    /// et son `liveNotesEditorID` : les chemins `adoptPendingLiveNotes()` /
    /// `discardEmptyNoteIfNeeded()` dépendent de l'ordre de démontage SwiftUI,
    /// et le programme §2.4 interdit d'y toucher.
    @ViewBuilder
    private var meetingSpace: some View {
        if meeting.kind == .note {
            liveNotesEditor
        } else {
            MeetingSpaceView(
                meeting: meeting,
                screen: screen,
                settings: settings,
                kpi: MeetingKPIBuilder.build(meeting: meeting),
                prepareContext: MeetingPrepareBuilder.build(meeting: meeting,
                                                            allMeetings: allMeetings),
                historique: allMeetings,
                menuActions: makeMenuActions(),
                // Spec §2.4 : la bascule suit le **mode de transcription**, et
                // rien d'autre. La condition `!transcriptSegments.isEmpty` qui
                // vivait ici la masquait tant qu'aucun segment n'était
                // diarisé — donc toujours, avant la fin d'une diarisation, et
                // jamais sur le jeu de recette (écart (c) n° 5).
                showsSpeakerToggle: settings.transcriptionMode == .diarizeFirst,
                isSummarizing: isSummarizing,
                isAssistantOpen: $showAssistant,
                onSummarize: { Task { await generateShortSummary() } },
                onManageParticipants: { showParticipantsSheet = true },
                // La carte Décisions filtre la colonne de notes sur
                // `kind:decision` (spec §2.3) ; un second clic le relâche.
                onFilterDecisions: {
                    screen.toggleNoteFilter(.decision)
                    screen.mode = .live
                },
                // L'onglet Risques du rail (lot 3) : le bandeau y renvoie.
                onOpenRisks: { screen.railTab = .risques },
                onOpenMeeting: { id in openMeeting(id) },
                onToggleAction: { id in toggleTask(id) },
                onDiarize: { runDiarization() },
                onReidentify: { reidentifySpeakers() },
                onAddToManagerReport: { range, extrait, champ in
                    startManagerReportFlow(range: range, snippet: extrait, field: champ)
                },
                onShowCaptures: {
                    // Le lot 6 a retiré `showSlidesList` et son popover : les
                    // captures se lisent dans la bande du lot 7 et dans le
                    // tiroir Ressources, filtre `Captures`. Sans capture, le
                    // sélecteur de source reste la bonne destination.
                    if captureCoordinator.captureCount == 0 {
                        screen.capture.showPopover = true
                    } else {
                        screen.resources.open(filter: .captures)
                    }
                },
                onImportResources: { fileImportTarget = .documents },
                capture: captureCoordinator
            )
            .onAppear {
                // Le versement des sujets permanents dans `prepNotes` était
                // fait par l'onglet Préparation ; il suit son contenu dans le
                // mode Préparer.
                if screen.mode == .prepare {
                    PrepCarryoverService.drainStandingIntoMeeting(meeting, in: context)
                }
            }
            .onChange(of: screen.mode) { _, nouveau in
                if nouveau == .prepare {
                    PrepCarryoverService.drainStandingIntoMeeting(meeting, in: context)
                }
            }
        }
    }

    /// Génère le résumé en une phrase du mode Relire.
    /// `MeetingSummaryService.generate` est la seule définition du prompt et de
    /// la source (le lot 19 l'a extraite de la carte Résumé du dashboard, qu'il
    /// a retirée avec le dashboard lui-même).
    @MainActor
    private func generateShortSummary() async {
        guard !isSummarizing else { return }
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            try await MeetingSummaryService.generate(meeting: meeting, settings: settings)
            saveContext()
        } catch {
            reportError = error.localizedDescription
        }
    }

    /// Ouvre une autre réunion dans sa fenêtre — les « derniers points » du
    /// mode Préparer sont cliquables.
    private func openMeeting(_ id: PersistentIdentifier) {
        guard let cible = allMeetings.first(where: { $0.persistentModelID == id }) else { return }
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: cible.ensuredStableID,
            autoStartRecording: false
        )
    }

    /// Coche ou décoche une action désignée par son identifiant persistant —
    /// la liste d'actions reportées du mode Préparer ne porte que des valeurs.
    private func toggleTask(_ id: PersistentIdentifier) {
        guard let tache = meeting.tasks.first(where: { $0.persistentModelID == id }) else { return }
        tache.isCompleted.toggle()
        saveContext()
    }

    /// L'éditeur markdown du corps de la réunion, inchangé depuis l'onglet
    /// « Notes live ». Son `editorID` reste propre à la réunion.
    private var liveNotesEditor: some View {
        MarkdownNoteEditor(
            text: Binding(
                get: { meeting.liveNotes },
                set: {
                    meeting.liveNotes = $0
                    saveContext()
                    NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
                }
            ),
            editorID: liveNotesEditorID
        )
    }

    /// Crée une réunion et l'ouvre dans sa propre fenêtre.
    ///
    /// C'est le `+` de l'ancienne deuxième ligne de la barre du haut, devenu
    /// une entrée du menu de type (spec §2.1). Le projet est repris de la
    /// réunion courante : on enchaîne presque toujours sur le même dossier.
    /// L'ouverture passe par `QuickLaunchRouter`, comme tous les autres
    /// chemins qui présentent une réunion hors de la liste.
    private func createMeeting() {
        let nouvelle = Meeting(title: "", date: Date(), notes: "")
        nouvelle.project = meeting.project
        context.insert(nouvelle)
        saveContext()
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: nouvelle.ensuredStableID,
            autoStartRecording: false
        )
    }

    private func togglePlay(url: URL) {
        if player.loadedURL != url {
            do {
                try player.load(url: url)
            } catch {
                transcribeError = "Lecture impossible: \(error.localizedDescription)"
                return
            }
        }
        playhead.beginPlayback()
        player.toggle()
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func debouncedSave(delay: TimeInterval = 0.6) {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try? context.save()
        }
    }

    @MainActor
    private func retranscribe(wavURL: URL, thenGenerateReport: Bool = false) async {
        transcribeError = nil
        print("[MeetingView] retranscribe: \(wavURL.path) thenReport=\(thenGenerateReport)")
        // Segments existants supprimés DANS le job, juste avant insertion des
        // nouveaux — pas avant le démarrage du job. Annulation pendant le
        // download des modèles ou le STT préserve donc les anciens segments.
        transcriptionPhase = .transcribing
        transcriptionProgress = nil
        transcriptionProgressStatus = nil

        let queue = JobQueue.shared
        _ = queue.start(
            kind: .transcription,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title
        ) { jobID in
            do {
                try Task.checkCancellation()
                // Purge des anciens segments déléguée à
                // `TranscriptionService.persistAligned/AnonymousSegments`
                // qui efface juste avant d'insérer les nouveaux. Préserve
                // les segments existants en cas d'annulation / d'erreur STT.
                let result = try await stt.runTranscription(
                    audioURL: wavURL,
                    meeting: meeting,
                    settings: settings,
                    in: context,
                    onPhase: { phase in
                        Task { @MainActor in self.transcriptionPhase = phase }
                    },
                    onProgress: { fraction, status in
                        Task { @MainActor in
                            self.transcriptionProgress = fraction
                            self.transcriptionProgressStatus = status
                        }
                        queue.updateProgress(jobID, fraction: fraction, status: status)
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.transcriptionPhase = .idle
                    self.transcriptionProgress = nil
                    self.transcriptionProgressStatus = nil
                    // Cache embeddings pour EMA voiceprint update au 1er labeling.
                    self.screen.lastDiarizationEmbeddings = result.clusterEmbeddings
                    self.meeting.rawTranscript = result.text
                    PrepCarryoverService.carryoverUncheckedFromMeeting(
                        self.meeting,
                        settings: self.settings,
                        in: self.context
                    )
                    self.meeting.mergedTranscript = NoteMergeService.merge(
                        transcript: result.text,
                        liveNotes: self.meeting.liveNotes
                    )
                    // Fin de transcription : on revient à la séance, où la
                    // transcription est affichée à côté des notes.
                    self.screen.space = .meeting
                    self.screen.mode = .live
                    self.saveContext()
                    TeamsAutoRecordCoordinator.shared.transcriptionDidFinish(
                        meetingID: self.meeting.ensuredStableID,
                        segmentCount: result.segments.count)
                }
                print("[MeetingView] retranscribe OK: \(result.text.count) chars, \(result.segments.count) segments")
                // Enchaîne la génération du rapport « dans la foulée » si demandé
                // (flux Transcrire + Rapport en un clic).
                if thenGenerateReport {
                    Task { @MainActor in await self.generateReport() }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.transcriptionPhase = .idle
                    self.transcriptionProgress = nil
                    self.transcriptionProgressStatus = nil
                }
                throw CancellationError()
            } catch {
                await MainActor.run {
                    self.transcribeError = error.localizedDescription
                    self.transcriptionPhase = .error(error.localizedDescription)
                    TeamsAutoRecordCoordinator.shared.transcriptionDidFinish(
                        meetingID: self.meeting.ensuredStableID, segmentCount: 0)
                }
                print("[MeetingView] retranscribe FAILED: \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Le câblage des ressources (import, dépôt, `⌘⇧V`, partage à l'écran)
    /// vit dans `ResourceCoordinator` (lot 6). Les quatre fonctions d'import
    /// qui vivaient ici — `handleFileDrop`, `importDocuments` et leurs deux
    /// `@State` — en sont parties : le programme §2.4 point 1 interdit
    /// d'ajouter quoi que ce soit à ce fichier, et elles ne parlaient que de
    /// ressources.
    /// Le pilotage de la capture (lot 7) : catalogue de sources, ouverture de
    /// session, geste manuel. Valeur reconstruite à chaque rendu, comme
    /// `resourceCoordinator` — elle ne retient rien, l'état vit dans
    /// `screen.capture` et la session dans `captureService`.
    private var captureCoordinator: CaptureSessionCoordinator {
        CaptureSessionCoordinator(meeting: meeting,
                                  screen: screen,
                                  service: captureService,
                                  context: context)
    }

    private var resourceCoordinator: ResourceCoordinator {
        ResourceCoordinator(meeting: meeting,
                            context: context,
                            state: screen.resources,
                            playhead: screen.playhead)
    }

    // MARK: - Participants

    private var availableCollaborators: [Collaborator] {
        let ids = Set(meeting.participants.map(\.persistentModelID))
        return allCollaborators
            .filter { !ids.contains($0.persistentModelID) }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func addParticipant(_ c: Collaborator) {
        meeting.participants.append(c)
        meeting.setParticipantStatus(.present, for: c)
        saveContext()
    }

    private func removeParticipant(_ c: Collaborator) {
        meeting.participants.removeAll { $0.persistentModelID == c.persistentModelID }
        meeting.clearParticipantStatus(for: c)
        saveContext()
    }

    /// Retire tous les participants de la réunion. Les fiches « jetables » —
    /// collaborateurs présents dans aucune autre réunion et sans aucune donnée
    /// rattachée (entretiens, notes, actions, projets, empreinte vocale, épinglage)
    /// — sont supprimées de l'annuaire au passage : typiquement les fiches créées
    /// par import calendrier ou ad-hoc pour cette seule réunion.
    private func removeAllParticipants() {
        let removed = meeting.participants
        meeting.participants.removeAll()
        for c in removed {
            meeting.clearParticipantStatus(for: c)
            if isThrowawayCollaborator(c) {
                context.delete(c)
            }
        }
        saveContext()
    }

    /// `true` si le collaborateur ne porte aucune donnée en dehors de la réunion
    /// courante : aucune autre réunion, ni entretien, action, projet (CP/AT),
    /// empreinte vocale ou épinglage sidebar. Une note est un `Meeting` de kind
    /// `.note` : elle est déjà couverte par `otherMeetings`, pas de vérification
    /// séparée à faire.
    private func isThrowawayCollaborator(_ c: Collaborator) -> Bool {
        let otherMeetings = c.meetings.filter { $0.persistentModelID != meeting.persistentModelID }
        return otherMeetings.isEmpty
            && c.assignedTasks.isEmpty
            && c.projectsAsManager.isEmpty
            && c.projectsAsArchitect.isEmpty
            && c.voicePrint == nil
            && c.pinLevel == 0
    }

    private func setParticipantStatus(_ status: MeetingAttendanceStatus, for collaborator: Collaborator) {
        meeting.setParticipantStatus(status, for: collaborator)
        saveContext()
    }

    private func participantStatus(for collaborator: Collaborator) -> MeetingAttendanceStatus {
        meeting.participantStatus(for: collaborator)
    }

    /// Crée un `Collaborator` adhoc (réutilisable) et l'ajoute à la réunion.
    private func addAdhocParticipant() {
        let name = screen.newAdhocName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if let existing = allCollaborators.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            addParticipant(existing)
        } else {
            let c = Collaborator(name: name, role: "Ad-hoc")
            c.isAdhoc = true
            c.pinLevel = 0
            context.insert(c)
            addParticipant(c)
        }
        screen.newAdhocName = ""
    }

    /// Applique l'événement choisi dans le sélecteur. La logique vit dans
    /// `MeetingCalendarSync` : ce n'est pas une vue.
    private func importCalendarEvent(_ event: CalendarMeetingEvent) {
        calendarImportError = nil
        MeetingCalendarSync.apply(event: event,
                                  to: meeting,
                                  knownCollaborators: allCollaborators,
                                  in: context)
        saveContext()
    }

    /// Recharge la réunion depuis son événement calendrier. Appelée par les
    /// deux boutons Resync (feuille Détails et gestion des participants).
    @MainActor
    private func resyncFromCalendarInMeetingView() {
        MeetingCalendarSync.resync(meeting: meeting, settings: settings, in: context)
    }

    // MARK: - Actions panel

    // MARK: - Recording actions

    /// Le coordinateur Teams ne possède pas le pipeline de démarrage / arrêt
    /// / transcription / rapport : il dépose une demande, et cette fenêtre —
    /// si c'est la sienne — la consomme une seule fois et exécute son propre
    /// chemin. `consumePendingRequest` renvoie `nil` pour toute autre réunion.
    private func consumeTeamsRequestIfAny() {
        guard let request = TeamsAutoRecordCoordinator.shared
            .consumePendingRequest(for: meeting.ensuredStableID) else { return }
        switch request {
        case .startRecording:
            // Même garde que le démarrage automatique : jamais deux captures.
            guard !didAutoStart, !recorder.isRecording else { return }
            didAutoStart = true
            Task { await startRecording() }
        case .stopAndFinalize: Task { await stopRecordingAndTranscribe() }
        case .generateReport:  Task { await generateReport() }
        case .retryTranscription:
            guard let url = meeting.wavFileURL else {
                // Rien à retranscrire : on le dit au coordinateur plutôt que de le laisser attendre.
                TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
                return
            }
            Task { await retranscribe(wavURL: url) }
        }
    }

    /// Seule une réunion liée à un événement Teams demande la seconde piste :
    /// une réunion en présentiel n'a pas d'audio distant à capter, et le mode
    /// classique reste strictement inchangé. Partagé par les deux démarrages —
    /// une reprise d'enregistrement doit capter les mêmes pistes que le premier.
    private var captureMode: TeamsAudioCaptureMode {
        (meeting.teamsJoinURL?.isEmpty == false) ? settings.teamsAudioCaptureMode : .microOnly
    }

    private func startRecording() async {
        if recorder.isRecording && recorder.activeMeetingID != meeting.stableID {
            recorder.lastError = "Un enregistrement est déjà en cours pour une autre réunion."
            TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
            return
        }
        // Ouvre le flux live AVANT de démarrer le recorder (la continuation doit
        // exister dès le 1er tap pour que start() puisse construire le TapSink),
        // mais on ne lance sa consommation (begin) qu'APRÈS le succès de start() :
        // sinon un throw synchrone de start() (ex. double-tap → alreadyRecording)
        // court contre la Task begin() et peut la faire démarrer sur un flux
        // jamais terminé → hang infini.
        let liveStream: AsyncStream<[Float]>? = settings.liveTranscriptionEnabled
            ? recorder.makeAudioStream() : nil
        do {
            let url = try await recorder.start(meetingID: meeting.ensuredStableID,
                                               captureMode: captureMode)
            // start() a réussi : on peut maintenant démarrer la transcription live.
            if let liveStream {
                Task {
                    await LiveTranscriptionService.shared.begin(
                        audioStream: liveStream,
                        language: stt.language,
                        engineKind: settings.transcriptionEngine,
                        variant: settings.voxtralVariant)
                }
                // La transcription live s'affiche dans le widget (Vue d'ensemble)
                // et dans l'onglet « Transcription » — pas de bascule d'onglet.
            }
            meeting.wavFilePath = url.path
            // Origine de l'axe temps partagé (notes horodatées, captures,
            // frise). Posée une seule fois : un enregistrement complémentaire
            // ne doit pas décaler les notes déjà prises.
            if meeting.recordingStartedAt == nil {
                meeting.recordingStartedAt = Date()
            }
            if let startedAt = meeting.recordingStartedAt {
                playhead.beginRecording(startedAt: startedAt)
            }
            saveContext()
        } catch {
            recorder.lastError = error.localizedDescription
            // Défense : no-op si begin() n'a jamais démarré (start() a throw
            // avant qu'on ne lance la consommation du flux live).
            LiveTranscriptionService.shared.abort()
            // Sans ce signal le coordinateur resterait en `.recording` sur une
            // capture qui n'existe pas, puis en `.finalizing` pour toujours.
            // Mais un double démarrage sur la MÊME réunion jette
            // `alreadyRecording` alors que la capture, elle, tourne : le perdant
            // de la course ne doit pas abattre le parcours du gagnant.
            if !recorder.isRecording(for: meeting.ensuredStableID) {
                TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
            }
        }
    }

    /// Démarre un enregistrement complémentaire qui sera concaténé au WAV
    /// existant lors du `stop()`. Le WAV courant est conservé et fusionné
    /// avec le nouveau pour produire un fichier unique.
    private func startAppendRecording() async {
        guard let existing = meeting.wavFileURL, fileExists(existing) else {
            await startRecording()
            return
        }
        if recorder.isRecording {
            recorder.lastError = "Un enregistrement est déjà en cours."
            return
        }
        pendingAppendBaseURL = existing
        // Même câblage que startRecording() : le flux live est préparé avant
        // start() mais sa consommation (begin) n'est lancée qu'après succès,
        // pour éviter la course avec un throw synchrone de start().
        let liveStream: AsyncStream<[Float]>? = settings.liveTranscriptionEnabled
            ? recorder.makeAudioStream() : nil
        do {
            let url = try await recorder.start(meetingID: meeting.ensuredStableID,
                                               captureMode: captureMode)
            // start() a réussi : on peut maintenant démarrer la transcription live.
            if let liveStream {
                Task {
                    await LiveTranscriptionService.shared.begin(
                        audioStream: liveStream,
                        language: stt.language,
                        engineKind: settings.transcriptionEngine,
                        variant: settings.voxtralVariant)
                }
                // Live affiché dans le widget + l'onglet « Transcription ».
            }
            // On laisse meeting.wavFilePath pointer sur l'ancien jusqu'à la
            // concaténation post-stop ; en cas d'arrêt anormal, l'utilisateur
            // garde son enregistrement initial. La nouvelle URL est conservée
            // par le recorder via currentFileURL.
            _ = url
        } catch {
            pendingAppendBaseURL = nil
            recorder.lastError = error.localizedDescription
            // Défense : no-op si begin() n'a jamais démarré (start() a throw
            // avant qu'on ne lance la consommation du flux live).
            LiveTranscriptionService.shared.abort()
        }
    }

    /// Attache un WAV/audio déjà présent sur disque au meeting courant.
    /// Si le fichier vit déjà sous `recordings/`, on pointe dessus directement.
    /// Sinon on copie sous `recordings/<UUID>.<ext>` pour stabiliser le chemin.
    /// Les fichiers compressés (m4a, mp3, mp4/mov…) sont transcodés en WAV
    /// 16 kHz mono résilient via `AudioImportService.prepareForPipeline`.
    /// La durée est lue via `AVAudioFile` puis stockée dans `meeting.durationSeconds`.
    private func importExistingWAV(result: Result<[URL], Error>) async {
        wavImportError = nil
        do {
            guard let src = try result.get().first else { return }

            let needsScope = src.startAccessingSecurityScopedResource()
            defer { if needsScope { src.stopAccessingSecurityScopedResource() } }

            let fm = FileManager.default
            let recordingsDir = URL.applicationSupportDirectory
                .appending(path: "OneToOne", directoryHint: .isDirectory)
                .appending(path: "recordings", directoryHint: .isDirectory)
            try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

            let target: URL
            if src.deletingLastPathComponent().standardized == recordingsDir.standardized {
                target = src
            } else {
                let ext = src.pathExtension.isEmpty ? "wav" : src.pathExtension
                target = recordingsDir.appending(path: "\(UUID().uuidString).\(ext)")
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: src, to: target)
            }

            // Tout le pipeline aval (waveform, STT, diarisation, éditeur) lit via
            // AVAudioFile. Les fichiers compressés sont transcodés en WAV 16 kHz
            // mono résilient (paquets corrompus → silence) — seul format sans piège.
            let (audioURL, transcoded) = try await AudioImportService.prepareForPipeline(target, outputDir: recordingsDir)
            if transcoded, target != src {
                try? fm.removeItem(at: target)  // copie intermédiaire devenue inutile
            }

            // Lève si le fichier préparé n'a aucun échantillon : mieux vaut un
            // message que le couple « chemin audio valide + durée nulle », qui
            // renvoyait ensuite `Transcrire + Rapport` dans l'export
            // AVFoundation (défaut du 2026-09-08).
            let durationSeconds = try AudioImportService.pipelineDurationSeconds(of: audioURL)

            meeting.wavFilePath = audioURL.path
            meeting.durationSeconds = durationSeconds
            saveContext()
            print("[MeetingView] importWAV → \(audioURL.path) duration=\(durationSeconds)s")
        } catch {
            wavImportError = error.localizedDescription
            print("[MeetingView] importWAV failed: \(error)")
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard recorder.activeMeetingID == nil || recorder.activeMeetingID == meeting.stableID else {
            recorder.lastError = "Cet enregistrement appartient à une autre réunion."
            TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
            return
        }
        guard let stopped = recorder.stop() else { return }

        // Le flux audio est terminé par recorder.stop() (continuation.finish()),
        // donc end() peut drainer et se terminer sans bloquer. Les segments
        // horodatés sont consommés en Task 8 (nettoyage + diarisation) plus
        // bas, via finalizeLiveTranscript.
        // Garde sur l'état réel du service (isLive), pas sur le réglage : si
        // l'utilisateur désactive liveTranscriptionEnabled EN COURS
        // d'enregistrement (Réglages = fenêtre séparée), une session live
        // encore active ne doit pas fuiter.
        let liveSegments = LiveTranscriptionService.shared.isLive
            ? await LiveTranscriptionService.shared.end()
            : []

        // Laisse le FS finaliser le header WAV avant de le relire.
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Capturé AVANT la concaténation ci-dessous, qui remet
        // `pendingAppendBaseURL` à nil une fois le merge effectué. En mode
        // append, les timestamps live ne couvrent que le nouveau segment (pas
        // l'audio concaténé complet) → la finalisation live est exclue, le
        // chemin batch (re-STT complet) est forcé.
        let wasAppend = pendingAppendBaseURL != nil

        // Concaténation si on était en mode "ajout d'un enregistrement".
        var finalURL = stopped.url
        var totalDuration = stopped.duration
        if let baseURL = pendingAppendBaseURL, fileExists(baseURL) {
            do {
                let mergedURL = AudioRecorderService.recordingsDirectory
                    .appending(path: "\(UUID().uuidString).wav")
                try AudioRecorderService.concatenateWAVs(first: baseURL, second: stopped.url, output: mergedURL)
                let mergedFile = try AVAudioFile(forReading: mergedURL)
                totalDuration = Double(mergedFile.length) / mergedFile.processingFormat.sampleRate
                // Nettoyage : on supprime le base et le segment 2 (gardés en log mais inutiles).
                try? FileManager.default.removeItem(at: baseURL)
                try? FileManager.default.removeItem(at: stopped.url)
                finalURL = mergedURL
                print("[MeetingView] append → concat OK \(mergedURL.path) duration=\(totalDuration)s")
            } catch {
                transcribeError = "Concaténation échouée : \(error.localizedDescription). Le nouvel enregistrement remplace l'ancien."
                print("[MeetingView] concat FAILED: \(error)")
            }
            pendingAppendBaseURL = nil
        }

        meeting.durationSeconds = Int(totalDuration.rounded())
        meeting.wavFilePath = finalURL.path
        saveContext()

        print("[MeetingView] stop → WAV=\(finalURL.path) duration=\(totalDuration)s")

        // Sanity checks : fichier existe, taille non nulle, durée > 1s.
        let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        guard fileSize > 44 else {
            transcribeError = "Fichier audio vide (\(fileSize) octets). Enregistrement échoué."
            print("[MeetingView] WAV invalide: \(fileSize) octets")
            TeamsAutoRecordCoordinator.shared.transcriptionDidFinish(
                meetingID: meeting.ensuredStableID, segmentCount: 0)
            return
        }
        guard totalDuration >= 1.0 else {
            transcribeError = "Enregistrement trop court (\(String(format: "%.1f", totalDuration))s). STT désactivé."
            print("[MeetingView] durée trop courte: \(totalDuration)s")
            TeamsAutoRecordCoordinator.shared.transcriptionDidFinish(
                meetingID: meeting.ensuredStableID, segmentCount: 0)
            return
        }

        transcribeError = nil
        do {
            print("[MeetingView] → transcribe start (with diarization + speaker matching)…")
            // Purge des segments existants déléguée à TranscriptionService
            // (atomique avec l'insertion des nouveaux — préserve les anciens
            // si STT échoue ou est annulé).
            transcriptionPhase = .transcribing
            transcriptionProgress = nil
            transcriptionProgressStatus = nil
            // Live actif (et pas un append, cf. note ci-dessus) → pas de 2e
            // passe STT : nettoyage + diarisation seule + attribution par
            // timestamps. Sinon (live désactivé, ou append) → pipeline batch
            // inchangé.
            let useLive = !liveSegments.isEmpty && !wasAppend
            let result: STTResult
            if useLive {
                result = try await stt.finalizeLiveTranscript(
                    segments: liveSegments,
                    audioURL: finalURL,
                    meeting: meeting,
                    settings: settings,
                    in: context,
                    onPhase: { phase in
                        Task { @MainActor in self.transcriptionPhase = phase }
                    },
                    onProgress: { fraction, status in
                        Task { @MainActor in
                            self.transcriptionProgress = fraction
                            self.transcriptionProgressStatus = status
                        }
                    }
                )
            } else {
                result = try await stt.runTranscription(
                    audioURL: finalURL,
                    meeting: meeting,
                    settings: settings,
                    in: context,
                    onPhase: { phase in
                        Task { @MainActor in self.transcriptionPhase = phase }
                    },
                    onProgress: { fraction, status in
                        Task { @MainActor in
                            self.transcriptionProgress = fraction
                            self.transcriptionProgressStatus = status
                        }
                    }
                )
            }
            transcriptionPhase = .idle
            transcriptionProgress = nil
            transcriptionProgressStatus = nil
            print("[MeetingView] ← transcribe OK: \(result.text.count) chars, \(result.segments.count) segments")
            // Cache les embeddings pour permettre l'EMA voiceprint update au
            // premier labeling manuel (sinon il faut attendre re-diarisation).
            screen.lastDiarizationEmbeddings = result.clusterEmbeddings
            meeting.rawTranscript = result.text
            PrepCarryoverService.carryoverUncheckedFromMeeting(
                meeting,
                settings: settings,
                in: context
            )
            meeting.mergedTranscript = NoteMergeService.merge(
                transcript: result.text,
                liveNotes: meeting.liveNotes
            )
            screen.space = .meeting
            screen.mode = .live
            saveContext()
            // Les deux branches ci-dessus (finalisation live et re-STT batch)
            // convergent ici : un seul compte rendu par transcription tentée.
            TeamsAutoRecordCoordinator.shared.transcriptionDidFinish(
                meetingID: meeting.ensuredStableID,
                segmentCount: result.segments.count)
        } catch {
            transcribeError = error.localizedDescription
            transcriptionPhase = .error(error.localizedDescription)
            print("[MeetingView] transcribe FAILED: \(error.localizedDescription)")
            TeamsAutoRecordCoordinator.shared.transcriptionDidFinish(
                meetingID: meeting.ensuredStableID, segmentCount: 0)
        }
    }

    // MARK: - Generate toolbar

    /// Toolbar minimaliste au-dessus du rapport : template affiché + bouton unique Générer.
    @ViewBuilder
    private var generateToolbar: some View {
        HStack {
            if let template = meeting.reportTemplate {
                Text("Template :")
                    .font(.caption).foregroundStyle(.secondary)
                Text(template.name).font(.caption.bold())
            } else {
                Text("Template : Auto").font(.caption).foregroundStyle(.secondary)
            }

            Picker("", selection: $reportEditMode) {
                Image(systemName: "eye").tag(false)
                Image(systemName: "pencil").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Aperçu / Éditer markdown")
            .padding(.leading, 8)

            Spacer()
            Button {
                Task { await runGenerate() }
            } label: {
                Label(isGenerating || isGeneratingReport ? "Génère…" : "Générer",
                      systemImage: "wand.and.stars")
            }
            .disabled(isGenerating || isGeneratingReport || meeting.rawTranscript.isEmpty)
            .help("Génère un nouveau rapport (écrase la version actuelle)")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @MainActor
    private func runGenerate() async {
        await generateReport()
    }

    /// Throttle simple actor-based pour limiter les updates UI streaming.
    /// `shouldEmit()` retourne `true` au plus 1× par `minInterval` secondes.
    private actor ProgressThrottle {
        let minInterval: TimeInterval
        var lastEmit: Date = .distantPast
        var lastPhase = -1
        init(minInterval: TimeInterval) { self.minInterval = minInterval }
        func shouldEmit() -> Bool {
            let now = Date()
            if now.timeIntervalSince(lastEmit) >= minInterval {
                lastEmit = now
                return true
            }
            return false
        }
        func shouldEmit(activity: AIClient.Activity) -> Bool {
            let phase: Int
            switch activity {
            case .waiting: phase = 0
            case .reasoning: phase = 1
            case .writing: phase = 2
            }
            if phase != lastPhase {
                lastPhase = phase
                lastEmit = Date()
                return true
            }
            return shouldEmit()
        }
    }

    // MARK: - Report generation

    /// Point d'entrée du bouton « Rapport ». Si la transcription n'existe pas
    /// encore mais qu'un audio est disponible, transcrit d'abord puis enchaîne
    /// le rapport automatiquement (« dans la foulée »). Sinon génère directement.
    private func startReportFlow() async {
        guard !isGenerating && !isGeneratingReport, !stt.isTranscribing else {
            print("[Rapport] flux déjà en cours, abort")
            return
        }
        if meeting.rawTranscript.isEmpty {
            // Le bouton est désarmé sans audio (`hasPlayableAudio`), mais le
            // fichier peut avoir disparu depuis le dernier rendu : un message
            // plutôt qu'un clic sans effet.
            guard let wav = meeting.wavFileURL else {
                reportError = "Cette réunion n'a ni transcription ni fichier audio : "
                    + "enregistrez ou importez un audio avant de demander un rapport."
                return
            }
            await retranscribe(wavURL: wav, thenGenerateReport: true)
        } else {
            await generateReport()
        }
    }

    private func generateReport() async {
        guard !isGenerating && !isGeneratingReport else {
            print("[Rapport] génération déjà en cours, abort")
            return
        }
        guard !meeting.rawTranscript.isEmpty else {
            reportError = "Le rapport a besoin d'une transcription : la transcription de cette "
                + "réunion est vide."
            TeamsAutoRecordCoordinator.shared.reportDidFinish(
                meetingID: meeting.ensuredStableID, succeeded: false)
            return
        }

        // Refresh merged transcript au cas où l'utilisateur a édité les notes.
        meeting.mergedTranscript = NoteMergeService.merge(
            transcript: meeting.rawTranscript,
            liveNotes: meeting.liveNotes
        )

        reportError = nil
        isGeneratingReport = true
        reportProgressChars = 0
        reportElapsedSeconds = 0
        reportActivity = AIReportProgress()

        let queue = JobQueue.shared
        _ = queue.start(
            kind: .report,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title
        ) { jobID in
            // Les durées démarrent à l'exécution, pas pendant l'attente en file.
            self.reportActivity.start(.preparing)
            let throttle = ProgressThrottle(minInterval: 0.25)
            let activityThrottle = ProgressThrottle(minInterval: 0.25)
            let start = Date()
            let elapsedTimer = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { break }
                    self.reportElapsedSeconds = Int(Date().timeIntervalSince(start))
                    queue.updateProgress(jobID,
                                          fraction: nil,
                                          status: "\(self.reportElapsedSeconds)s · \(self.reportActivity.label)"
                                            + (self.reportActivity.warning().map { " — \($0)" } ?? ""))
                }
            }
            defer {
                elapsedTimer.cancel()
                Task { @MainActor in
                    self.isGeneratingReport = false
                    self.reportProgressChars = 0
                    self.reportElapsedSeconds = 0
                }
            }

            try Task.checkCancellation()

            let generationStart = Date()
            // RAG sémantique : récupère extraits pertinents des réunions
            // antérieures, ajouté en arrière-plan du prompt.
            let ragContext = await self.fetchHistoricalContext()
            do {
                try Task.checkCancellation()
                let report = try await AIReportService.generate(
                    meeting: meeting,
                    in: context,
                    settings: settings,
                    additionalContext: ragContext,
                    onProgress: { partial in
                        // Note : signature non-throwing — la cancellation est
                        // vérifiée juste après l'appel `generate(...)`. Côté
                        // streaming on se contente de pousser la progression.
                        guard await throttle.shouldEmit() else { return }
                        let count = partial.count
                        await MainActor.run {
                            self.reportProgressChars = count
                            self.reportActivity.receive(.writing(count))
                        }
                    },
                    onActivity: { activity in
                        guard await activityThrottle.shouldEmit(activity: activity) else { return }
                        await MainActor.run {
                            self.reportActivity.receive(activity)
                        }
                    },
                    onMarkdownReady: { markdown in
                        try Task.checkCancellation()
                        // Une seule révision : la seconde passe enrichit les
                        // faits, elle ne crée pas un deuxième rapport identique.
                        self.apply(report: MeetingReportData(summary: markdown,
                            keyPoints: [], decisions: [], openQuestions: [], actions: [], alerts: []))
                        try self.context.save()
                        self.reportActivity.start(.extracting)
                        queue.updateProgress(jobID, fraction: nil, status: self.reportActivity.label)
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.apply(report: report, createRevision: false)
                    self.meeting.reportGenerationDurationSeconds = Date().timeIntervalSince(generationStart)
                    self.saveContext()
                    // Le rapport écrit, l'écran passe en **Relire** et pose le
                    // curseur sur la première action sans responsable (spec
                    // §2.2 et §2.7, lot 5). L'espace Rapport reste à un clic,
                    // dans la nav latérale du poste de pilotage.
                    ReviewState.apresGenerationDuRapport(self.screen)
                    TeamsAutoRecordCoordinator.shared.reportDidFinish(
                        meetingID: self.meeting.ensuredStableID, succeeded: true)
                }

                // Suggestion de thèmes post-rapport (non bloquant pour l'UI,
                // rejouée à chaque génération).
                Task { @MainActor in await self.suggestTags() }

                // Indexation RAG post-rapport (non bloquant pour l'UI).
                Task.detached { @MainActor in
                    do {
                        try await RAGIndexer.reindex(meeting: meeting, context: context)
                    } catch {
                        print("[MeetingView] RAG reindex échoué: \(error.localizedDescription)")
                    }
                }
            } catch is CancellationError {
                // Une annulation laisse la réunion prête à retenter : le
                // coordinateur la traduit par le popup « Rapport non généré ».
                await MainActor.run {
                    TeamsAutoRecordCoordinator.shared.reportDidFinish(
                        meetingID: self.meeting.ensuredStableID, succeeded: false)
                }
                throw CancellationError()
            } catch {
                await MainActor.run {
                    self.reportError = error.localizedDescription
                    TeamsAutoRecordCoordinator.shared.reportDidFinish(
                        meetingID: self.meeting.ensuredStableID, succeeded: false)
                }
                throw error
            }
        }
    }

    /// Demande à l'IA des thèmes pour cette réunion et les expose en chips
    /// « fantômes ». Non bloquant, silencieux en cas d'échec (liste vide), et
    /// jamais appliqué automatiquement : l'utilisateur accepte ou ignore.
    @MainActor
    private func suggestTags() async {
        guard !isSuggestingTags else { return }
        let transcript = meeting.mergedTranscript.isEmpty ? meeting.rawTranscript : meeting.mergedTranscript
        let source = MeetingTagSuggester.sourceText(summary: meeting.summary, transcript: transcript)
        guard !source.isEmpty else { return }

        let existing = ((try? context.fetch(FetchDescriptor<MeetingTag>())) ?? [])
            .filter { !$0.isArchived }
            .map(\.name)

        isSuggestingTags = true
        let names = await MeetingTagSuggester.suggest(
            summary: source,
            existingTags: existing,
            settings: settings
        )
        isSuggestingTags = false

        // Un thème déjà posé sur la réunion n'est pas re-proposé.
        let linked = Set(meeting.tags.map { MeetingTag.normalizedKey($0.name) })
        screen.suggestedTagNames = names.filter { !linked.contains(MeetingTag.normalizedKey($0)) }
    }

    /// Retourne un bloc texte avec les extraits pertinents des réunions précédentes.
    /// Vide si rien à récupérer ou si l'embedding Ollama échoue.
    private func fetchHistoricalContext() async -> String {
        // Scope dynamique selon le type de réunion.
        var scope = RAGQuery.Scope()
        scope.excludeMeetingPID = meeting.persistentModelID

        switch meeting.kind {
        case .project:
            scope.projectPID = meeting.project?.persistentModelID
            guard scope.projectPID != nil else { return "" }
        case .oneToOne:
            scope.collaboratorPID = meeting.participants.first?.persistentModelID
            guard scope.collaboratorPID != nil else { return "" }
        case .manager:
            scope.collaboratorPID = meeting.participants.first?.persistentModelID
            guard scope.collaboratorPID != nil else { return "" }
        case .global, .work, .note, .workshop:
            return ""  // pas d'enrichissement historique hors scope clair
        }

        // Requête synthétique courte pour l'embedding (les 2000 premiers chars
        // de la transcription donnent un bon résumé sémantique).
        let query = String(meeting.mergedTranscript.prefix(2000))
        guard !query.isEmpty else { return "" }

        do {
            let results = try await RAGQuery.search(
                query: query,
                topK: 5,
                scope: scope,
                context: context
            )
            guard !results.isEmpty else { return "" }

            let lines = results.enumerated().map { idx, r -> String in
                let date = r.chunk.meeting?.date.formatted(date: .abbreviated, time: .omitted) ?? "?"
                let title = r.chunk.meeting?.title ?? "réunion sans titre"
                return "[\(idx + 1)] \(date) — \(title) (sim=\(String(format: "%.2f", r.similarity))):\n\(r.chunk.text)"
            }
            return lines.joined(separator: "\n\n")
        } catch {
            print("[MeetingView] RAG search échoué: \(error.localizedDescription)")
            return ""
        }
    }

    private func apply(report: MeetingReportData, createRevision: Bool = true) {
        // Le texte est déjà publié pendant l'extraction : ne pas écraser une
        // éventuelle correction manuelle lorsque les faits arrivent ensuite.
        if createRevision { meeting.summary = report.summary }
        meeting.keyPoints = report.keyPoints
        meeting.decisions = report.decisions
        meeting.openQuestions = report.openQuestions

        // Snapshot v_n+1 — chaque génération crée une nouvelle révision pour
        // pouvoir comparer/restaurer un draft antérieur.
        if createRevision {
            let nextVersion = (meeting.reportRevisions.map(\.version).max() ?? 0) + 1
            let rev = ReportRevision(
                meeting: meeting,
                version: nextVersion,
                body: report.summary,
                critique: "",
                writerMessage: "",
                isValidated: false
            )
            context.insert(rev)
        }

        for a in report.actions {
            let task = ActionTask(title: a.title)
            task.meeting = meeting
            task.project = meeting.project
            if let iso = a.deadlineISO {
                task.dueDate = ISO8601DateFormatter().date(from: iso)
                    ?? DateFormatter.yyyyMMdd.date(from: iso)
            }
            if let assignee = a.assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
               !assignee.isEmpty {
                if let match = CollaboratorMatcher.match(name: assignee, in: meeting, all: allCollaborators) {
                    task.collaborator = match
                } else {
                    task.unresolvedAssigneeName = assignee
                }
            }
            context.insert(task)
        }

        for a in report.alerts {
            let alert = ProjectAlert(title: a.title, detail: a.detail, severity: a.severity)
            alert.project = meeting.project
            alert.meeting = meeting
            context.insert(alert)
        }

        saveContext()
        screen.space = .report
    }

    // MARK: - Tasks

    // La création d'action a quitté ce fichier : elle vit dans
    // `ActionComposerService.creer`, appelée par le composeur du rail
    // (spec §2.5). C'est elle qui consomme `pendingActionDraft` et qui place
    // l'action neuve en tête de son groupe.

    /// Défaut malin du destinataire à la 1re apparition : en 1:1, on pré-remplit
    /// « Collaborateur » avec le partenaire ; sinon « Moi ». Une seule fois.
    private func applyActionDraftDefaultsIfNeeded() {
        guard !screen.didApplyActionDefaults else { return }
        screen.didApplyActionDefaults = true
        if meeting.kind == .oneToOne, let partner = meeting.participants.first {
            screen.newTaskAudience = .collaborateur
            screen.selectedCollaborator = partner
        } else {
            screen.newTaskAudience = .moi
        }
    }

    // MARK: - Utils

    private func saveContext() {
        do { try context.save() } catch { print("[MeetingView] save FAILED: \(error)") }
    }

    /// Résout le texte source complet correspondant à un champ de rapport
    /// manager (`mergedTranscript`, `transcript`, `summary`, `notes`,
    /// `liveNotes`) ; chaîne vide pour un champ inconnu.
    /// Démarre le flux d'ajout d'un extrait au rapport manager : pré-remplit une
    /// élaboration de repli immédiate, ouvre la feuille de classification puis
    /// lance en parallèle la catégorisation et l'élaboration IA.
    private func startManagerReportFlow(range: NSRange, snippet: String, field: String) {
        mgrSuggestedCategory = nil
        mgrSuggestedElaboration = nil
        isMgrSuggestingCategory = true
        isMgrElaborating = true

        // Compute deterministic context for both initial elaboration fallback
        // (shown immediately) and the AI prompt context.
        let fullText = ManagerReportService.sourceText(field: field, in: meeting)
        let ctx = SentenceContextExtractor.extractContext(text: fullText, range: range)
        // Pre-fill the elaboration field with raw context+snippet so user has
        // something usable instantly, even before AI returns or if AI fails.
        mgrInitialElaboration = ManagerSnippetElaborator.fallback(
            contextBefore: ctx.before, snippet: snippet, contextAfter: ctx.after
        )

        // Setting `pendingMgrSelection` triggers `.sheet(item:)` atomically.
        pendingMgrSelection = PendingMgrSelection(range: range, snippet: snippet, field: field)

        // Fire category classifier and snippet elaborator in parallel.
        Task { @MainActor in
            let suggested = await ManagerCategoryClassifier.classify(
                snippet: snippet,
                projectName: meeting.project?.name,
                settings: settings
            )
            mgrSuggestedCategory = suggested
            isMgrSuggestingCategory = false
        }

        Task { @MainActor in
            let outcome = await ManagerSnippetElaborator.elaborate(
                snippet: snippet,
                contextBefore: ctx.before,
                contextAfter: ctx.after,
                projectName: meeting.project?.name,
                sourceMeetingTitle: meeting.title,
                sourceMeetingDate: meeting.date,
                settings: settings
            )
            switch outcome {
            case .ai(let text):
                mgrSuggestedElaboration = text
                mgrElaborationFromAI = true
                mgrElaborationFallbackReason = ""
            case .fallback(let text, let reason):
                mgrSuggestedElaboration = text
                mgrElaborationFromAI = false
                mgrElaborationFallbackReason = reason
            }
            isMgrElaborating = false
        }
    }

    /// Persiste l'extrait sélectionné comme item de rapport manager (catégorie,
    /// tag, texte élaboré, contexte de phrase) puis ferme la feuille.
    private func confirmManagerItem(pending: PendingMgrSelection,
                                    category: String,
                                    tag: String,
                                    elaboratedText: String,
                                    aiSuggested: String?) {
        let fullText = ManagerReportService.sourceText(field: pending.field, in: meeting)
        let ctx = SentenceContextExtractor.extractContext(text: fullText, range: pending.range)
        do {
            _ = try ManagerReportService.add(
                snippet: pending.snippet,
                sourceField: pending.field,
                range: pending.range,
                sourceMeeting: meeting,
                contextBefore: ctx.before,
                contextAfter: ctx.after,
                elaboratedText: elaboratedText,
                category: category,
                tag: tag,
                aiSuggestedCategory: aiSuggested,
                in: context
            )
            try context.save()
        } catch {
            print("[Manager] add failed: \(error)")
        }
        pendingMgrSelection = nil
    }

    /// Launch VAD diarization on the meeting's audio. Re-assigns speakerID
    /// across all segments based on the detected turn boundaries.
    private func runDiarization() {
        guard let wavPath = meeting.wavFilePath, !wavPath.isEmpty else { return }
        let url = URL(fileURLWithPath: wavPath)
        let durationSec = TimeInterval(meeting.durationSeconds)
        Task.detached(priority: .userInitiated) {
            let turns = DiarizationService.detectTurns(
                audioURL: url, totalDurationSec: max(1, durationSec)
            )
            await MainActor.run {
                applySpeakerTurns(turns)
            }
        }
    }

    /// Re-runs the Pyannote speech-swift diarization on the existing wav to
    /// rebuild per-cluster embeddings + re-match against current voiceprints.
    /// Does NOT re-transcribe — only updates speaker badges + assignments.
    @ViewBuilder
    private var transcriptionPhaseBanner: some View {
        if transcriptionPhase.isActive {
            HStack(spacing: 10) {
                if let pct = transcriptionProgress {
                    ProgressView(value: pct).controlSize(.small).frame(width: 90)
                    Text("\(Int(pct * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(transcriptionPhase.label).font(.caption)
                if let status = transcriptionProgressStatus, !status.isEmpty {
                    Text("· \(status)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.2)), alignment: .bottom)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if case .error(let msg) = transcriptionPhase {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(msg).font(.caption).lineLimit(2)
                Spacer()
                Button {
                    transcriptionPhase = .idle
                } label: {
                    Image(systemName: "xmark.circle")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.orange.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.2)), alignment: .bottom)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Relance la diarisation Pyannote sur le WAV existant pour reconstruire les
    /// embeddings par cluster et re-matcher contre les voiceprints courants.
    /// Ne re-transcrit pas : ne met à jour que les assignations et métadonnées
    /// de speakers (les `cid` n'étant pas stables entre runs, `seg.speaker`
    /// n'est volontairement pas remappé ici).
    private func reidentifySpeakers() {
        guard let wavPath = meeting.wavFilePath, !wavPath.isEmpty else { return }
        let url = URL(fileURLWithPath: wavPath)
        let queue = JobQueue.shared
        _ = queue.start(
            kind: .diarization,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title + " · diarisation"
        ) { jobID in
            await MainActor.run {
                self.transcriptionPhase = .reidentifying
                self.transcriptionProgress = nil
                self.transcriptionProgressStatus = nil
            }
            do {
                try Task.checkCancellation()
                let out = try await PyannoteDiarizer.shared.diarize(
                    audioURL: url,
                    onPhase: { phase in
                        Task { @MainActor in
                            if case .loadingModel = phase {
                                self.transcriptionPhase = .loadingModel
                            } else {
                                self.transcriptionPhase = .reidentifying
                            }
                        }
                    },
                    onProgress: { fraction, status in
                        Task { @MainActor in
                            self.transcriptionProgress = fraction
                            self.transcriptionProgressStatus = status
                        }
                        queue.updateProgress(jobID, fraction: fraction, status: status)
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.screen.lastDiarizationEmbeddings = out.perClusterEmbedding
                    let assignments = SpeakerMatcher.match(
                        clusterEmbeddings: out.perClusterEmbedding,
                        meeting: self.meeting,
                        in: self.context,
                        settings: self.settings
                    )
                    var assignmentsDict: [String: Any] = [:]
                    var metaDict: [String: [String: Any]] = [:]
                    for (cid, a) in assignments {
                        assignmentsDict[String(cid)] = a.collaborator?.ensuredStableID.uuidString ?? NSNull()
                        metaDict[String(cid)] = [
                            "confidence": a.confidence,
                            "auto": a.auto,
                            "ambiguous": a.ambiguous,
                            "candidates": a.candidates.map { $0.0.ensuredStableID.uuidString }
                        ]
                        // ⚠ NE PAS remapper `seg.speaker` depuis `cid` ici :
                        // pyannote ne garantit pas la stabilité des cluster
                        // IDs entre deux runs.
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: assignmentsDict),
                       let s = String(data: data, encoding: .utf8) {
                        self.meeting.speakerAssignmentsJSON = s
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                       let s = String(data: data, encoding: .utf8) {
                        self.meeting.speakerMatchMetaJSON = s
                    }
                    try? self.context.save()
                    self.transcriptionPhase = .idle
                    self.transcriptionProgress = nil
                    self.transcriptionProgressStatus = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.transcriptionPhase = .idle
                    self.transcriptionProgress = nil
                    self.transcriptionProgressStatus = nil
                }
                throw CancellationError()
            } catch {
                print("[MeetingView] reidentifySpeakers failed: \(error)")
                await MainActor.run {
                    self.transcriptionPhase = .error(error.localizedDescription)
                    self.transcriptionProgress = nil
                    self.transcriptionProgressStatus = nil
                }
                throw error
            }
        }
    }

    /// Maps each `TranscriptSegment` to a detected turn (whichever turn
    /// contains the segment's midpoint) and updates `speakerID`.
    private func applySpeakerTurns(_ turns: [(start: Double, end: Double, speakerID: Int)]) {
        guard !turns.isEmpty else { return }
        for seg in meeting.transcriptSegments {
            let mid = (seg.startSeconds + seg.endSeconds) / 2
            let match = turns.first(where: { $0.start <= mid && mid <= $0.end }) ?? turns.first!
            seg.speakerID = match.speakerID
        }
        try? context.save()
    }

    /// Supprime la réunion courante après confirmation. Stoppe un éventuel
    /// enregistrement en cours, quitte la vue PUIS supprime au cycle suivant :
    /// supprimer le modèle pendant que la vue l'observe ferait crasher SwiftData.
    /// Le fichier audio sur disque est conservé (récupérable via l'import des
    /// WAV orphelins).
    private func deleteMeeting() {
        // Posé avant tout le reste : coupe court à la réindexation par
        // .onDisappear, qui sinon se déclenche via dismiss() juste en dessous.
        // Consigné aussi dans le registre, pour l'écran resté ouvert sur la
        // même réunion dans l'autre fenêtre.
        isBeingDeleted = true
        MeetingScreenRegistry.shared.markDeleted(meeting.persistentModelID)
        if recorder.isRecording, recorder.activeMeetingID == meeting.stableID {
            _ = recorder.stop()
            // recorder.stop() clôt le flux audio : end() peut drainer sans
            // bloquer. On jette le résultat (suppression = annulation du live).
            // Garde sur isLive (état réel), pas sur le réglage — cf.
            // stopRecordingAndTranscribe().
            if LiveTranscriptionService.shared.isLive {
                Task { _ = await LiveTranscriptionService.shared.end() }
            }
        }
        // Après notre propre démontage, jamais avant : prévenir le
        // coordinateur ici l'aurait fait couper la capture lui-même
        // (effet `.stopRecording`), et la garde ci-dessus, déjà fausse,
        // aurait sauté le drain du flux live — dont les segments seraient
        // réapparus dans la transcription de la réunion suivante.
        TeamsAutoRecordCoordinator.shared.meetingWasDeleted(meetingID: meeting.ensuredStableID)
        let target = meeting
        let ctx = context
        // Retrait de l'index Spotlight synchrone et avant dismiss() : au-delà
        // de ce point, .onDisappear peut se déclencher n'importe quand, et une
        // réindexation après le remove() ci-dessous laisserait un orphelin
        // permanent (voir commentaire sur isBeingDeleted).
        SpotlightIndexService.shared.remove(meeting: target)
        dismiss()
        Task { @MainActor in
            ctx.delete(target)
            do { try ctx.save() } catch { print("[MeetingView] delete FAILED: \(error)") }
        }
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}
