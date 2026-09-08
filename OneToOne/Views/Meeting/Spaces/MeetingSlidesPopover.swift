import SwiftUI

/// La galerie des captures de la séance, ouverte depuis la barre du haut.
///
/// Extraite de `MeetingView` telle quelle (le programme interdit d'ajouter à
/// ce fichier), avec ses seuls jetons repris sur `One2OneToken`. Le lot 7 la
/// remplace par `CapturesStrip`, en pied de la colonne principale, avec les
/// vignettes 132 × 76 et le déclencheur de chaque capture.
struct MeetingSlidesPopover: View {
    let slides: [SlideCapture]
    let onDelete: (SlideCapture) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("CAPTURES DE LA SÉANCE").sectionLabel()
                MonoMeta("\(slides.count)", emphase: !slides.isEmpty)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(alignment: .bottom) {
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
            }

            if slides.isEmpty {
                MeetingEmptyInvite(
                    titre: "Aucune capture",
                    invite: "Configurez la source de capture dans la barre du haut : chaque changement de partage sera enregistré."
                )
                .frame(width: 300, height: 400)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(slides) { slide in
                            ligne(slide)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .frame(width: 300, height: 400)
            }
        }
    }

    private func ligne(_ slide: SlideCapture) -> some View {
        HStack(spacing: 10) {
            vignette(slide)
            VStack(alignment: .leading, spacing: 3) {
                Text("Capture \(slide.index)")
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                MonoMeta(slide.capturedAt.formatted(date: .omitted, time: .standard))
            }
            Spacer(minLength: 4)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: slide.imagePath))
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(One2OneToken.action)
            }
            .buttonStyle(.plain)
            .help("Ouvrir dans Aperçu")
            Button {
                onDelete(slide)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(One2OneToken.report)
            }
            .buttonStyle(.plain)
            .help("Supprimer cette capture")
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func vignette(_ slide: SlideCapture) -> some View {
        if let image = NSImage(contentsOfFile: slide.imagePath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 60)
                .background(One2OneToken.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview))
        } else {
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                .fill(One2OneToken.surfaceAlt)
                .frame(width: 80, height: 60)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(One2OneToken.inkMuted)
                )
        }
    }
}
