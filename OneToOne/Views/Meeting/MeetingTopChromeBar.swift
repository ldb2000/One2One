import SwiftUI

struct MeetingTopChromeBar: View {
    @Bindable var meeting: Meeting
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var captureService: ScreenCaptureService
    let isGeneratingReport: Bool
    let reportProgressChars: Int
    let reportElapsedSeconds: Int
    let capturedSlidesCount: Int
    let hasWav: Bool

    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onTogglePause: () -> Void
    let onTogglePlay: () -> Void
    let onRetranscribe: () -> Void
    let onGenerateReport: () -> Void
    let onShowCaptureSetup: () -> Void
    let onShowSlides: () -> Void
    let onToggleCustomPrompt: () -> Void
    let onImportCalendar: () -> Void
    let onImportExistingWAV: () -> Void
    let onExportMarkdown: () -> Void
    let onExportPDF: () -> Void
    let onExportMail: (MeetingMailExportOptions) -> Void
    let onExportOutlook: (MeetingMailExportOptions) -> Void
    let onExportAppleNotes: (MeetingMailExportOptions) -> Void
    let onSaveNow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            breadcrumb
            Spacer()
            recorderPill
            captureButton
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
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
    }

    // MARK: - Recorder pill

    @ViewBuilder
    private var recorderPill: some View {
        if recorder.isRecording {
            recordingPill
        } else if hasWav {
            playbackPill
        } else {
            idlePill
        }
    }

    private var idlePill: some View {
        Button(action: onStartRecording) {
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
            Button(action: onTogglePause) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            Button(action: onStopRecording) {
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
            Text("\(formatDuration(player.currentTime)) / \(formatDuration(max(player.duration, TimeInterval(meeting.durationSeconds))))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
            Button(action: onRetranscribe) {
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
        Button(action: onGenerateReport) {
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

    // MARK: - More menu

    private var moreMenu: some View {
        Menu {
            Section("Exporter") {
                Button(action: onExportMarkdown) { Label("Copier Markdown", systemImage: "doc.text") }
                Button(action: onExportPDF) { Label("Exporter PDF", systemImage: "doc.richtext") }

                Menu {
                    Button { onExportMail([]) } label: {
                        Label("Rapport seul", systemImage: "envelope")
                    }
                    Button { onExportMail(.includeSlidesPDF) } label: {
                        Label("Rapport + slides (PDF)", systemImage: "envelope.badge")
                    }
                    Button { onExportMail([.includeTranscript]) } label: {
                        Label("Rapport + transcript", systemImage: "envelope")
                    }
                    Button { onExportMail([.includeTranscript, .includeSlidesPDF]) } label: {
                        Label("Rapport + transcript + slides", systemImage: "envelope.badge")
                    }
                } label: {
                    Label("Envoyer via Apple Mail", systemImage: "envelope")
                }

                Menu {
                    Button { onExportOutlook([]) } label: {
                        Label("Rapport seul", systemImage: "envelope")
                    }
                    Button { onExportOutlook(.includeSlidesPDF) } label: {
                        Label("Rapport + slides (PDF)", systemImage: "envelope.badge")
                    }
                    Button { onExportOutlook([.includeTranscript]) } label: {
                        Label("Rapport + transcript", systemImage: "envelope")
                    }
                    Button { onExportOutlook([.includeTranscript, .includeSlidesPDF]) } label: {
                        Label("Rapport + transcript + slides", systemImage: "envelope.badge")
                    }
                } label: {
                    Label("Envoyer via Microsoft Outlook", systemImage: "paperplane")
                }

                Menu {
                    Button { onExportAppleNotes([]) } label: {
                        Label("Rapport seul", systemImage: "note.text")
                    }
                    Button { onExportAppleNotes(.includeSlidesPDF) } label: {
                        Label("Rapport + slides", systemImage: "note.text.badge.plus")
                    }
                    Button { onExportAppleNotes([.includeTranscript]) } label: {
                        Label("Rapport + transcript", systemImage: "note.text")
                    }
                    Button { onExportAppleNotes([.includeTranscript, .includeSlidesPDF]) } label: {
                        Label("Rapport + transcript + slides", systemImage: "note.text.badge.plus")
                    }
                } label: {
                    Label("Exporter vers Apple Notes", systemImage: "note.text")
                }
            }
            Divider()
            Button(action: onToggleCustomPrompt) { Label("Prompt spécifique", systemImage: "text.bubble") }
            Button(action: onImportCalendar) { Label("Importer Calendrier", systemImage: "calendar.badge.plus") }
            Button(action: onImportExistingWAV) { Label("Importer un WAV existant", systemImage: "waveform.badge.plus") }
            Divider()
            Button(action: onSaveNow) { Label("Enregistrer maintenant", systemImage: "checkmark.circle") }
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
