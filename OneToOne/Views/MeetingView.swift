import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

fileprivate struct SpeakerMeta {
    let confidence: Double
    let auto: Bool
    let ambiguous: Bool
    let candidateStableIDs: [String]

    static func parse(json: String, clusterID: Int) -> SpeakerMeta? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = dict[String(clusterID)] as? [String: Any] else {
            return nil
        }
        return SpeakerMeta(
            confidence: (entry["confidence"] as? Double) ?? 0,
            auto: (entry["auto"] as? Bool) ?? false,
            ambiguous: (entry["ambiguous"] as? Bool) ?? false,
            candidateStableIDs: (entry["candidates"] as? [String]) ?? []
        )
    }
}

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

struct MeetingView: View {
    @Bindable var meeting: Meeting
    /// Démarre automatiquement le recorder à `onAppear` (déclenché par
    /// quick-launch 1:1). Consommé une seule fois grâce à `didAutoStart`.
    var autoStartRecording: Bool = false

    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var allCollaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    // MARK: - Services

    @StateObject private var recorder = AudioRecorderService.shared
    @StateObject private var stt = TranscriptionService.shared
    @StateObject private var player = AudioPlayerService()
    @StateObject private var captureService = ScreenCaptureService()

    // MARK: - Local state

    @State private var newTaskTitle = ""
    @State private var selectedCollaborator: Collaborator?
    @State private var showNewTaskDueDate = false
    @State private var newTaskDueDate: Date? = nil
    @State private var newAdhocName = ""
    @State private var showCustomPrompt = false
    @State private var activeSection: MeetingSection = .liveNotes
    @State private var participantsRefreshID = UUID()
    @State private var isGeneratingReport = false
    @State private var isGenerating: Bool = false
    @State private var reportEditMode: Bool = false
    @State private var reportError: String?
    @State private var transcribeError: String?
    @State private var transcriptionPhase: TranscriptionPhase = .idle
    @State private var transcriptionProgress: Double? = nil   // 0.0–1.0 when known
    @State private var transcriptionProgressStatus: String? = nil
    @State private var speakerPickerSearch: String = ""
    @State private var showDocImporter = false
    @State private var attachmentError: String?
    @State private var isImportingAttachment = false
    @State private var isDraggingDoc = false
    @State private var showCaptureSetup = false
    @State private var showSlidesList = false
    @State private var showCalendarImporter = false
    @State private var calendarImportError: String?
    @State private var showWavImporter = false
    @State private var wavImportError: String?
    @State private var reportProgressChars: Int = 0
    @State private var reportElapsedSeconds: Int = 0
    @State private var saveStatusMessage: String?
    @State private var showPlayback: Bool = false
    @State private var didAutoStart = false
    @State private var audioEditMode: AudioEditMode?
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
    @State private var showSpeakersView: Bool = true
    @State private var renamingSpeakerID: Int?
    @State private var lastDiarizationEmbeddings: [Int: [Float]] = [:]
    /// Si défini, la prochaine `stop()` concatène le nouveau WAV avec celui-ci.
    @State private var pendingAppendBaseURL: URL?
    @SceneStorage("meeting.detailsExpanded") private var detailsExpanded: Bool = true
    @SceneStorage("meeting.actionsCollapsed") private var actionsCollapsed: Bool = false

    enum MeetingSection: String, CaseIterable, Identifiable {
        case preparation = "Préparation"
        case liveNotes = "Notes live"
        case transcript = "Transcription"
        case report = "Rapport"
        case documents = "Documents"
        var id: String { rawValue }
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
                player: player,
                captureService: captureService,
                isGeneratingReport: isGeneratingReport,
                reportProgressChars: reportProgressChars,
                reportElapsedSeconds: reportElapsedSeconds,
                capturedSlidesCount: currentSlides.count,
                hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
                onStartRecording: { Task { await startRecording() } },
                onStopRecording:  { Task { await stopRecordingAndTranscribe() } },
                onAppendRecording: { Task { await startAppendRecording() } },
                onTogglePause:    { if recorder.isPaused { recorder.resume() } else { recorder.pause() } },
                onTogglePlay:     { if let wav = meeting.wavFileURL { togglePlay(url: wav); showPlayback = true } },
                onRetranscribe:   { if let wav = meeting.wavFileURL { Task { await retranscribe(wavURL: wav) } } },
                onGenerateReport: { Task { await generateReport() } },
                onShowCaptureSetup: { showCaptureSetup = true },
                onShowSlides:       { showSlidesList = true },
                onToggleCustomPrompt: { showCustomPrompt.toggle() },
                onImportCalendar:     { showCalendarImporter = true },
                onImportExistingWAV:  { showWavImporter = true },
                onRevealWAV: {
                    if let url = meeting.wavFileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                },
                onEditAudio: { audioEditMode = .trimStart },
                hasWAV: meeting.wavFileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                onExportMarkdown: {
                    let md = ExportService().exportMeetingMarkdown(meeting: meeting)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(md, forType: .string)
                },
                onExportPDF: {
                    let name = "Reunion_\(meeting.date.formatted(.iso8601.year().month().day()))_\(meeting.title).pdf"
                    ExportService().exportMeetingPDF(meeting: meeting, fileName: name)
                },
                onExportMail:        { opts in ExportService().exportMeetingMail(meeting: meeting, options: opts) },
                onExportOutlook:     { opts in ExportService().exportMeetingOutlook(meeting: meeting, options: opts) },
                onExportAppleNotes: { opts in
                    ExportService().exportMeetingToAppleNotes(meeting: meeting, options: opts)
                },
                onSaveNow: saveMeetingNow
            )

            HStack {
                prepBadgeView
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            MeetingContextualRecorderBar(
                recorder: recorder,
                stt: stt,
                player: player,
                captureService: captureService,
                hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
                showPlayback: showPlayback,
                onSnapshot: { captureService.snapshot() },
                onStopCapture: { Task { await captureService.stop() } },
                onSeek: { player.seek(to: $0) },
                onSkip: { player.skip(by: $0) },
                errors: [
                    recorder.lastError,
                    transcribeError,
                    reportError,
                    captureService.lastError,
                    attachmentError,
                    calendarImportError,
                    wavImportError
                ].compactMap { $0 }.filter { !$0.isEmpty },
                onDismissErrors: {
                    recorder.lastError = nil
                    transcribeError = nil
                    reportError = nil
                    captureService.lastError = nil
                    attachmentError = nil
                    calendarImportError = nil
                    wavImportError = nil
                }
            )
            .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
            .animation(.easeInOut(duration: 0.15), value: captureService.isCapturing)
            .animation(.easeInOut(duration: 0.15), value: showPlayback)

            transcriptionPhaseBanner

            HSplitView {
                mainPanel.frame(minWidth: 520)
                if meeting.kind == .manager {
                    ManagerAgendaSidebar(meeting: meeting, settings: settings)
                        .frame(minWidth: 320, maxWidth: 460)
                } else {
                    ConfigurableRightSidebar(
                        meeting: meeting,
                        settings: settings,
                        allCollaborators: allCollaborators,
                        currentSlides: currentSlides,
                        collapsed: $actionsCollapsed,
                        newTaskTitle: $newTaskTitle,
                        selectedCollaborator: $selectedCollaborator,
                        showNewTaskDueDate: $showNewTaskDueDate,
                        newTaskDueDate: $newTaskDueDate,
                        onAddTask: addTask,
                        onDeleteTask: { task in
                            context.delete(task)
                            saveContext()
                        },
                        onToggleTaskCompletion: { task in
                            task.isCompleted.toggle()
                            saveContext()
                        },
                        onShowSlides:       { showSlidesList = true },
                        onShowCaptureSetup: { showCaptureSetup = true },
                        saveContext: saveContext
                    )
                    .frame(minWidth: actionsCollapsed ? 44 : 300, maxWidth: actionsCollapsed ? 44 : 440)
                }
            }
        }
        .navigationTitle(meeting.title.isEmpty ? "Réunion" : meeting.title)
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
            AudioEditorSheet(meeting: meeting, mode: mode) { _ in }
        }
        .popover(isPresented: $showSlidesList) { slidesPopover }
        .popover(isPresented: $showCaptureSetup) {
            ScreenCaptureConfigView(service: captureService, meeting: meeting)
        }
        .fileImporter(
            isPresented: $showWavImporter,
            allowedContentTypes: [.audio, .wav, .mp3, .mpeg4Audio, .aiff],
            allowsMultipleSelection: false
        ) { result in
            Task { await importExistingWAV(result: result) }
        }
        .onAppear {
            guard autoStartRecording, !didAutoStart, !recorder.isRecording else { return }
            didAutoStart = true
            Task { await startRecording() }
        }
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetingHeaderEditorial(
                meeting: meeting,
                settings: settings,
                detailsExpanded: $detailsExpanded
            )
            MeetingDetailsBlock(
                meeting: meeting,
                settings: settings,
                allCollaborators: allCollaborators,
                availableCollaborators: availableCollaborators,
                projects: projects,
                expanded: $detailsExpanded,
                showCustomPrompt: $showCustomPrompt,
                newAdhocName: $newAdhocName,
                calendarImportError: $calendarImportError,
                addParticipant: addParticipant,
                removeParticipant: removeParticipant,
                setParticipantStatus: { status, c in setParticipantStatus(status, for: c) },
                participantStatus: { c in participantStatus(for: c) },
                addAdhoc: addAdhocParticipant,
                saveContext: saveContext
            )
            MeetingTabsUnderline(
                selection: $activeSection,
                attachmentsCount: meeting.attachments.count,
                hasReport: !meeting.summary.isEmpty
            )
            sectionContent
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        player.toggle()
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @MainActor
    private func retranscribe(wavURL: URL) async {
        transcribeError = nil
        print("[MeetingView] retranscribe: \(wavURL.path)")
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
                let result = try await stt.transcribeWithDiarization(
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
                    self.lastDiarizationEmbeddings = result.clusterEmbeddings
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
                    self.activeSection = .transcript
                    self.saveContext()
                }
                print("[MeetingView] retranscribe OK: \(result.text.count) chars, \(result.segments.count) segments")
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
                }
                print("[MeetingView] retranscribe FAILED: \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Replaces `meeting.transcriptSegments` with fresh ones (deletes existing
    /// rows first so a re-transcribe doesn't accumulate stale segments).
    /// New segments default to `speakerID = 0` (non-assigned) — the diarization
    /// pass and/or user assignment fills speakers in afterwards.
    private func persistTranscriptSegments(_ segments: [STTSegment]) {
        for old in meeting.transcriptSegments {
            context.delete(old)
        }
        for (idx, seg) in segments.enumerated() {
            let row = TranscriptSegment(
                orderIndex: idx,
                startSeconds: seg.startSeconds,
                endSeconds: seg.endSeconds,
                text: seg.text
            )
            row.meeting = meeting
            context.insert(row)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .preparation:
            MeetingPrepTab(meeting: meeting)
                .onAppear {
                    PrepCarryoverService.drainStandingIntoMeeting(meeting, in: context)
                }
        case .liveNotes:
            MarkdownEditorView(text: $meeting.liveNotes, textViewID: "meetingLiveNotes")
        case .transcript:
            transcriptView
        case .report:
            reportView
        case .documents:
            documentsView
        }
    }

    private var documentsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(meeting.attachments.count) document(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if isImportingAttachment {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Import + indexation…").font(.caption)
                    }
                }
                Button(action: { showDocImporter = true }) {
                    Label("Importer", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImportingAttachment)
            }
            .padding()

            if let err = attachmentError {
                Text(err).font(.caption).foregroundColor(.red).padding(.horizontal).padding(.bottom, 8)
            }

            Divider()

            ZStack {
                List {
                    ForEach(meeting.attachments.sorted(by: { $0.importedAt > $1.importedAt })) { att in
                        attachmentRow(att)
                    }
                }

                if isDraggingDoc {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 40))
                        Text("Déposer ici pour importer")
                            .font(.headline)
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .padding(20)
                    )
                }

                if meeting.attachments.isEmpty && !isDraggingDoc {
                    ContentUnavailableView(
                        "Aucun document",
                        systemImage: "doc.on.doc",
                        description: Text("Importez des documents ou déposez-les ici.")
                    )
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingDoc) { providers in
            Task {
                await handleFileDrop(providers)
            }
            return true
        }
        .fileImporter(
            isPresented: $showDocImporter,
            allowedContentTypes: [
                .pdf, .plainText, .text, .presentation, .spreadsheet,
                UTType(filenameExtension: "docx")!,
                UTType(filenameExtension: "pptx")!,
                UTType(filenameExtension: "xlsx")!,
                .content, .item
            ],
            allowsMultipleSelection: true
        ) { result in
            Task { await importDocuments(result: result) }
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
        }
        if !urls.isEmpty {
            await importDocuments(result: .success(urls))
        }
    }

    private var slidesPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Slides capturées (\(captureService.capturedSlidesCount))")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    let slides = currentSlides
                    
                    if slides.isEmpty {
                        Text("Aucune slide capturée dans cette session.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    
                    ForEach(slides) { slide in
                        HStack(spacing: 12) {
                            if let image = NSImage(contentsOfFile: slide.imagePath) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 60)
                                    .background(Color.black.opacity(0.1))
                                    .cornerRadius(4)
                            } else {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 80, height: 60)
                                    .cornerRadius(4)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Slide \(slide.index)")
                                    .font(.subheadline.bold())
                                Text(slide.capturedAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: slide.imagePath)) }) {
                                Image(systemName: "eye")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Ouvrir dans Aperçu")
                            
                            Button(action: { captureService.deleteSlide(slide) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .frame(width: 300, height: 400)
        }
    }

    private func attachmentRow(_ att: MeetingAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: att.kind))
                .foregroundColor(.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(att.fileName).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(att.kind.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18))
                        .cornerRadius(4)
                    Text("\(att.chunks.count) chunks indexés")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !att.extractedText.isEmpty {
                        Text("\(att.extractedText.count) car.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Re-indexer") {
                    Task {
                        try? await MeetingAttachmentService.reindexAttachment(att, context: context)
                    }
                }
                if att.kind == "slides" {
                    Button("Voir les slides") {
                        showSlidesList = true
                    }
                }
                Button("Ouvrir") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: att.filePath))
                }
                Divider()
                Button("Supprimer", role: .destructive) {
                    context.delete(att)
                    saveContext()
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "pdf":      return "doc.richtext"
        case "pptx":     return "rectangle.on.rectangle.angled"
        case "docx":     return "doc.text"
        case "xlsx":     return "tablecells"
        case "image":    return "photo"
        case "slides":   return "camera.viewfinder"
        case "markdown", "text": return "text.alignleft"
        default:          return "doc"
        }
    }

    @MainActor
    private func importDocuments(result: Result<[URL], Error>) async {
        attachmentError = nil
        switch result {
        case .success(let urls):
            isImportingAttachment = true
            defer { isImportingAttachment = false }
            for url in urls {
                do {
                    try await MeetingAttachmentService.importDocument(
                        url: url,
                        into: meeting,
                        context: context
                    )
                } catch {
                    attachmentError = error.localizedDescription
                }
            }
        case .failure(let error):
            attachmentError = error.localizedDescription
        }
    }

    // MARK: - Prep badge

    private enum PrepBadge { case none, toPrepare, prepared }

    private var prepBadgeState: PrepBadge {
        let standingNonEmpty: Bool = {
            switch meeting.kind {
            case .oneToOne, .manager:
                return !(meeting.participants.first?.standingPrepNotes.isEmpty ?? true)
            case .project:
                return !(meeting.project?.standingPrepNotes.isEmpty ?? true)
            case .global, .work:
                return false
            }
        }()
        let isFuture = (meeting.scheduledStart ?? meeting.date) > Date()
        let hasContent = !meeting.prepNotes.isEmpty || standingNonEmpty
        if isFuture && !hasContent { return .toPrepare }
        if hasContent { return .prepared }
        return .none
    }

    @ViewBuilder
    private var prepBadgeView: some View {
        switch prepBadgeState {
        case .toPrepare:
            Label("À préparer", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.orange))
        case .prepared:
            Label("Préparée", systemImage: "checkmark.seal.fill")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.green))
        case .none:
            EmptyView()
        }
    }


    private var transcriptView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if meeting.rawTranscript.isEmpty {
                    ContentUnavailableView(
                        "Aucune transcription",
                        systemImage: "waveform",
                        description: Text("Démarre un enregistrement pour voir la transcription ici.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    transcriptToolbar
                    if showSpeakersView && !meeting.transcriptSegments.isEmpty {
                        transcriptSegmentsView
                    } else if !meeting.mergedTranscript.isEmpty {
                        MeetingHighlightableTextView(
                            text: .constant(meeting.mergedTranscript),
                            isEditable: false,
                            highlightedRanges: managerHighlightedRanges(for: "mergedTranscript"),
                            onAddToManagerReport: { range, snippet in
                                startManagerReportFlow(range: range, snippet: snippet, field: "mergedTranscript")
                            }
                        )
                        .frame(minHeight: 280)
                    } else {
                        MeetingHighlightableTextView(
                            text: .constant(meeting.rawTranscript),
                            isEditable: false,
                            highlightedRanges: managerHighlightedRanges(for: "transcript"),
                            onAddToManagerReport: { range, snippet in
                                startManagerReportFlow(range: range, snippet: snippet, field: "transcript")
                            }
                        )
                        .frame(minHeight: 280)
                    }
                }
            }
            .padding()
        }
    }

    private var reportView: some View {
        VStack(spacing: 0) {
            // Bandeau d'avertissement si transcription supprimée
            if !meeting.reportRevisions.isEmpty,
               meeting.rawTranscript.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Transcription supprimée après édition audio — re-transcrire pour mettre à jour le rapport.")
                        .font(.caption)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
                .padding(.horizontal).padding(.top, 8)
            }

            if meeting.summary.isEmpty {
                ContentUnavailableView(
                    "Aucun rapport",
                    systemImage: "wand.and.stars",
                    description: Text("Génère le rapport une fois la transcription prête.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                generateToolbar
                    .padding(.horizontal, 8).padding(.top, 4)
                Divider()
                if reportEditMode {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            MarkdownEditorView(
                                text: Binding(
                                    get: { meeting.summary },
                                    set: { meeting.summary = $0; try? context.save() }
                                ),
                                textViewID: "reportEditor.\(meeting.persistentModelID.hashValue)"
                            )
                            .frame(minHeight: 280)

                            Divider()

                            decisionsEditor

                            Divider()

                            metaHeaderEditor

                            Divider()

                            actionsNotice
                        }
                        .padding(12)
                    }
                } else {
                    MeetingReportPreview(html: ReportHTMLBuilder.build(
                        meeting: meeting,
                        template: meeting.reportTemplate,
                        includeTranscript: false,
                        managerName: settings.ownerName,
                        managerRole: settings.ownerRole
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var decisionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DÉCISIONS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text("(\(meeting.decisions.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    meeting.decisions.append("")
                    try? context.save()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Ajouter une décision")
            }

            if meeting.decisions.isEmpty {
                Text("Aucune décision. Ces lignes apparaîtront automatiquement comme tableau « Relevé de décisions » dans le rapport.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(meeting.decisions.enumerated()), id: \.offset) { idx, _ in
                    HStack(spacing: 6) {
                        Text("D\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        TextField("Décision…", text: Binding(
                            get: { idx < meeting.decisions.count ? meeting.decisions[idx] : "" },
                            set: { newValue in
                                guard idx < meeting.decisions.count else { return }
                                meeting.decisions[idx] = newValue
                                try? context.save()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button {
                            guard idx < meeting.decisions.count else { return }
                            meeting.decisions.remove(at: idx)
                            try? context.save()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Supprimer cette décision")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metaHeaderEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EN-TÊTE DU RAPPORT")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Référencés (non présents)")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("ex: Zied · Nicolas Hauvinet · Travaux McKinsey",
                          text: Binding(
                            get: { meeting.referencedAbsent },
                            set: { meeting.referencedAbsent = $0; try? context.save() }
                          ))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prochaine échéance")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("ex: Partage du modèle puis présentation McKinsey",
                          text: Binding(
                            get: { meeting.nextDeadline },
                            set: { meeting.nextDeadline = $0; try? context.save() }
                          ))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var actionsNotice: some View {
        HStack(spacing: 6) {
            Text("PLAN D'ACTIONS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("(\(meeting.tasks.count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("↗ Éditer via le panneau Actions (droite)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .italic()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
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
        meeting.setParticipantStatus(.participant, for: c)
        saveContext()
        participantsRefreshID = UUID()
    }

    private func removeParticipant(_ c: Collaborator) {
        meeting.participants.removeAll { $0.persistentModelID == c.persistentModelID }
        meeting.clearParticipantStatus(for: c)
        saveContext()
        participantsRefreshID = UUID()
    }

    private func setParticipantStatus(_ status: MeetingAttendanceStatus, for collaborator: Collaborator) {
        meeting.setParticipantStatus(status, for: collaborator)
        saveContext()
        participantsRefreshID = UUID()
    }

    private func participantStatus(for collaborator: Collaborator) -> MeetingAttendanceStatus {
        meeting.participantStatus(for: collaborator)
    }

    /// Crée un `Collaborator` adhoc (réutilisable) et l'ajoute à la réunion.
    private func addAdhocParticipant() {
        let name = newAdhocName.trimmingCharacters(in: .whitespaces)
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
        newAdhocName = ""
    }

    private func importCalendarEvent(_ event: CalendarMeetingEvent) {
        calendarImportError = nil
        meeting.title = event.title
        meeting.date = event.startDate
        meeting.calendarEventID = event.id
        meeting.calendarEventTitle = event.title
        meeting.meetingDurationSeconds = max(0, Int(event.endDate.timeIntervalSince(event.startDate).rounded()))

        for attendee in event.attendees {
            let collaborator = resolveCollaborator(for: attendee)
            if !meeting.participants.contains(where: { $0.persistentModelID == collaborator.persistentModelID }) {
                meeting.participants.append(collaborator)
            }
            meeting.setParticipantStatus(attendee.status, for: collaborator)
        }

        saveContext()
        participantsRefreshID = UUID()
    }

    private func resolveCollaborator(for attendee: CalendarMeetingAttendee) -> Collaborator {
        let normalizedName = attendee.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if let existing = allCollaborators.first(where: {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedName
        }) {
            // Compléter l'email s'il était vide.
            if existing.email.isEmpty, let email = attendee.email, !email.isEmpty {
                existing.email = email
            }
            return existing
        }

        let collaborator = Collaborator(name: attendee.name, role: "Calendrier")
        collaborator.email = attendee.email ?? ""
        collaborator.isAdhoc = true
        collaborator.pinLevel = 0
        context.insert(collaborator)
        return collaborator
    }

    // MARK: - Actions panel

    // MARK: - Recording actions

    private func startRecording() async {
        if recorder.isRecording && recorder.activeMeetingID != meeting.stableID {
            recorder.lastError = "Un enregistrement est déjà en cours pour une autre réunion."
            return
        }
        do {
            let url = try await recorder.start(meetingID: meeting.stableID)
            meeting.wavFilePath = url.path
            saveContext()
        } catch {
            recorder.lastError = error.localizedDescription
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
        do {
            let url = try await recorder.start(meetingID: meeting.stableID)
            // On laisse meeting.wavFilePath pointer sur l'ancien jusqu'à la
            // concaténation post-stop ; en cas d'arrêt anormal, l'utilisateur
            // garde son enregistrement initial. La nouvelle URL est conservée
            // par le recorder via currentFileURL.
            _ = url
        } catch {
            pendingAppendBaseURL = nil
            recorder.lastError = error.localizedDescription
        }
    }

    /// Attache un WAV/audio déjà présent sur disque au meeting courant.
    /// Si le fichier vit déjà sous `recordings/`, on pointe dessus directement.
    /// Sinon on copie sous `recordings/<UUID>.<ext>` pour stabiliser le chemin.
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

            let file = try AVAudioFile(forReading: target)
            let durationSeconds = Double(file.length) / file.processingFormat.sampleRate

            meeting.wavFilePath = target.path
            meeting.durationSeconds = Int(durationSeconds.rounded())
            saveContext()
            print("[MeetingView] importWAV → \(target.path) duration=\(durationSeconds)s")
        } catch {
            wavImportError = error.localizedDescription
            print("[MeetingView] importWAV failed: \(error)")
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard recorder.activeMeetingID == nil || recorder.activeMeetingID == meeting.stableID else {
            recorder.lastError = "Cet enregistrement appartient à une autre réunion."
            return
        }
        guard let stopped = recorder.stop() else { return }

        // Laisse le FS finaliser le header WAV avant de le relire.
        try? await Task.sleep(nanoseconds: 400_000_000)

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
            return
        }
        guard totalDuration >= 1.0 else {
            transcribeError = "Enregistrement trop court (\(String(format: "%.1f", totalDuration))s). STT désactivé."
            print("[MeetingView] durée trop courte: \(totalDuration)s")
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
            let result = try await stt.transcribeWithDiarization(
                audioURL: finalURL,
                meeting: meeting,
                settings: settings,
                in: context,
                onPhase: { phase in
                    transcriptionPhase = phase
                    if case .transcribing = phase {
                        transcriptionProgress = nil
                        transcriptionProgressStatus = nil
                    }
                },
                onProgress: { fraction, status in
                    transcriptionProgress = fraction
                    transcriptionProgressStatus = status
                }
            )
            transcriptionPhase = .idle
            transcriptionProgress = nil
            transcriptionProgressStatus = nil
            print("[MeetingView] ← transcribe OK: \(result.text.count) chars, \(result.segments.count) segments")
            // Cache les embeddings pour permettre l'EMA voiceprint update au
            // premier labeling manuel (sinon il faut attendre re-diarisation).
            lastDiarizationEmbeddings = result.clusterEmbeddings
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
            activeSection = .transcript
            saveContext()
        } catch {
            transcribeError = error.localizedDescription
            transcriptionPhase = .error(error.localizedDescription)
            print("[MeetingView] transcribe FAILED: \(error.localizedDescription)")
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
                Label(isGenerating ? "Génère…" : "Générer",
                      systemImage: "wand.and.stars")
            }
            .disabled(isGenerating || meeting.rawTranscript.isEmpty)
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
        isGenerating = true
        let queue = JobQueue.shared
        let title = meeting.title
        let id = meeting.persistentModelID
        // Throttle des updates UI pendant le streaming LLM. Sans ça, chaque
        // token (~50-100/sec) déclenche un re-render SwiftUI et bloque le
        // main thread sur les longs rapports.
        let throttle = ProgressThrottle(minInterval: 0.25)
        _ = queue.start(
            kind: .report,
            meetingID: id,
            meetingTitle: title + " · rapport"
        ) { jobID in
            defer { Task { @MainActor in self.isGenerating = false } }
            do {
                let result = try await AIReportService.generate(
                    meeting: meeting,
                    in: context,
                    settings: settings,
                    additionalContext: "",
                    onProgress: { partial in
                        guard await throttle.shouldEmit() else { return }
                        let count = partial.count
                        let tail = partial.suffix(80)
                            .replacingOccurrences(of: "\n", with: " ")
                        await MainActor.run {
                            queue.updateProgress(
                                jobID,
                                fraction: nil,
                                status: "\(count) chars · …\(tail)"
                            )
                        }
                    }
                )
                await MainActor.run {
                    self.apply(report: result)
                }
            } catch {
                print("[Rapport] génération échec: \(error)")
            }
        }
    }

    /// Throttle simple actor-based pour limiter les updates UI streaming.
    /// `shouldEmit()` retourne `true` au plus 1× par `minInterval` secondes.
    private actor ProgressThrottle {
        let minInterval: TimeInterval
        var lastEmit: Date = .distantPast
        init(minInterval: TimeInterval) { self.minInterval = minInterval }
        func shouldEmit() -> Bool {
            let now = Date()
            if now.timeIntervalSince(lastEmit) >= minInterval {
                lastEmit = now
                return true
            }
            return false
        }
    }

    // MARK: - Report generation

    private func generateReport() async {
        guard !meeting.rawTranscript.isEmpty else { return }

        // Refresh merged transcript au cas où l'utilisateur a édité les notes.
        meeting.mergedTranscript = NoteMergeService.merge(
            transcript: meeting.rawTranscript,
            liveNotes: meeting.liveNotes
        )

        reportError = nil
        isGeneratingReport = true
        reportProgressChars = 0
        reportElapsedSeconds = 0

        let queue = JobQueue.shared
        _ = queue.start(
            kind: .report,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title
        ) { jobID in
            // Tick d'avancement (LLM streaming — pas de fraction réelle, on
            // alimente le statusText avec le nombre de chars reçus).
            let start = Date()
            let elapsedTimer = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { break }
                    self.reportElapsedSeconds = Int(Date().timeIntervalSince(start))
                    queue.updateProgress(jobID,
                                          fraction: nil,
                                          status: "\(self.reportElapsedSeconds)s · \(self.reportProgressChars) chars")
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
                let report = try await AIReportService.generate(
                    meeting: meeting,
                    in: context,
                    settings: settings,
                    additionalContext: ragContext,
                    onProgress: { partial in
                        // Note : signature non-throwing — la cancellation est
                        // vérifiée juste après l'appel `generate(...)`. Côté
                        // streaming on se contente de pousser la progression.
                        let count = partial.count
                        await MainActor.run {
                            self.reportProgressChars = count
                        }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.apply(report: report)
                    self.meeting.reportGenerationDurationSeconds = Date().timeIntervalSince(generationStart)
                    self.saveContext()
                    self.activeSection = .report
                }

                // Indexation RAG post-rapport (non bloquant pour l'UI).
                Task.detached { @MainActor in
                    do {
                        try await RAGIndexer.reindex(meeting: meeting, context: context)
                    } catch {
                        print("[MeetingView] RAG reindex échoué: \(error.localizedDescription)")
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await MainActor.run { self.reportError = error.localizedDescription }
                throw error
            }
        }
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
        case .global, .work:
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

    private func fetchAttachmentsContext() async -> String {
        let meetingPID = meeting.persistentModelID
        let totalChars = meeting.attachments
            .map { $0.extractedText.count }
            .reduce(0, +)

        // Seuil : < 20_000 chars total → on injecte le texte brut cap par doc.
        // Au-delà → on bascule sur top-K chunks via RAGQuery scope attachment + meeting.
        if totalChars < 20_000 {
            return meeting.attachments
                .filter { !$0.extractedText.isEmpty }
                .map { "### \($0.fileName) (\($0.kind))\n\($0.extractedText.prefix(8000))" }
                .joined(separator: "\n\n")
        }

        let query = String(meeting.mergedTranscript.prefix(2000))
        let scope = RAGQuery.Scope(
            projectPID: nil,
            collaboratorPID: nil,
            meetingKind: nil,
            excludeMeetingPID: nil,
            sourceType: "attachment",
            meetingPID: meetingPID
        )
        let results = try? await RAGQuery.search(query: query, topK: 8, scope: scope, context: context)
        return (results ?? []).map { r in
            "### \(r.chunk.attachment?.fileName ?? "?") — extrait\n\(r.chunk.text)"
        }.joined(separator: "\n\n")
    }

    private func apply(report: MeetingReportData) {
        meeting.summary = report.summary
        meeting.keyPoints = report.keyPoints
        meeting.decisions = report.decisions
        meeting.openQuestions = report.openQuestions

        // Snapshot v_n+1 — chaque génération crée une nouvelle révision pour
        // pouvoir comparer/restaurer un draft antérieur.
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
            alert.interview = nil
            alert.meeting = meeting
            context.insert(alert)
        }

        saveContext()
        activeSection = .report
    }

    // MARK: - Tasks

    private func addTask() {
        let t = ActionTask(
            title: newTaskTitle,
            dueDate: showNewTaskDueDate ? (newTaskDueDate ?? Date()) : nil
        )
        t.meeting = meeting
        t.project = meeting.project
        t.collaborator = selectedCollaborator
        context.insert(t)
        newTaskTitle = ""
        newTaskDueDate = nil
        showNewTaskDueDate = false
        saveContext()
    }

    // MARK: - Utils

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    private var currentSlides: [SlideCapture] {
        // Pendant une session : source de vérité = service.
        if let att = captureService.currentAttachment {
            return att.slides.sorted(by: { $0.index < $1.index })
        }
        // Hors session : on affiche la dernière session "slides" de cette réunion.
        let latest = meeting.attachments
            .filter { $0.kind == "slides" }
            .sorted(by: { $0.importedAt > $1.importedAt })
            .first
        return latest?.slides.sorted(by: { $0.index < $1.index }) ?? []
    }

    private func saveContext() {
        do { try context.save() } catch { print("[MeetingView] save FAILED: \(error)") }
    }

    private func startManagerReportFlow(range: NSRange, snippet: String, field: String) {
        mgrSuggestedCategory = nil
        mgrSuggestedElaboration = nil
        isMgrSuggestingCategory = true
        isMgrElaborating = true

        // Compute deterministic context for both initial elaboration fallback
        // (shown immediately) and the AI prompt context.
        let fullText: String
        switch field {
        case "mergedTranscript": fullText = meeting.mergedTranscript
        case "transcript":       fullText = meeting.rawTranscript
        case "summary":          fullText = meeting.summary
        case "notes":            fullText = meeting.notes
        case "liveNotes":        fullText = meeting.liveNotes
        default:                 fullText = ""
        }
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

    private func confirmManagerItem(pending: PendingMgrSelection,
                                    category: String,
                                    tag: String,
                                    elaboratedText: String,
                                    aiSuggested: String?) {
        let fullText: String
        switch pending.field {
        case "mergedTranscript": fullText = meeting.mergedTranscript
        case "transcript":       fullText = meeting.rawTranscript
        case "summary":          fullText = meeting.summary
        case "notes":            fullText = meeting.notes
        case "liveNotes":        fullText = meeting.liveNotes
        default:                 fullText = ""
        }
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

    /// Bullet row used in the Rapport tab for each entry in
    /// faits marquants / points clés / décisions / questions ouvertes.
    @ViewBuilder
    private func bulletRow(text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(.titleAndIcon)
    }

    private func managerHighlightedRanges(for field: String) -> [NSRange] {
        ManagerReportService.itemsHighlightingSource(meeting: meeting, field: field, in: context).map {
            NSRange(location: $0.sourceRangeStart, length: $0.sourceRangeLength)
        }
    }

    // MARK: - Transcript / speakers UI

    /// Header above the transcript: speakers toggle + diarization launcher.
    @ViewBuilder
    private var transcriptToolbar: some View {
        HStack(spacing: 12) {
            Toggle("Afficher speakers", isOn: $showSpeakersView)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(meeting.transcriptSegments.isEmpty)

            if !meeting.transcriptSegments.isEmpty {
                Text("\(meeting.transcriptSegments.count) segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                runDiarization()
            } label: {
                Label("Détecter les speakers", systemImage: "person.wave.2")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(meeting.transcriptSegments.isEmpty || (meeting.wavFilePath ?? "").isEmpty)
            .help("Analyse l'audio (VAD) et propose une alternance de tours de parole. Reassign manuel ensuite via clic sur le label.")

            Button {
                reidentifySpeakers()
            } label: {
                Image(systemName: "person.crop.circle.badge.questionmark")
            }
            .help("Ré-identifier les speakers")
            .disabled((meeting.wavFilePath ?? "").isEmpty)
        }
        .padding(.bottom, 4)
    }

    /// List of timestamped segments with speaker prefix + color.
    @ViewBuilder
    private var transcriptSegmentsView: some View {
        let sorted = meeting.transcriptSegments.sorted { $0.orderIndex < $1.orderIndex }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sorted) { seg in
                segmentRow(seg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segmentRow(_ seg: TranscriptSegment) -> some View {
        // textSelection(.enabled) capture le clic droit sur macOS → on ne peut
        // pas y attacher un contextMenu fonctionnel. À la place : bouton play
        // visible à côté du timestamp (clic gauche = lecture ; option-clic =
        // seek sans jouer).
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            speakerBadge(for: seg)

            Button {
                playSegmentAudio(seg)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.caption2)
                    Text(seg.formattedTimestamp)
                        .font(.caption.monospacedDigit().bold())
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(
                    Capsule().fill(meeting.wavFileURL == nil
                                   ? Color.secondary.opacity(0.15)
                                   : Color.accentColor.opacity(0.18))
                )
                .foregroundColor(meeting.wavFileURL == nil ? .secondary : .accentColor)
                .overlay(
                    Capsule().stroke(
                        meeting.wavFileURL == nil ? Color.clear : Color.accentColor.opacity(0.4),
                        lineWidth: 0.5
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(meeting.wavFileURL == nil)
            .help(meeting.wavFileURL == nil
                  ? "Aucun audio attaché à la réunion"
                  : "Lire l'audio à partir de \(seg.formattedTimestamp)")

            Text(seg.text)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// Charge le wav si besoin et positionne le curseur sans démarrer la lecture.
    private func seekToSegment(_ seg: TranscriptSegment) {
        guard let url = meeting.wavFileURL else { return }
        if player.loadedURL != url { try? player.load(url: url) }
        player.seek(to: seg.startSeconds)
    }

    /// Charge le wav si besoin, place le curseur sur seg.startSeconds, joue.
    /// Si la lecture est déjà en cours, on pause d'abord pour forcer le saut
    /// (sinon AVAudioPlayer continue parfois depuis l'ancienne position avant
    /// de prendre en compte le seek).
    private func playSegmentAudio(_ seg: TranscriptSegment) {
        guard let url = meeting.wavFileURL else { return }
        do {
            if player.loadedURL != url { try player.load(url: url) }
        } catch {
            transcribeError = "Lecture impossible: \(error.localizedDescription)"
            return
        }
        let wasPlaying = player.isPlaying
        if wasPlaying { player.pause() }
        player.seek(to: seg.startSeconds)
        player.play()
        print("[MeetingView] play segment from \(seg.startSeconds)s (was playing: \(wasPlaying))")
    }

    @ViewBuilder
    private func speakerBadge(for seg: TranscriptSegment) -> some View {
        let clusterID = seg.speakerID - 1
        let meta = SpeakerMeta.parse(json: meeting.speakerMatchMetaJSON, clusterID: clusterID)

        if let speaker = seg.speaker {
            // Auto-assigned: small green check
            Button { renamingSpeakerID = seg.speakerID } label: {
                HStack(spacing: 4) {
                    Image(systemName: meta?.auto == true ? "checkmark.seal.fill" : "person.fill")
                        .font(.caption2)
                        .foregroundStyle(meta?.auto == true ? .green : speakerColor(seg.speakerID))
                    Text(speaker.name)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    if let m = meta, m.auto {
                        Text("(\(Int(m.confidence * 100))%)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(speakerColor(seg.speakerID).opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { renamingSpeakerID == seg.speakerID },
                set: { if !$0 { renamingSpeakerID = nil } }
            )) {
                speakerRenamePopover(speakerID: seg.speakerID).padding(12).frame(minWidth: 240)
            }
        } else if let m = meta,
                  m.confidence >= settings.speakerIdSuggestThreshold,
                  let suggested = firstCandidate(stableIDs: m.candidateStableIDs) {
            // Suggestion path
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.caption2).foregroundStyle(.orange)
                Text("\(suggested.name)? (\(Int(m.confidence * 100))%)")
                    .font(.caption.italic())
                    .foregroundColor(.primary)
                Button { acceptSuggestion(suggested, for: seg) } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }.buttonStyle(.plain)
                Button { rejectSuggestion(for: seg) } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.10))
            .clipShape(Capsule())
        } else {
            // Anonymous fallback (existing flow).
            Button { renamingSpeakerID = seg.speakerID } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(speakerColor(seg.speakerID))
                        .frame(width: 8, height: 8)
                    Text("[\(seg.displayLabel)]")
                        .font(.caption.bold())
                        .foregroundColor(speakerColor(seg.speakerID))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(speakerColor(seg.speakerID).opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { renamingSpeakerID == seg.speakerID },
                set: { if !$0 { renamingSpeakerID = nil } }
            )) {
                speakerRenamePopover(speakerID: seg.speakerID).padding(12).frame(minWidth: 240)
            }
        }
    }

    private func firstCandidate(stableIDs: [String]) -> Collaborator? {
        guard let first = stableIDs.first, let uuid = UUID(uuidString: first) else { return nil }
        return allCollaborators.first { $0.stableID == uuid }
    }

    private func acceptSuggestion(_ collab: Collaborator, for seg: TranscriptSegment) {
        assignSpeaker(speakerID: seg.speakerID, to: collab)
    }

    private func rejectSuggestion(for seg: TranscriptSegment) {
        let clusterID = seg.speakerID - 1
        var meta = (try? JSONSerialization.jsonObject(
            with: meeting.speakerMatchMetaJSON.data(using: .utf8) ?? Data()
        ) as? [String: Any]) ?? [:]
        meta.removeValue(forKey: String(clusterID))
        if let data = try? JSONSerialization.data(withJSONObject: meta),
           let s = String(data: data, encoding: .utf8) {
            meeting.speakerMatchMetaJSON = s
            try? context.save()
        }
    }

    @ViewBuilder
    private func speakerRenamePopover(speakerID: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speaker \(speakerID) → participant")
                .font(.caption.bold())

            TextField("Rechercher…", text: $speakerPickerSearch)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            let participantIDs = Set(meeting.participants.map { $0.persistentModelID })
            let query = speakerPickerSearch.trimmingCharacters(in: .whitespaces)
            let matches: (Collaborator) -> Bool = { c in
                query.isEmpty || c.name.localizedCaseInsensitiveContains(query)
            }
            let participants = meeting.participants
                .filter { !$0.isArchived && matches($0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let others = allCollaborators
                .filter { !participantIDs.contains($0.persistentModelID) && matches($0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if participants.isEmpty && others.isEmpty {
                Text(query.isEmpty ? "Aucun collaborateur dans la base." : "Aucun résultat.")
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if !participants.isEmpty {
                            Text("Participants de la réunion").font(.caption2.bold()).foregroundStyle(.secondary)
                            ForEach(participants) { c in
                                speakerPickerRow(c, speakerID: speakerID, highlighted: true)
                            }
                        }
                        if !others.isEmpty {
                            if !participants.isEmpty { Divider() }
                            Text("Autres collaborateurs").font(.caption2.bold()).foregroundStyle(.secondary)
                            ForEach(others) { c in
                                speakerPickerRow(c, speakerID: speakerID, highlighted: false)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
                Divider()
            }
            Button("Annuler") {
                renamingSpeakerID = nil
                speakerPickerSearch = ""
            }
            .font(.caption)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func speakerPickerRow(_ c: Collaborator, speakerID: Int, highlighted: Bool) -> some View {
        Button {
            assignSpeaker(speakerID: speakerID, to: c)
            renamingSpeakerID = nil
            speakerPickerSearch = ""
        } label: {
            HStack {
                Image(systemName: highlighted ? "person.fill.checkmark" : "person.fill")
                    .foregroundColor(highlighted ? .green : .accentColor)
                Text(c.name)
                    .fontWeight(highlighted ? .semibold : .regular)
                if c.voicePrint != nil {
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func assignSpeaker(speakerID: Int, to collaborator: Collaborator) {
        for seg in meeting.transcriptSegments where seg.speakerID == speakerID {
            seg.speaker = collaborator
        }
        // Update assignmentsJSON
        let clusterID = speakerID - 1
        var assignments = (try? JSONSerialization.jsonObject(
            with: meeting.speakerAssignmentsJSON.data(using: .utf8) ?? Data()
        ) as? [String: Any]) ?? [:]
        assignments[String(clusterID)] = collaborator.ensuredStableID.uuidString
        if let data = try? JSONSerialization.data(withJSONObject: assignments),
           let s = String(data: data, encoding: .utf8) {
            meeting.speakerAssignmentsJSON = s
        }
        // EMA voiceprint update if we have a fresh embedding cached from the last
        // diarization pass for this cluster.
        if let embedding = lastDiarizationEmbeddings[clusterID] {
            SpeakerMatcher.applyEMAUpdate(to: collaborator, newEmbedding: embedding, in: context)
        }
        try? context.save()
    }

    /// Stable palette per speakerID. ID 0 = grey (unassigned).
    private func speakerColor(_ id: Int) -> Color {
        guard id > 0 else { return .secondary }
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .brown]
        return palette[(id - 1) % palette.count]
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
                    self.lastDiarizationEmbeddings = out.perClusterEmbedding
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

    private func saveMeetingNow() {
        saveContext()
        saveStatusMessage = "Réunion enregistrée"

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if saveStatusMessage == "Réunion enregistrée" {
                saveStatusMessage = nil
            }
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

