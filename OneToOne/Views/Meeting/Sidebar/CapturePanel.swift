import SwiftUI

/// Panneau Capture de la sidebar configurable. Affiche le dernier slide capturé
/// + boutons pour ouvrir la galerie ou la configuration de capture. Refactor
/// pur — code identique à `capturePreviewCard` de l'ancien MeetingActionsSidebar.
struct CapturePanel: View {

    let currentSlides: [SlideCapture]
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            if let latest = currentSlides.last,
               let image = NSImage(contentsOfFile: latest.imagePath) {
                Button(action: onShowSlides) {
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
                            .stroke(MeetingTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onShowCaptureSetup) {
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
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}
