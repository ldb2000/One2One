import SwiftUI

/// Barre contextuelle affichée en haut de la réunion : VU-mètre d'enregistrement,
/// lecteur audio, capture d'écran et progression STT/OCR. N'apparaît que lorsqu'au
/// moins une activité est en cours (enregistrement, lecture, capture, transcription, erreurs).
struct MeetingContextualRecorderBar: View {
    /// Service d'enregistrement audio (état `isRecording`, niveau `averagePower`).
    @ObservedObject var recorder: AudioRecorderService
    /// Service de transcription (progression et libellé affichés dans le segment de progression).
    @ObservedObject var stt: TranscriptionService
    /// Lecteur audio piloté par le segment de lecture (slider, skip).
    @ObservedObject var player: AudioPlayerService
    /// Service de capture d'écran (slides capturées, progression OCR).
    @ObservedObject var captureService: ScreenCaptureService

    /// Vrai si un fichier WAV existe ; conditionne l'affichage du segment de lecture.
    let hasWav: Bool
    /// Autorise l'affichage du segment de lecture (sinon masqué même si `hasWav`).
    let showPlayback: Bool
    /// Déclenche un snapshot manuel de la capture d'écran.
    let onSnapshot: () -> Void
    /// Arrête la capture d'écran en cours.
    let onStopCapture: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSkip: (TimeInterval) -> Void

    let errors: [String]
    let onDismissErrors: () -> Void

    var body: some View {
        let visible = recorder.isRecording || (showPlayback && hasWav) || captureService.isCapturing
            || stt.isTranscribing || captureService.ocrProgress != nil || !errors.isEmpty

        if visible {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if recorder.isRecording {
                        recordingSegment
                    } else if showPlayback && hasWav {
                        playbackSegment
                    }

                    if (recorder.isRecording || (showPlayback && hasWav)) && captureService.isCapturing {
                        Divider().frame(height: 20)
                    }

                    if captureService.isCapturing {
                        captureSegment
                    }

                    Spacer()

                    progressSegment
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)

                if !errors.isEmpty {
                    errorBar
                }
            }
            .background(MeetingTheme.surfaceCream)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MeetingTheme.hairline).frame(height: 0.5)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Segment d'enregistrement : VU-mètre + niveau d'entrée en dB.
    private var recordingSegment: some View {
        HStack(spacing: 10) {
            vuMeter
            Text(String(format: "Niveau : %.0f dB", recorder.averagePower))
                .font(MeetingTheme.meta)
                .foregroundColor(.secondary)
        }
    }

    private var vuMeter: some View {
        let level = max(0, min(1, (recorder.averagePower + 60) / 60))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(level > 0.7 ? Color.red : (level > 0.3 ? Color.orange : Color.green))
                    .frame(width: CGFloat(level) * geo.size.width)
            }
        }
        .frame(width: 140, height: 8)
    }

    /// Segment de lecture : boutons skip ±15 s et slider de position (masqué si durée nulle).
    private var playbackSegment: some View {
        HStack(spacing: 8) {
            Button { onSkip(-15) } label: { Image(systemName: "gobackward.15") }.buttonStyle(.borderless)
            Button { onSkip(15) } label: { Image(systemName: "goforward.15") }.buttonStyle(.borderless)

            if player.duration > 0 {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { onSeek($0) }
                    ),
                    in: 0...max(player.duration, 0.1)
                )
                .frame(minWidth: 160, maxWidth: 360)
            } else {
                Color.clear.frame(width: 160, height: 1)
            }
        }
    }

    /// Segment de capture d'écran : compteur de slides + boutons snapshot/arrêt.
    private var captureSegment: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder").foregroundColor(.blue)
            Text("Capture : \(captureService.capturedSlidesCount) slides")
                .font(.caption)
            Button(action: onSnapshot) { Image(systemName: "camera.fill") }
                .buttonStyle(.bordered)
                .help("Snapshot manuel")
            Button(action: onStopCapture) { Image(systemName: "stop.fill") }
                .buttonStyle(.bordered)
                .help("Arrêter la capture")
        }
    }

    /// Segment de progression : barre/spinner STT (avec pourcentage) et progression OCR.
    @ViewBuilder
    private var progressSegment: some View {
        HStack(spacing: 10) {
            if stt.isTranscribing {
                HStack(spacing: 6) {
                    if stt.progressFraction > 0 {
                        ZStack {
                            ProgressView(value: stt.progressFraction)
                                .progressViewStyle(.linear)
                                .frame(width: 140)
                            Text("\(Int(stt.progressFraction * 100)) %")
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        }
                        .frame(width: 140)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if !stt.progressLabel.isEmpty {
                        Text(stt.progressLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    } else {
                        Text("STT…").font(.caption.monospacedDigit())
                    }
                }
            }
            if let p = captureService.ocrProgress {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("OCR \(p.current)/\(p.total)").font(.caption.monospacedDigit())
                }
            }
        }
    }

    private var errorBar: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, msg in
                    Text(msg).font(.caption).foregroundColor(.red)
                }
            }
            Spacer()
            Button(action: onDismissErrors) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
    }
}
