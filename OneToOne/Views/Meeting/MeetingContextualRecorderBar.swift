import SwiftUI

struct MeetingContextualRecorderBar: View {
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var captureService: ScreenCaptureService

    let hasWav: Bool
    let showPlayback: Bool
    let onSnapshot: () -> Void
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

    @ViewBuilder
    private var progressSegment: some View {
        HStack(spacing: 10) {
            if stt.isTranscribing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("STT…").font(.caption.monospacedDigit())
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
