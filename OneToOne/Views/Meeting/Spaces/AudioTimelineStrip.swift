import SwiftUI

/// La frise audio de 22 px en pied de la carte notes ↔ transcription
/// (spec §2.4, capture `1a-cockpit.png` : `00:00` … `23:24`, onde, tête bleue,
/// marqueur rouge de décision, marqueur bleu de note).
///
/// « Onde échantillonnée, tête de lecture 2 px `accent/action`, marqueurs ronds
/// (note), carrés (capture), losanges (décision). Clic = déplacement, glisser =
/// balayage. »
///
/// Sans fichier audio, la frise **reste affichée** : une piste plate, les
/// marqueurs des notes déjà prises et l'invite « Aucun audio ». C'est l'axe
/// temps de la réunion, pas seulement celui d'un enregistrement.
struct AudioTimelineStrip: View {

    let meeting: Meeting
    let screen: MeetingScreenModel

    @State private var peaks: [Float] = []

    private var playhead: MeetingPlayhead { screen.playhead }

    /// Durée de l'axe : celle du fichier chargé, sinon celle enregistrée sur la
    /// réunion. Zéro quand la réunion n'a pas encore d'axe temps.
    private var duration: Double {
        playhead.duration > 0 ? playhead.duration : Double(meeting.durationSeconds)
    }

    private var hasAudio: Bool { meeting.wavFileURL != nil }

    var body: some View {
        HStack(spacing: 8) {
            Text(TimecodeLabel.format(0))
                .font(.plexMono(9.5, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.ink4)
            piste
            Text(TimecodeLabel.format(duration))
                .font(.plexMono(9.5, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.ink4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: AudioTimelineGeometry.height + 12)
        .overlay(alignment: .top) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    private var piste: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            ZStack(alignment: .leading) {
                Canvas { ctx, size in dessiner(ctx: ctx, size: size) }
                if !hasAudio {
                    Text("Aucun audio")
                        .font(.plexSans(10))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(height: AudioTimelineGeometry.height)
            .contentShape(Rectangle())
            .gesture(
                // Clic **et** glisser : un `DragGesture` de distance minimale
                // nulle rend les deux, là où un `onTapGesture` ne donnerait
                // pas le balayage continu de la spec.
                DragGesture(minimumDistance: 0)
                    .onChanged { valeur in deplacer(vers: valeur.location.x, largeur: largeur) }
            )
            .task(id: TacheOnde(chemin: meeting.wavFilePath ?? "", largeur: largeur)) {
                await chargerOnde(largeur: largeur)
            }
        }
        .frame(height: AudioTimelineGeometry.height)
    }

    /// Identité de la tâche de chargement : le fichier **et** la largeur. Sans
    /// la largeur, un redimensionnement garderait une onde à l'ancienne
    /// résolution ; sans le chemin, un changement de fichier passerait
    /// inaperçu.
    private struct TacheOnde: Equatable {
        let chemin: String
        let largeur: CGFloat
    }

    // MARK: - Dessin

    private func dessiner(ctx: GraphicsContext, size: CGSize) {
        let d = duration
        // Piste de fond : c'est elle qui rend la frise lisible quand il n'y a
        // pas encore d'onde à dessiner.
        let fond = Path(roundedRect: CGRect(x: 0, y: size.height / 2 - 3,
                                            width: size.width, height: 6),
                        cornerRadius: 3)
        ctx.fill(fond, with: .color(One2OneToken.hair))

        if !peaks.isEmpty {
            let largeurPic = size.width / CGFloat(peaks.count)
            var onde = Path()
            for (index, pic) in peaks.enumerated() {
                let hauteur = max(2, CGFloat(pic) * (size.height - 4))
                let x = CGFloat(index) * largeurPic
                onde.addRect(CGRect(x: x,
                                    y: (size.height - hauteur) / 2,
                                    width: max(1, largeurPic - 1),
                                    height: hauteur))
            }
            ctx.fill(onde, with: .color(One2OneToken.actionBg))
        }

        // Marqueurs sous la tête de lecture : un repère masqué par le curseur
        // serait un repère perdu.
        for repere in playhead.markers {
            let x = AudioTimelineGeometry.x(t: repere.t, duration: d, width: size.width)
            dessiner(repere, at: x, ctx: ctx, size: size)
        }

        if d > 0 {
            let x = AudioTimelineGeometry.x(t: playhead.t, duration: d, width: size.width)
            let tete = Path(CGRect(x: max(0, x - AudioTimelineGeometry.playheadWidth / 2),
                                   y: 0,
                                   width: AudioTimelineGeometry.playheadWidth,
                                   height: size.height))
            ctx.fill(tete, with: .color(One2OneToken.action))
        }
    }

    /// Rond (note), losange (décision), carré (capture) — spec §2.4. Le risque
    /// prend le rond ambre : la frise n'a que trois formes, et une quatrième la
    /// rendrait illisible à 22 px.
    private func dessiner(_ repere: MeetingPlayhead.Marker,
                          at x: CGFloat,
                          ctx: GraphicsContext,
                          size: CGSize) {
        let taille = AudioTimelineGeometry.markerSize
        let centre = CGPoint(x: x, y: size.height / 2)
        let cadre = CGRect(x: centre.x - taille / 2, y: centre.y - taille / 2,
                           width: taille, height: taille)
        switch repere.kind {
        case .note:
            ctx.fill(Path(ellipseIn: cadre), with: .color(One2OneToken.action))
        case .risk:
            ctx.fill(Path(ellipseIn: cadre), with: .color(One2OneToken.warn))
        case .decision:
            var losange = Path()
            losange.move(to: CGPoint(x: centre.x, y: cadre.minY))
            losange.addLine(to: CGPoint(x: cadre.maxX, y: centre.y))
            losange.addLine(to: CGPoint(x: centre.x, y: cadre.maxY))
            losange.addLine(to: CGPoint(x: cadre.minX, y: centre.y))
            losange.closeSubpath()
            ctx.fill(losange, with: .color(One2OneToken.report))
        case .capture:
            ctx.fill(Path(roundedRect: cadre, cornerRadius: 1.5),
                     with: .color(One2OneToken.captureMarker))
        case .board:
            ctx.fill(Path(roundedRect: cadre, cornerRadius: 1.5),
                     with: .color(One2OneToken.workshop))
        }
    }

    // MARK: - Gestes et chargement

    private func deplacer(vers x: CGFloat, largeur: CGFloat) {
        let d = duration
        guard d > 0 else { return }
        if playhead.duration <= 0 { playhead.duration = d }
        playhead.seek(to: AudioTimelineGeometry.t(x: x, duration: d, width: largeur))
    }

    private func chargerOnde(largeur: CGFloat) async {
        guard let url = meeting.wavFileURL, largeur > 0 else {
            peaks = []
            return
        }
        let count = AudioTimelineGeometry.peakCount(width: largeur)
        let resultat = await AudioWaveformCache.shared.peaks(url: url, count: count)
        peaks = resultat
    }
}
