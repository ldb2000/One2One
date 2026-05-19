import SwiftUI
import AVFoundation

/// Waveform interactive avec marqueur draggable et lecture audio.
/// Le parent contrôle `markerSeconds` (binding) pour exécuter trim/split.
struct AudioWaveformEditor: View {
    let url: URL
    @Binding var markerSeconds: Double
    @StateObject private var player = AudioPlayerService()
    @State private var peaks: [Float] = []
    @State private var isLoadingPeaks = true
    @State private var totalDuration: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if isLoadingPeaks {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Canvas { ctx, size in
                            drawPeaks(ctx: ctx, size: size)
                        }
                    }
                    markerLine(width: geo.size.width, height: geo.size.height)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in moveMarker(to: g.location.x, width: geo.size.width) }
                )
            }
            .frame(height: 120)

            controls
        }
        .task { await loadPeaks() }
    }

    private func drawPeaks(ctx: GraphicsContext, size: CGSize) {
        guard !peaks.isEmpty else { return }
        let midY = size.height / 2
        let barWidth = size.width / CGFloat(peaks.count)
        var path = Path()
        for (i, p) in peaks.enumerated() {
            let x = CGFloat(i) * barWidth + barWidth / 2
            let h = CGFloat(p) * (size.height / 2 - 4)
            path.move(to: CGPoint(x: x, y: midY - h))
            path.addLine(to: CGPoint(x: x, y: midY + h))
        }
        ctx.stroke(path, with: .color(.secondary.opacity(0.65)), lineWidth: max(1, barWidth - 1))
    }

    private func markerLine(width: CGFloat, height: CGFloat) -> some View {
        let x = totalDuration > 0 ? CGFloat(markerSeconds / totalDuration) * width : 0
        return Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: height)
            .offset(x: x)
    }

    private func moveMarker(to x: CGFloat, width: CGFloat) {
        guard totalDuration > 0 else { return }
        let clamped = min(max(x, 0), width)
        markerSeconds = Double(clamped / width) * totalDuration
        player.seek(to: markerSeconds)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if player.isPlaying { player.pause() } else {
                    try? player.load(url: url)
                    player.seek(to: markerSeconds)
                    player.play()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)

            Text(format(markerSeconds))
                .font(.body.monospacedDigit())
            Text("/")
                .foregroundStyle(.tertiary)
            Text(format(totalDuration))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Slider(value: $markerSeconds, in: 0...max(totalDuration, 0.01)) { editing in
                if !editing { player.seek(to: markerSeconds) }
            }
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 4)
    }

    private func loadPeaks() async {
        totalDuration = AudioFileEditor.duration(url: url)
        do {
            peaks = try await AudioWaveform.peaks(url: url, count: 600)
        } catch {
            peaks = []
        }
        isLoadingPeaks = false
    }

    private func format(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
