import SwiftUI

/// La frise audio de 22 px en pied de la carte notes ↔ transcription
/// (spec §2.4, capture `1a-cockpit.png` : `00:00` … `23:24`, onde, tête bleue,
/// marqueur rouge de décision, marqueur bleu de note).
///
/// « Onde échantillonnée, tête de lecture 2 px `accent/action`, marqueurs ronds
/// (note), carrés (capture), losanges (décision). Clic = déplacement, glisser =
/// balayage. »
///
/// Sans fichier audio, la frise **reste affichée** : une piste plate et les
/// marqueurs des notes déjà prises. C'est l'axe temps de la réunion, pas
/// seulement celui d'un enregistrement. L'invite « Aucun audio » n'apparaît
/// que si la frise est vide de marqueurs, faute de quoi elle se superposerait
/// à eux.
struct AudioTimelineStrip: View {

    let meeting: Meeting
    let screen: MeetingScreenModel

    /// Bande d'étiquettes au-dessus des marqueurs (spec §2.7, capture
    /// `1c-poste-de-pilotage.png` : `04:12`, `DÉCISION`, `15:20`).
    ///
    /// Défaut `false` : la frise de 22 px du mode En séance (lot 2) ne change
    /// pas d'un pixel. C'est le poste de pilotage qui l'allume, sa frise étant
    /// pleine largeur et en pied d'écran.
    var labelled: Bool = false

    @State private var peaks: [Float] = []

    /// Hauteur totale de la frise, bande d'étiquettes comprise.
    static func hauteur(labelled: Bool) -> CGFloat {
        AudioTimelineGeometry.height + 12
            + (labelled ? TimelineLabelLayout.hauteur : 0)
    }

    /// Les marqueurs à étiqueter, dans l'ordre du temps.
    ///
    /// Une décision porte le mot `DÉCISION` (c'est ce qu'on cherche en
    /// relisant), les notes et les risques leur timecode. Les captures et les
    /// planches sont **écartées** : leur carré se lit déjà, et une étiquette
    /// par vignette saturerait la frise.
    static func candidats(_ markers: [MeetingPlayhead.Marker]) -> [TimelineLabelLayout.Candidat] {
        markers
            .sorted { $0.t < $1.t }
            .compactMap { repere in
                switch repere.kind {
                case .decision:
                    return TimelineLabelLayout.Candidat(t: repere.t,
                                                        texte: "DÉCISION",
                                                        estDecision: true)
                case .note, .risk:
                    return TimelineLabelLayout.Candidat(t: repere.t,
                                                        texte: TimecodeLabel.format(repere.t),
                                                        estDecision: false)
                case .capture, .board:
                    return nil
                }
            }
    }

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
                .font(.plexMono(10, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.ink4)
            piste
            Text(TimecodeLabel.format(duration))
                .font(.plexMono(10, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.ink4)
            // Spec §5.2 (lot 7) : la légende du carré, seulement quand la
            // séance a des captures — expliquer un symbole absent est du bruit.
            if let legende = MeetingTimelineMarkers.captureLegend(playhead.markers) {
                Text(legende)
                    .font(.plexMono(9.5, .medium))
                    .foregroundStyle(One2OneToken.ink4)
                    .fixedSize()
                    .help("Chaque carré est une capture d'écran de la séance")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: Self.hauteur(labelled: labelled))
        .overlay(alignment: .top) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    private var piste: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            VStack(spacing: 0) {
                if labelled {
                    etiquettes(largeur: largeur)
                }
                pisteSeule(largeur: largeur)
            }
        }
        .frame(height: labelled
               ? AudioTimelineGeometry.height + TimelineLabelLayout.hauteur
               : AudioTimelineGeometry.height)
    }

    /// La bande d'étiquettes du mode `labelled`, alignée sur les marqueurs.
    private func etiquettes(largeur: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(TimelineLabelLayout.placer(Self.candidats(playhead.markers),
                                                duration: duration,
                                                width: largeur)) { etiquette in
                Text(etiquette.texte)
                    .font(.plexMono(9.5, .medium))
                    .foregroundStyle(etiquette.estDecision
                                     ? One2OneToken.reportInk
                                     : One2OneToken.actionInk)
                    .frame(width: etiquette.largeur)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(etiquette.estDecision
                                  ? One2OneToken.reportBg
                                  : One2OneToken.actionBg)
                    )
                    .offset(x: etiquette.centre - etiquette.largeur / 2)
            }
        }
        .frame(width: largeur, height: TimelineLabelLayout.hauteur, alignment: .leading)
    }

    private func pisteSeule(largeur: CGFloat) -> some View {
        Group {
            ZStack(alignment: .leading) {
                Canvas { ctx, size in dessiner(ctx: ctx, size: size) }
                // L'invite ne s'affiche que si la frise est **vraiment** vide.
                // Dès qu'un marqueur est posé, l'axe se lit tout seul et le
                // texte se superposait aux ronds et aux losanges — illisible,
                // relevé par la recette visuelle de la vague 1–4 sur les cinq
                // écrans. `ink/4` et non `ink/muted` : sous 12 px la spec §1.2
                // exige 4,5:1.
                if !hasAudio && playhead.markers.isEmpty {
                    Text("Aucun audio")
                        .font(.plexSans(10))
                        .foregroundStyle(One2OneToken.ink4)
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
            // Spec §5.2 (lot 7) : carré de 12 px, `accent/action` pour la
            // **dernière** capture — celle qu'on cherche en priorité quand on
            // revient sur la frise.
            let cote = MeetingTimelineMarkers.captureMarkerSize
            let carre = CGRect(x: centre.x - cote / 2, y: centre.y - cote / 2,
                               width: cote, height: cote)
            let estDerniere = repere.t == MeetingTimelineMarkers.lastCaptureT(playhead.markers)
            ctx.fill(Path(roundedRect: carre, cornerRadius: 2),
                     with: .color(estDerniere ? One2OneToken.action : One2OneToken.captureMarker))
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
