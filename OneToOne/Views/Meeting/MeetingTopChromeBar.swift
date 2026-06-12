import SwiftUI
import SwiftData

/// Barre supérieure (« chrome ») de l'écran réunion : fil d'Ariane, pill
/// d'enregistrement/lecture, capture, sélecteur de template, génération de
/// rapport et menu « … ». Vue purement présentationnelle : toute la logique
/// métier est déléguée au parent via les callbacks `on…`.
struct MeetingTopChromeBar: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [ReportTemplate]
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var captureService: ScreenCaptureService
    let isGeneratingReport: Bool
    let reportProgressChars: Int
    let reportElapsedSeconds: Int
    let capturedSlidesCount: Int

    /// Source d'actions partagée avec les menus natifs (cf. MeetingMenuActions).
    let actions: MeetingMenuActions

    // Closures propres à la barre (absentes des menus natifs) :
    /// Bascule lecture/pause de l'audio enregistré.
    let onTogglePlay: () -> Void
    /// Ouvre la configuration de la source de capture d'écran.
    let onShowCaptureSetup: () -> Void
    /// Ouvre la galerie des slides capturées.
    let onShowSlides: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            breadcrumb
            Spacer()
            recorderPill
            captureButton
            templatePickerButton
            reportButton
            moreMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MeetingTheme.canvasCream)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MeetingTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text("One2One").foregroundColor(.secondary)
            chevron
            if let project = meeting.project {
                Text("Projets").foregroundColor(.secondary)
                chevron
                Text(project.name).fontWeight(.semibold).foregroundColor(.primary)
            } else {
                Text(meeting.kind.label).fontWeight(.semibold).foregroundColor(.primary)
            }
            audioStatusBadge
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// Badge d'état de disponibilité de l'audio dans le fil d'Ariane.
    /// - `.original` : audio intact → aucun badge affiché.
    /// - `.compressed` : audio recompressé (AAC) → badge informatif (qualité STT dégradée).
    /// - `.deleted` : audio purgé par la politique de rétention → badge « archivé ».
    @ViewBuilder
    private var audioStatusBadge: some View {
        switch meeting.audioAvailability {
        case .original:
            EmptyView()
        case .compressed:
            Label("Audio compressé", systemImage: "archivebox")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .help("Audio compressé (AAC 32 kbps mono) — qualité STT dégradée si re-transcription")
        case .deleted:
            Label("Audio archivé", systemImage: "trash")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .help("Audio supprimé après 30 jours (politique de rétention). Rapport et transcription conservés.")
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
    }

    // MARK: - Recorder pill

    @ViewBuilder
    private var recorderPill: some View {
        if recorder.isRecording {
            recordingPill
        } else if actions.hasWav {
            playbackPill
        } else {
            idlePill
        }
    }

    private var idlePill: some View {
        Button(action: actions.startRecording) {
            Label("Enregistrer", systemImage: "record.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.red))
        }
        .buttonStyle(.plain)
        .disabled(stt.isTranscribing || isGeneratingReport)
    }

    private var recordingPill: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(formatDuration(recorder.elapsedSeconds))
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
            Button(action: actions.togglePause) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            Button(action: actions.stopRecording) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(MeetingTheme.badgeBlack))
    }

    private var playbackPill: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlay) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .disabled(!meeting.hasPlayableAudio)
            .opacity(meeting.hasPlayableAudio ? 1.0 : 0.4)
            .help(meeting.hasPlayableAudio ? "Lecture" : "Audio supprimé après politique de rétention")
            Text("\(formatDuration(player.currentTime)) / \(formatDuration(max(player.duration, TimeInterval(meeting.durationSeconds))))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
            Button(action: actions.appendRecording) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Reprendre l'enregistrement (concaténation)")
            .disabled(stt.isTranscribing || isGeneratingReport)
            Button(action: actions.retranscribe) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .disabled(stt.isTranscribing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(MeetingTheme.badgeBlack))
    }

    // MARK: - Capture button

    @ViewBuilder
    private var captureButton: some View {
        if captureService.isCapturing {
            HStack(spacing: 4) {
                Button(action: onShowSlides) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                        Text("\(captureService.capturedSlidesCount) slides")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Voir les slides capturées")

                Menu {
                    Button {
                        onShowCaptureSetup()
                    } label: {
                        Label("Changer la source…", systemImage: "rectangle.dashed.badge.record")
                    }
                    Button(role: .destructive) {
                        Task { await captureService.stop() }
                    } label: {
                        Label("Arrêter la capture", systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Options de capture")
            }
        } else if capturedSlidesCount > 0 {
            Button(action: onShowSlides) {
                Label("Capture", systemImage: "camera.viewfinder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .overlay(alignment: .topTrailing) {
                Text("\(capturedSlidesCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 4, y: -4)
            }
        } else {
            Button(action: onShowCaptureSetup) {
                Label("Capture", systemImage: "camera.viewfinder").font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Report button

    @ViewBuilder
    private var reportButton: some View {
        let disabled = meeting.rawTranscript.isEmpty || recorder.isRecording || stt.isTranscribing || isGeneratingReport
        Button(action: actions.generateReport) {
            HStack(spacing: 6) {
                if isGeneratingReport {
                    ProgressView().controlSize(.small).tint(.white)
                    if reportProgressChars > 0 {
                        Text("\(reportProgressChars) car. · \(formatElapsed(reportElapsedSeconds))")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("Rapport… \(formatElapsed(reportElapsedSeconds))")
                            .font(.caption.monospacedDigit())
                    }
                } else {
                    Image(systemName: "wand.and.stars")
                    if meeting.summary.isEmpty {
                        Text("Rapport")
                    } else if meeting.reportGenerationDurationSeconds > 0 {
                        Text("Rapport ✓ (\(formatElapsed(Int(meeting.reportGenerationDurationSeconds.rounded()))))")
                    } else {
                        Text("Rapport ✓")
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(disabled ? Color.secondary.opacity(0.4) : MeetingTheme.accentOrange)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Template picker

    private var templatePickerButton: some View {
        Menu {
            Button("Auto (selon type)") {
                meeting.reportTemplate = nil
                try? modelContext.save()
            }
            Divider()
            ForEach(compatibleTemplates) { t in
                Button(t.name) {
                    meeting.reportTemplate = t
                    try? modelContext.save()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                Text(meeting.reportTemplate?.name ?? "Auto")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Template de rapport — modifie la structure du compte-rendu généré")
    }

    /// Templates non archivés proposés dans le sélecteur, triés par priorité :
    /// d'abord le `ReportTemplateKind` correspondant au type de la réunion,
    /// puis par ordre alphabétique (insensible à la casse).
    private var compatibleTemplates: [ReportTemplate] {
        let mapping: [MeetingKind: ReportTemplateKind] = [
            .global: .general,
            .oneToOne: .oneToOne,
            .manager: .manager,
            .project: .copil,
            .work: .general
        ]
        let preferred = mapping[meeting.kind] ?? .general
        return allTemplates
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let li = lhs.kind == preferred ? 0 : 1
                let ri = rhs.kind == preferred ? 0 : 1
                if li != ri { return li < ri }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - More menu

    private var moreMenu: some View {
        Menu {
            Menu {
                Button(action: actions.exportMarkdown) { Label("Copier Markdown", systemImage: "doc.text") }
                Button(action: actions.exportPDF) { Label("Exporter PDF", systemImage: "doc.richtext") }
                Menu {
                    Button { actions.exportMail([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportMail(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportMail([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportMail([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Apple Mail", systemImage: "envelope") }
                Menu {
                    Button { actions.exportOutlook([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportOutlook(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportOutlook([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportOutlook([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Microsoft Outlook", systemImage: "paperplane") }
                Menu {
                    Button { actions.exportAppleNotes([]) } label: { Label("Rapport seul", systemImage: "note.text") }
                    Button { actions.exportAppleNotes(.includeSlidesPDF) } label: { Label("Rapport + slides", systemImage: "note.text.badge.plus") }
                    Button { actions.exportAppleNotes([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "note.text") }
                    Button { actions.exportAppleNotes([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "note.text.badge.plus") }
                } label: { Label("Exporter vers Apple Notes", systemImage: "note.text") }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }
            .disabled(!actions.hasReport)

            Divider()
            Button(action: actions.toggleCustomPrompt) { Label("Prompt spécifique", systemImage: "text.bubble") }
            Menu {
                Button(action: actions.importCalendar) { Label("Importer Calendrier", systemImage: "calendar.badge.plus") }
                Button(action: actions.importExistingWAV) { Label("Importer un WAV existant", systemImage: "waveform.badge.plus") }
            } label: { Label("Importer", systemImage: "square.and.arrow.down") }
            Menu {
                Button(action: actions.editAudio) { Label("Éditer l'audio…", systemImage: "scissors") }
                    .disabled(!actions.hasPlayableAudio)
                Button(action: actions.revealWAV) { Label("Révéler le WAV dans Finder", systemImage: "folder") }
                    .disabled(!actions.hasPlayableAudio)
            } label: { Label("Audio", systemImage: "waveform") }

            Divider()
            Button(role: .destructive, action: actions.deleteMeeting) {
                Label("Supprimer la réunion…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
