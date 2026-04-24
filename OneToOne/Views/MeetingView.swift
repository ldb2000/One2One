import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MeetingView: View {
    @Bindable var meeting: Meeting
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var allCollaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    // MARK: - Services

    @StateObject private var recorder = AudioRecorderService()
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
    @State private var saveStatusMessage: String?
    @State private var showPlayback: Bool = false
    @SceneStorage("meeting.detailsExpanded") private var detailsExpanded: Bool = true

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
                capturedSlidesCount: currentSlides.count,
                hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
                onStartRecording: { Task { await startRecording() } },
                onStopRecording:  { Task { await stopRecordingAndTranscribe() } },
                onTogglePause:    { if recorder.isPaused { recorder.resume() } else { recorder.pause() } },
                onTogglePlay:     { if let wav = meeting.wavFileURL { togglePlay(url: wav); showPlayback = true } },
                onRetranscribe:   { if let wav = meeting.wavFileURL { Task { await retranscribe(wavURL: wav) } } },
                onGenerateReport: { Task { await generateReport() } },
                onShowCaptureSetup: { showCaptureSetup = true },
                onShowSlides:       { showSlidesList = true },
                onToggleCustomPrompt: { showCustomPrompt.toggle() },
                onImportCalendar:     { showCalendarImporter = true },
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
                onExportMail:       { ExportService().exportMeetingMail(meeting: meeting) },
                onExportEML:        { ExportService().exportMeetingOutlookEML(meeting: meeting) },
                onExportAppleNotes: {
                    let title = meeting.title.isEmpty ? "Réunion" : meeting.title
                    let md = ExportService().exportMeetingMarkdown(meeting: meeting, options: .shareable)
                    ExportService().exportToAppleNotes(title: title, markdownContent: md)
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
                    calendarImportError
                ].compactMap { $0 }.filter { !$0.isEmpty },
                onDismissErrors: {
                    recorder.lastError = nil
                    transcribeError = nil
                    reportError = nil
                    captureService.lastError = nil
                    attachmentError = nil
                    calendarImportError = nil
                }
            )
            .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
            .animation(.easeInOut(duration: 0.15), value: captureService.isCapturing)
            .animation(.easeInOut(duration: 0.15), value: showPlayback)

            HSplitView {
                mainPanel.frame(minWidth: 520)
                actionsPanel.frame(minWidth: 300, maxWidth: 420)
            }
        }
        .navigationTitle(meeting.title.isEmpty ? "Réunion" : meeting.title)
        .sheet(isPresented: $showCalendarImporter) {
            CalendarEventImportSheet(anchorDate: meeting.date) { event in
                importCalendarEvent(event)
            }
        }
        .popover(isPresented: $showSlidesList) { slidesPopover }
        .popover(isPresented: $showCaptureSetup) {
            ScreenCaptureConfigView(service: captureService, meeting: meeting)
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
            activeSection = .transcript
            saveContext()
            print("[MeetingView] retranscribe OK: \(result.text.count) chars")
        } catch {
            transcribeError = error.localizedDescription
            print("[MeetingView] retranscribe FAILED: \(error.localizedDescription)")
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

    /// Vignette de la dernière slide capturée, affichée en haut à droite du header.
    /// Cliquer ouvre le popover de la liste complète (même que le bouton "N slides").
    @ViewBuilder
    private var latestCaptureThumbnail: some View {
        if let latest = currentSlides.last,
           let nsImage = NSImage(contentsOfFile: latest.imagePath) {
            Button(action: { showSlidesList = true }) {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                    Text("Slide \(latest.index) · \(latest.capturedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Dernière capture — clic pour voir toutes les slides")
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
                    if !meeting.mergedTranscript.isEmpty {
                        Text(meeting.mergedTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text(meeting.rawTranscript)
                            .font(.body)
                            .textSelection(.enabled)
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
                                Label(item, systemImage: "sparkles").font(.callout)
                            }
                        }
                    }
                    section("Résumé") {
                        Text(meeting.summary).textSelection(.enabled)
                    }
                    if !meeting.keyPoints.isEmpty {
                        section("Points clés") {
                            ForEach(meeting.keyPoints, id: \.self) { p in
                                Label(p, systemImage: "circle.fill").labelStyle(.titleAndIcon)
                                    .font(.callout)
                            }
                        }
                    }
                    if !meeting.decisions.isEmpty {
                        section("Décisions") {
                            ForEach(meeting.decisions, id: \.self) { d in
                                Label(d, systemImage: "checkmark.seal").font(.callout)
                            }
                        }
                    }
                    if !meeting.openQuestions.isEmpty {
                        section("Questions ouvertes") {
                            ForEach(meeting.openQuestions, id: \.self) { q in
                                Label(q, systemImage: "questionmark.circle").font(.callout)
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
            return existing
        }

        let collaborator = Collaborator(name: attendee.name, role: attendee.email ?? "Calendrier")
        collaborator.isAdhoc = true
        collaborator.pinLevel = 0
        context.insert(collaborator)
        return collaborator
    }

    // MARK: - Actions panel

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            capturePreviewPanel

            HStack {
                Text("Actions").font(.headline)
                let count = meeting.tasks.filter { !$0.isCompleted }.count
                if count > 0 {
                    Text("\(count)").font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.blue).foregroundColor(.white)
                        .cornerRadius(8)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)

            List {
                ForEach(meeting.tasks) { task in
                    taskRow(task)
                }
                .onDelete(perform: deleteTasks)
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                EditableTextField(placeholder: "Nouvelle action…", text: $newTaskTitle).frame(height: 24)
                HStack(spacing: 8) {
                    Picker("Assigné à", selection: $selectedCollaborator) {
                        Text("Non assigné").tag(nil as Collaborator?)
                        ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                    }
                    .pickerStyle(.menu)
                    Toggle(isOn: $showNewTaskDueDate) {
                        Label("Échéance", systemImage: "calendar").font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    if showNewTaskDueDate {
                        DatePicker("", selection: Binding(
                            get: { newTaskDueDate ?? Date() },
                            set: { newTaskDueDate = $0 }
                        ), displayedComponents: .date).labelsHidden()
                    }
                }
                Button(action: addTask) {
                    Label("Ajouter l'action", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        }
    }

    @ViewBuilder
    private var capturePreviewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture")
                .font(.headline)

            Group {
                if let latest = currentSlides.last,
                   let image = NSImage(contentsOfFile: latest.imagePath) {
                    Button(action: { showSlidesList = true }) {
                        ZStack(alignment: .bottomLeading) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .clipped()

                            LinearGradient(
                                colors: [.clear, .black.opacity(0.65)],
                                startPoint: .center,
                                endPoint: .bottom
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Slide \(latest.index)")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Text(latest.capturedAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(10)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Aucune capture")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private func taskRow(_ task: ActionTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: { task.isCompleted.toggle(); saveContext() }) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                EditableTextField(placeholder: "Action…", text: Bindable(task).title)
                    .strikethrough(task.isCompleted)
                    .frame(height: 22)

                Spacer()
                Button(action: { context.delete(task); saveContext() }) {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { task.collaborator },
                    set: { task.collaborator = $0; saveContext() }
                )) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                }
                .pickerStyle(.menu).frame(maxWidth: 140).font(.caption)

                if let dd = task.dueDate {
                    DatePicker("", selection: Binding(
                        get: { dd },
                        set: { task.dueDate = $0; saveContext() }
                    ), displayedComponents: .date).labelsHidden().font(.caption).frame(width: 100)
                    Button(action: { task.dueDate = nil; saveContext() }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption2)
                    }.buttonStyle(.plain)
                } else {
                    Button(action: { task.dueDate = Date(); saveContext() }) {
                        Label("Échéance", systemImage: "calendar.badge.plus").font(.caption).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.leading, 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Recording actions

    private func startRecording() async {
        do {
            let url = try await recorder.start()
            meeting.wavFilePath = url.path
            saveContext()
        } catch {
            recorder.lastError = error.localizedDescription
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard let stopped = recorder.stop() else { return }
        meeting.durationSeconds = Int(stopped.duration)
        meeting.wavFilePath = stopped.url.path
        saveContext()

        print("[MeetingView] stop → WAV=\(stopped.url.path) duration=\(stopped.duration)s")

        // Laisse le FS finaliser le header WAV avant de le relire.
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Sanity checks : fichier existe, taille non nulle, durée > 1s.
        let attrs = try? FileManager.default.attributesOfItem(atPath: stopped.url.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        guard fileSize > 44 else {
            transcribeError = "Fichier audio vide (\(fileSize) octets). Enregistrement échoué."
            print("[MeetingView] WAV invalide: \(fileSize) octets")
            return
        }
        guard stopped.duration >= 1.0 else {
            transcribeError = "Enregistrement trop court (\(String(format: "%.1f", stopped.duration))s). STT désactivé."
            print("[MeetingView] durée trop courte: \(stopped.duration)s")
            return
        }

        transcribeError = nil
        do {
            print("[MeetingView] → transcribe start…")
            let result = try await stt.transcribe(audioURL: stopped.url)
            print("[MeetingView] ← transcribe OK: \(result.text.count) chars")
            meeting.rawTranscript = result.text
            meeting.mergedTranscript = NoteMergeService.merge(
                transcript: result.text,
                liveNotes: meeting.liveNotes
            )
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
        defer { isGeneratingReport = false }

        // Refresh merged transcript au cas où l'utilisateur a édité les notes.
        meeting.mergedTranscript = NoteMergeService.merge(
            transcript: meeting.rawTranscript,
            liveNotes: meeting.liveNotes
        )

        // Phase 8 : RAG historique — injection du contexte pré-LLM.
        let historicalContext = await fetchHistoricalContext()
        let attachmentsContext = await fetchAttachmentsContext()

        let participantsDesc = meeting.participantsDescription
        do {
            let report = try await AIReportService.generate(
                mergedTranscript: meeting.mergedTranscript,
                meetingKind: meeting.kind,
                durationSeconds: meeting.durationSeconds,
                projectName: meeting.project?.name,
                participantsDescription: participantsDesc,
                customPrompt: meeting.customPrompt,
                historicalContext: historicalContext,
                attachmentsContext: attachmentsContext,
                settings: settings
            )
            apply(report: report)
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

    private func deleteTasks(offsets: IndexSet) {
        for idx in offsets { context.delete(meeting.tasks[idx]) }
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

