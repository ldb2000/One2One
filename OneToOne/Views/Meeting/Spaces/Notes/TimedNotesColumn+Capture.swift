import SwiftUI

/// La carte de capture dans la colonne de notes (spec §5.3, capture 4a :
/// vignette `TEAMS` 56 × 36, `Capture 12:08 — tableau de chiffrage`,
/// `Texte extrait : « … »`, et `Agrandir`).
///
/// Dans un fichier d'extension, comme les autres apports du lot 7 : la colonne
/// de notes est réutilisée par trois lots en parallèle, et son fichier ne
/// reçoit ici qu'un aiguillage de trois lignes.
extension TimedNotesColumn {

    /// Géométrie de la vignette dans une note (capture 4a).
    static var captureThumbWidth: CGFloat { 56 }
    static var captureThumbHeight: CGFloat { 36 }

    /// La carte, ou `nil` quand la note ne porte pas de capture — ou quand sa
    /// référence ne mène plus nulle part (capture supprimée) : la colonne
    /// affiche alors la ligne de texte, jamais un cadre vide.
    @ViewBuilder
    func carteDeCapture(for note: MeetingNote) -> some View {
        if let capture = CaptureNoteInsertion.capture(for: note, in: meeting) {
            CaptureNoteCard(capture: capture, note: note, screen: screen)
        }
    }

    /// Vrai si la note doit s'afficher en carte plutôt qu'en ligne de texte.
    func estCarteDeCapture(_ note: MeetingNote) -> Bool {
        CaptureNoteInsertion.capture(for: note, in: meeting) != nil
    }
}

/// La carte elle-même. Vue à part et non `@ViewBuilder` dans l'extension : elle
/// porte un état local (`Agrandir`), et un `@State` ne vit pas dans une
/// extension de vue.
struct CaptureNoteCard: View {

    let capture: SlideCapture
    let note: MeetingNote
    let screen: MeetingScreenModel

    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }
    @State private var agrandie = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            carte
            if agrandie { apercu }
        }
        // Indentée sous la ligne de note qui la précède, comme sur la capture :
        // la carte appartient au propos de la note, elle ne le remplace pas.
        .padding(.leading, TimecodeLabel.width + 8)
    }

    private var carte: some View {
        HStack(alignment: .top, spacing: 10) {
            vignette
            VStack(alignment: .leading, spacing: 2) {
                Text(CaptureStripModel.title(for: capture))
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(c.ink1)
                    .lineLimit(1)
                if let extrait = CaptureStripModel.extractedTextLine(of: capture) {
                    Text(extrait)
                        .font(.plexSans(11.5))
                        .foregroundStyle(c.ink4)
                        .lineLimit(1)
                } else {
                    // L'OCR peut échouer : la capture reste utilisable sans
                    // texte (spec §5.3), et on le dit plutôt que de laisser
                    // une ligne vide qui passerait pour un chargement.
                    Text("Aucun texte extrait de cette capture.")
                        .font(.plexSans(11.5))
                        .foregroundStyle(c.ink4)
                }
            }
            Spacer(minLength: 0)
            Button(agrandie ? "Réduire" : "Agrandir") { agrandie.toggle() }
                .buttonStyle(.plain)
                .font(.plexSans(11, .medium))
                .foregroundStyle(c.actionInk)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(c.surfaceAlt))
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(c.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if let t = capture.t { screen.playhead.seek(to: t) } }
        .help("Replacer la lecture à \(MeetingPlayhead.mmss(capture.t ?? 0))")
    }

    /// La vignette 56 × 36. Le badge de source prend le relais quand le fichier
    /// a disparu : `TEAMS` dit encore d'où venait l'image.
    @ViewBuilder
    private var vignette: some View {
        let cadre = RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
        if let image = CaptureThumbnailCache.shared.thumbnail(forPath: capture.imagePath) {
            Image(decorative: image, scale: 2, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: TimedNotesColumn.captureThumbWidth,
                       height: TimedNotesColumn.captureThumbHeight)
                .clipShape(cadre)
                .overlay(cadre.strokeBorder(c.cardBorder, lineWidth: 1))
        } else {
            Text(capture.source.label.uppercased())
                .font(.plexMono(8.5, .semibold))
                .foregroundStyle(c.actionInk)
                .frame(width: TimedNotesColumn.captureThumbWidth,
                       height: TimedNotesColumn.captureThumbHeight)
                .background(cadre.fill(c.actionBg))
        }
    }

    /// `Agrandir` : l'image en pleine largeur de colonne, sans fenêtre ni
    /// feuille — on est en séance, ouvrir une modale coûterait le fil.
    @ViewBuilder
    private var apercu: some View {
        if let image = CaptureThumbnailCache.shared.thumbnail(forPath: capture.imagePath) {
            Image(decorative: image, scale: 2, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview))
                .padding(.top, 6)
        }
    }
}
