import SwiftUI
import AVFoundation

/// Mode visuel de l'éditeur — détermine quelle portion est "conservée" (accent)
/// vs "supprimée" (grisée) autour du marker.
enum AudioWaveformEditorMode {
    /// Marker = début de la zone conservée. Tout AVANT le marker = supprimé.
    case trimStart
    /// Marker = fin de la zone conservée. Tout APRÈS le marker = supprimé.
    case trimEnd
    /// Marker = point de coupe. Les deux portions sont "conservées" (accent),
    /// séparées par une ligne verticale.
    case split
}

/// Waveform interactive avec marqueur draggable, bulle de temps + scrubber
/// de lecture. Bicolore selon le mode (zone supprimée grisée).
struct AudioWaveformEditor: View {
    let url: URL
    @Binding var markerSeconds: Double
    let mode: AudioWaveformEditorMode

    @StateObject private var player = AudioPlayerService()
    @State private var peaks: [Float] = []
    @State private var isLoadingPeaks = true
    @State private var totalDuration: Double = 0
    @State private var scrubberValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 14) {
            waveformBlock
                .frame(height: 200)
            playbackRow
        }
        .task { await loadPeaks() }
        .onReceive(player.$currentTime) { t in
            if !isScrubbing { scrubberValue = t }
        }
    }

    // MARK: - Waveform

    @ViewBuilder
    private var waveformBlock: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if isLoadingPeaks {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Canvas { ctx, size in drawPeaks(ctx: ctx, size: size) }
                }
                marker(width: geo.size.width, height: geo.size.height)
                timeRuler(width: geo.size.width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in moveMarker(to: g.location.x, width: geo.size.width) }
            )
        }
    }

    private func drawPeaks(ctx: GraphicsContext, size: CGSize) {
        guard !peaks.isEmpty, totalDuration > 0 else { return }
        let topPadding: CGFloat = 28
        let bottomPadding: CGFloat = 22
        let availableHeight = size.height - topPadding - bottomPadding
        let midY = topPadding + availableHeight / 2
        let barWidth = size.width / CGFloat(peaks.count)

        let markerX = CGFloat(markerSeconds / totalDuration) * size.width
        let activeColor = Color.accentColor
        let inactiveColor = Color.secondary.opacity(0.35)

        for (i, p) in peaks.enumerated() {
            let x = CGFloat(i) * barWidth + barWidth / 2
            let h = max(2, CGFloat(p) * (availableHeight / 2 - 4))
            let color: Color
            switch mode {
            case .trimStart:
                color = (x >= markerX) ? activeColor : inactiveColor
            case .trimEnd:
                color = (x <= markerX) ? activeColor : inactiveColor
            case .split:
                color = activeColor
            }
            var path = Path()
            path.move(to: CGPoint(x: x, y: midY - h))
            path.addLine(to: CGPoint(x: x, y: midY + h))
            ctx.stroke(path, with: .color(color), lineWidth: max(1.5, barWidth - 1.5))
        }
    }

    @ViewBuilder
    private func marker(width: CGFloat, height: CGFloat) -> some View {
        let x = totalDuration > 0 ? CGFloat(markerSeconds / totalDuration) * width : 0
        let topPad: CGFloat = 28
        let bottomPad: CGFloat = 22
        ZStack(alignment: .top) {
            // Ligne verticale
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: height - topPad - bottomPad)
                .offset(x: x - 1, y: topPad)
            // Bulle de temps
            Text(formatTime(markerSeconds))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                )
                .overlay(
                    Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                )
                .offset(x: x - 28, y: 0)
            // Pastille haut
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(x: x - 5, y: topPad - 5)
            // Pastille bas
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(x: x - 5, y: height - bottomPad - 5)
        }
    }

    @ViewBuilder
    private func timeRuler(width: CGFloat) -> some View {
        HStack {
            ForEach(0..<5) { i in
                let frac = Double(i) / 4.0
                Text(formatTime(frac * totalDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if i < 4 { Spacer() }
            }
        }
        .padding(.horizontal, 2)
    }

    private func moveMarker(to x: CGFloat, width: CGFloat) {
        guard totalDuration > 0 else { return }
        let clamped = min(max(x, 0), width)
        markerSeconds = Double(clamped / width) * totalDuration
        player.seek(to: markerSeconds)
        scrubberValue = markerSeconds
    }

    // MARK: - Playback row

    @ViewBuilder
    private var playbackRow: some View {
        HStack(spacing: 12) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)

            Text("\(formatTime(scrubberValue))  /  \(formatTime(totalDuration))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(
                value: $scrubberValue,
                in: 0...max(totalDuration, 0.01),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { player.seek(to: scrubberValue) }
                }
            )
        }
    }

    private func togglePlay() {
        if player.isPlaying {
            player.pause()
        } else {
            try? player.load(url: url)
            player.seek(to: scrubberValue)
            player.play()
        }
    }

    // MARK: - Helpers

    private func loadPeaks() async {
        totalDuration = AudioFileEditor.duration(url: url)
        scrubberValue = 0
        do {
            peaks = try await AudioWaveform.peaks(url: url, count: 180)
        } catch {
            peaks = []
        }
        isLoadingPeaks = false
    }

    private func formatTime(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
