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
    @State private var reportError: String?
    @State private var transcribeError: String?
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

            HSplitView {
                mainPanel.frame(minWidth: 520)
                if meeting.kind == .manager {
                    ManagerAgendaSidebar(meeting: meeting, settings: settings)
                        .frame(minWidth: 320, maxWidth: 460)
                } else {
                    MeetingActionsSidebar(
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
        do {
            let result = try await stt.transcribe(audioURL: wavURL)
            meeting.rawTranscript = result.text
            meeting.mergedTranscript = NoteMergeService.merge(
                transcript: result.text,
                liveNotes: meeting.liveNotes
            )
            persistTranscriptSegments(result.segments)
            activeSection = .transcript
            saveContext()
            print("[MeetingView] retranscribe OK: \(result.text.count) chars, \(result.segments.count) segments")
        } catch {
            transcribeError = error.localizedDescription
            print("[MeetingView] retranscribe FAILED: \(error.localizedDescription)")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if meeting.summary.isEmpty {
                    ContentUnavailableView(
                        "Aucun rapport",
                        systemImage: "wand.and.stars",
                        description: Text("Génère le rapport une fois la transcription prête.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    if !meeting.highlights.isEmpty {
                        section("Faits marquants") {
                            ForEach(meeting.highlights, id: \.self) { item in
                                bulletRow(text: item, systemImage: "sparkles")
                            }
                        }
                    }
                    section("Résumé") {
                        MeetingHighlightableTextView(
                            text: .constant(meeting.summary),
                            isEditable: false,
                            highlightedRanges: managerHighlightedRanges(for: "summary"),
                            onAddToManagerReport: { range, snippet in
                                startManagerReportFlow(range: range, snippet: snippet, field: "summary")
                            }
                        )
                        .frame(minHeight: 240)
                    }
                    if !meeting.keyPoints.isEmpty {
                        section("Points clés") {
                            ForEach(meeting.keyPoints, id: \.self) { p in
                                bulletRow(text: p, systemImage: "circle.fill")
                            }
                        }
                    }
                    if !meeting.decisions.isEmpty {
                        section("Décisions") {
                            ForEach(meeting.decisions, id: \.self) { d in
                                bulletRow(text: d, systemImage: "checkmark.seal")
                            }
                        }
                    }
                    if !meeting.openQuestions.isEmpty {
                        section("Questions ouvertes") {
                            ForEach(meeting.openQuestions, id: \.self) { q in
                                bulletRow(text: q, systemImage: "questionmark.circle")
                            }
                        }
                    }
                }
            }
            .padding()
        }
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
            print("[MeetingView] → transcribe start…")
            let result = try await stt.transcribe(audioURL: finalURL)
            print("[MeetingView] ← transcribe OK: \(result.text.count) chars, \(result.segments.count) segments")
            meeting.rawTranscript = result.text
            meeting.mergedTranscript = NoteMergeService.merge(
                transcript: result.text,
                liveNotes: meeting.liveNotes
            )
            persistTranscriptSegments(result.segments)
            activeSection = .transcript
            saveContext()
        } catch {
            transcribeError = error.localizedDescription
            print("[MeetingView] transcribe FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Report generation

    private func generateReport() async {
        guard !meeting.rawTranscript.isEmpty else { return }

        reportError = nil
        isGeneratingReport = true
        reportProgressChars = 0
        reportElapsedSeconds = 0

        // Tick toutes les secondes pour afficher le temps écoulé pendant la
        // génération (le LLM ne renvoie rien tant que les poids ne sont pas
        // chargés — le compteur évite l'impression d'un freeze).
        let elapsedTimer = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self.reportElapsedSeconds = Int(Date().timeIntervalSince(start))
            }
        }
        defer {
            elapsedTimer.cancel()
            isGeneratingReport = false
            reportProgressChars = 0
            reportElapsedSeconds = 0
        }

        // Refresh merged transcript au cas où l'utilisateur a édité les notes.
        meeting.mergedTranscript = NoteMergeService.merge(
            transcript: meeting.rawTranscript,
            liveNotes: meeting.liveNotes
        )

        // Phase 8 : RAG historique — injection du contexte pré-LLM (now handled in resolver).
        let generationStart = Date()
        do {
            let report = try await AIReportService.generate(
                meeting: meeting,
                in: context,
                settings: settings,
                onProgress: { partial in
                    let count = partial.count
                    await MainActor.run {
                        self.reportProgressChars = count
                    }
                }
            )
            apply(report: report)
            meeting.reportGenerationDurationSeconds = Date().timeIntervalSince(generationStart)
            saveContext()
            activeSection = .report

            // Indexation RAG post-rapport (non bloquant pour l'UI).
            Task.detached { @MainActor in
                do {
                    try await RAGIndexer.reindex(meeting: meeting, context: context)
                } catch {
                    print("[MeetingView] RAG reindex échoué: \(error.localizedDescription)")
                }
            }
        } catch {
            reportError = error.localizedDescription
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

        for a in report.actions {
            let task = ActionTask(title: a.title)
            task.meeting = meeting
            task.project = meeting.project
            if let iso = a.deadlineISO {
                task.dueDate = ISO8601DateFormatter().date(from: iso)
                    ?? DateFormatter.yyyyMMdd.date(from: iso)
            }
            if let assignee = a.assignee,
               let collab = allCollaborators.first(where: { $0.name.localizedCaseInsensitiveCompare(assignee) == .orderedSame }) {
                task.collaborator = collab
            }
            context.insert(task)
        }

        for a in report.alerts {
            let alert = ProjectAlert(title: a.title, detail: a.detail, severity: a.severity)
            alert.project = meeting.project
            alert.interview = nil
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
    /// Original Label + trailing "Ajouter au rapport manager" affordance.
    @ViewBuilder
    private func bulletRow(text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Label {
                Text(text).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.titleAndIcon)

            Button {
                startManagerReportFlow(range: NSRange(location: 0, length: 0),
                                       snippet: text,
                                       field: "summary")
            } label: {
                Image(systemName: "plus.bubble")
                    .foregroundColor(.accentColor.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Ajouter au rapport manager")
        }
        .contextMenu {
            Button {
                startManagerReportFlow(range: NSRange(location: 0, length: 0),
                                       snippet: text,
                                       field: "summary")
            } label: { Label("Ajouter au rapport manager", systemImage: "plus.bubble") }
        }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            speakerBadge(for: seg)

            Text(seg.formattedTimestamp)
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)

            Text(seg.text)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
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
                  m.confidence >= SpeakerMatcher.suggestThreshold,
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
            if allCollaborators.isEmpty {
                Text("Aucun collaborateur dans la base.").font(.caption2).foregroundColor(.secondary)
            } else {
                ForEach(allCollaborators.sorted(by: { $0.name < $1.name })) { c in
                    Button {
                        assignSpeaker(speakerID: speakerID, to: c)
                        renamingSpeakerID = nil
                    } label: {
                        HStack {
                            Image(systemName: "person.fill").foregroundColor(.accentColor)
                            Text(c.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
            Button("Annuler") { renamingSpeakerID = nil }
                .font(.caption)
        }
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
    private func reidentifySpeakers() {
        guard let wavPath = meeting.wavFilePath, !wavPath.isEmpty else { return }
        let url = URL(fileURLWithPath: wavPath)
        Task { @MainActor in
            do {
                let out = try await PyannoteDiarizer.shared.diarize(audioURL: url)
                lastDiarizationEmbeddings = out.perClusterEmbedding
                let assignments = SpeakerMatcher.match(
                    clusterEmbeddings: out.perClusterEmbedding,
                    meeting: meeting,
                    in: context
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
                    if a.auto, let collab = a.collaborator {
                        for seg in meeting.transcriptSegments where seg.speakerID == cid + 1 {
                            seg.speaker = collab
                        }
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: assignmentsDict),
                   let s = String(data: data, encoding: .utf8) {
                    meeting.speakerAssignmentsJSON = s
                }
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let s = String(data: data, encoding: .utf8) {
                    meeting.speakerMatchMetaJSON = s
                }
                try? context.save()
            } catch {
                print("[MeetingView] reidentifySpeakers failed: \(error)")
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

