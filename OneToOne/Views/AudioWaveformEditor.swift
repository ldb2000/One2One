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

    // Layout constants — partagés entre `drawPeaks` et `marker` (doivent
    // matcher pour que la ligne verticale s'aligne avec les barres).
    private static let topPad: CGFloat = 28
    private static let bottomPad: CGFloat = 22

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

    /// Dessine la waveform dans le `Canvas` : barres centrées verticalement,
    /// colorées en accent (zone conservée) ou grisées (zone supprimée) selon le
    /// `mode` et la position du marqueur. Les barres sont agrégées en deux paths
    /// (actif/inactif) pour ne produire que deux strokes au lieu d'un par barre.
    private func drawPeaks(ctx: GraphicsContext, size: CGSize) {
        guard !peaks.isEmpty, totalDuration > 0 else { return }
        let availableHeight = size.height - Self.topPad - Self.bottomPad
        let midY = Self.topPad + availableHeight / 2
        let barWidth = size.width / CGFloat(peaks.count)
        let lineWidth = max(1.5, barWidth - 1.5)
        let markerX = CGFloat(markerSeconds / totalDuration) * size.width

        // Hoist le test mode hors de la boucle : `mode` est const pour tout
        // l'appel. Résultat : 2 paths agrégés (actif/inactif) + 2 strokes,
        // au lieu de 180 paths + 180 strokes.
        let isActive: (CGFloat) -> Bool
        switch mode {
        case .trimStart: isActive = { $0 >= markerX }
        case .trimEnd:   isActive = { $0 <= markerX }
        case .split:     isActive = { _ in true }
        }

        var activePath = Path()
        var inactivePath = Path()
        for (i, p) in peaks.enumerated() {
            let x = CGFloat(i) * barWidth + barWidth / 2
            let h = max(2, CGFloat(p) * (availableHeight / 2 - 4))
            let p1 = CGPoint(x: x, y: midY - h)
            let p2 = CGPoint(x: x, y: midY + h)
            if isActive(x) {
                activePath.move(to: p1); activePath.addLine(to: p2)
            } else {
                inactivePath.move(to: p1); inactivePath.addLine(to: p2)
            }
        }
        ctx.stroke(activePath, with: .color(.accentColor), lineWidth: lineWidth)
        ctx.stroke(inactivePath, with: .color(.secondary.opacity(0.35)), lineWidth: lineWidth)
    }

    /// Marqueur draggable positionné à `markerSeconds` : ligne verticale,
    /// poignées circulaires en haut/bas et bulle affichant le temps. Le `width`
    /// est l'espace horizontal disponible pour convertir le temps en position x.
    @ViewBuilder
    private func marker(width: CGFloat, height: CGFloat) -> some View {
        let x = totalDuration > 0 ? CGFloat(markerSeconds / totalDuration) * width : 0
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: height - Self.topPad - Self.bottomPad)
                .offset(x: x - 1, y: Self.topPad)
            Text(formatAudioTime(markerSeconds))
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
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(x: x - 5, y: Self.topPad - 5)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(x: x - 5, y: height - Self.bottomPad - 5)
        }
    }

    /// Règle temporelle sous la waveform : 5 graduations équidistantes de 0 à
    /// `totalDuration`, formatées par `formatAudioTime`.
    @ViewBuilder
    private func timeRuler(width: CGFloat) -> some View {
        HStack {
            ForEach(0..<5) { i in
                let frac = Double(i) / 4.0
                Text(formatAudioTime(frac * totalDuration))
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

            Text("\(formatAudioTime(scrubberValue))  /  \(formatAudioTime(totalDuration))")
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

}
