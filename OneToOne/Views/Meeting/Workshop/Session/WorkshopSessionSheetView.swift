import AppKit
import SwiftData
import SwiftUI

/// L'écran **6b — Atelier, planche de séance** : le mode Relire du type
/// Atelier (spec §7.3, capture `6b-atelier-planche-de-seance.png`).
///
/// « La sortie de l'atelier : toutes les planches, captures et pièces sur une
/// même page, dans l'ordre du temps, prêtes à partir dans le rapport. » C'est
/// la réponse à « qu'est-ce qu'on a produit ce matin ? », et c'est pour cela
/// que ce mode **remplace** le poste de pilotage du lot 5 : un atelier n'a pas
/// de tableau d'actions dense à relire, il a une production à passer en revue.
///
/// La vue ne calcule rien : la frise vient de `WorkshopTimelineModel`, la
/// légende de `BoardCaptionBuilder`, l'export de `WorkshopExport.exportAll` et
/// la case de `WorkshopReportAttachment`. Tous testés sans écran (plan §8).
///
/// Pas d'`AvatarStack` : la capture n'en porte pas, et le compte des
/// participants est déjà dans la ligne de métadonnées.
struct WorkshopSessionSheetView: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings

    @Environment(\.modelContext) private var context

    /// Largeur maximale de la carte. La capture mesure ~920 px : au-delà, les
    /// aperçus s'étirent et la colonne de timecodes s'éloigne du contenu
    /// qu'elle horodate.
    static let cardMaxWidth: CGFloat = 920

    /// Colonne de timecodes (spec §7.3 : « colonne timecode 40 px »).
    static let timecodeColumnWidth: CGFloat = 40

    /// Hauteur de l'aperçu (spec §7.3 : « aperçu 76–96 px de haut »).
    static let previewHeight: CGFloat = 92

    private var state: WorkshopState { screen.workshop }

    /// Un message d'échec de l'export, effacé au clic suivant.
    @State private var erreur: String?

    private var lignes: [WorkshopTimelineItem] {
        WorkshopTimelineModel.rows(for: meeting)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                enTete
                corps
            }
            .frame(maxWidth: Self.cardMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(One2OneToken.surfaceAlt))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(One2OneToken.cardBorder, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .background(One2OneToken.bgCanvas)
        // Une planche a toujours une légende, dès l'ouverture et sans réseau :
        // `fillMissingCaptions` est un calcul, pas une requête.
        .onAppear { state.fillMissingCaptions(meeting: meeting, context: context) }
    }

    // MARK: - En-tête

    private var enTete: some View {
        HStack(alignment: .top, spacing: 12) {
            Chip("ATELIER", ton: .workshop)
                .fixedSize()
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title)
                    .font(.plexSans(15, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(2)
                MonoMeta(resumeDeSeance, emphase: true)
            }
            Spacer(minLength: 8)
            boutonToutExporter
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(One2OneToken.workshopBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(One2OneToken.cardBorder)
                .frame(height: MeetingSpaceLayout.hairlineWidth)
        }
    }

    /// `4 sept. · 1 h 02 · 4 participants · 9 éléments produits`.
    private var resumeDeSeance: String {
        WorkshopTimelineModel.headerSummary(
            date: meeting.date,
            durationSeconds: meeting.meetingDurationSeconds > 0
                ? meeting.meetingDurationSeconds
                : meeting.durationSeconds,
            participantCount: meeting.participants.count,
            producedCount: lignes.count)
    }

    private var boutonToutExporter: some View {
        Button { exporterTout() } label: {
            Text("Tout exporter")
                .font(.plexSans(11.5, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy || lignes.isEmpty)
        .help("Un dossier avec une image et une scène .excalidraw.json par planche, plus un index")
    }

    // MARK: - Corps

    @ViewBuilder
    private var corps: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let erreur {
                Text(erreur)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.warnInk)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                            .fill(One2OneToken.warnBg))
            }
            if lignes.isEmpty {
                invite
            } else {
                ForEach(lignes) { ligne in
                    frise(ligne)
                }
            }
            encartDeCloture
        }
        .padding(16)
    }

    /// Aucun élément produit : une invite, jamais une zone vide (programme
    /// §2.1).
    private var invite: some View {
        RefonteCard {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(One2OneToken.workshop)
                Text(WorkshopTimelineModel.emptyInvite)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Une ligne de la frise

    private func frise(_ ligne: WorkshopTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(MeetingPlayhead.mmss(ligne.t))
                .font(.plexMono(10, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.ink4)
                .frame(width: Self.timecodeColumnWidth, alignment: .leading)
                .padding(.top, 8)
            carte(ligne)
        }
    }

    private func carte(_ ligne: WorkshopTimelineItem) -> some View {
        VStack(spacing: 0) {
            apercu(ligne)
            Rectangle()
                .fill(One2OneToken.cardBorder)
                .frame(height: MeetingSpaceLayout.hairlineWidth)
            pied(ligne)
        }
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface))
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1))
    }

    /// L'aperçu. Une planche sans vignette, une capture dont le fichier a
    /// disparu : la pastille de type remplace le cadre vide plutôt que de
    /// laisser un trou dans la frise.
    @ViewBuilder
    private func apercu(_ ligne: WorkshopTimelineItem) -> some View {
        ZStack {
            One2OneToken.surfaceAlt
            if let image = imageDApercu(ligne) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text(ligne.typeLabel.uppercased())
                    .font(.plexMono(9.5, .semibold))
                    .tracking(9.5 * 0.07)
                    .foregroundStyle(One2OneToken.ink4)
            }
        }
        .frame(height: Self.previewHeight)
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: One2OneToken.radiusCard,
                                   bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: One2OneToken.radiusCard,
                                   style: .continuous))
    }

    private func imageDApercu(_ ligne: WorkshopTimelineItem) -> NSImage? {
        guard !ligne.previewPath.isEmpty else { return nil }
        let url = ligne.previewIsRelative
            ? state.store.url(meetingStableID: meeting.ensuredStableID,
                              relativePath: ligne.previewPath)
            : URL(fileURLWithPath: ligne.previewPath)
        return NSImage(contentsOf: url)
    }

    /// `Croquis — périmètre actuel` à gauche, `Yann` à droite, et la légende
    /// dessous quand la planche en a une.
    private func pied(_ ligne: WorkshopTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ligne.footer)
                    .font(.plexSans(12, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Spacer(minLength: 4)
                MonoMeta(ligne.trailing)
                    .fixedSize()
            }
            if !ligne.caption.isEmpty {
                Text(ligne.caption)
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Encart de clôture

    /// Le rappel du stockage local et les deux boutons (spec §7.3).
    ///
    /// `.drawio` de la maquette **n'y figure pas** : hors v1 (décision D6 du
    /// programme). Proposer un format qui n'existe pas serait une promesse.
    private var encartDeCloture: some View {
        RefonteCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tout est stocké dans le fichier de la réunion — aucun service externe.")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Export PNG, SVG ou .excalidraw si besoin.")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                boutonDecrire
                boutonJoindre
            }
        }
    }

    /// `Décrire les planches` — le geste que promet la barre d'assistant du
    /// dock de 6a (spec §7.2). Absent de la maquette 6b : sans lui, le
    /// raffinement par l'assistant n'aurait aucun point d'entrée, et le poser
    /// sur `Joindre au rapport` ferait partir une requête réseau depuis une
    /// action que la spec veut locale.
    private var boutonDecrire: some View {
        Button {
            Task {
                await state.describeBoards(meeting: meeting, settings: settings, context: context)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 10))
                Text("Décrire les planches").font(.plexSans(11.5, .medium))
            }
            .foregroundStyle(One2OneToken.ink2)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(One2OneToken.surface))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .strokeBorder(One2OneToken.strongBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy
                  || meeting.boards.isEmpty
                  || !BoardCaptionBuilder.isEndpointConfigured(settings))
        .help(BoardCaptionBuilder.isEndpointConfigured(settings)
              ? "L'assistant réécrit la légende de chaque planche"
              : "Aucun modèle configuré — les légendes restent celles calculées depuis la planche")
    }

    /// `Joindre au rapport`, primaire teal — puis `Joint au rapport ✓`.
    private var boutonJoindre: some View {
        let joint = WorkshopReportAttachment.isFullyAttached(meeting: meeting)
        return Button {
            if WorkshopReportAttachment.attachAll(meeting: meeting) > 0 {
                try? context.save()
            }
        } label: {
            Text(WorkshopReportAttachment.buttonLabel(meeting: meeting))
                .font(.plexSans(11.5, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.workshop.opacity(joint ? 0.55 : 1)))
        }
        .buttonStyle(.plain)
        .disabled(joint || lignes.isEmpty)
        .help(joint
              ? "Les planches et les captures de cette séance partiront dans le rapport"
              : "Coche les planches et les captures de cette séance")
    }

    // MARK: - Export

    /// `Tout exporter` : un dossier choisi par l'utilisateur.
    ///
    /// La vignette de la planche affichée est **forcée** avant l'export : elle
    /// n'est régénérée qu'au plus toutes les 5 s (spec §7.4), et exporter une
    /// image d'il y a quatre secondes de dessin serait un piège.
    private func exporterTout() {
        erreur = nil
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.canCreateDirectories = true
        panneau.prompt = "Exporter ici"
        panneau.message = "Choisissez où écrire le dossier de la séance."
        guard panneau.runModal() == .OK, let destination = panneau.url else { return }

        Task {
            state.isBusy = true
            defer { state.isBusy = false }
            if let active = state.activeBoard(of: meeting) {
                await state.regenerateThumbnail(for: active, meeting: meeting, force: true)
            }
            state.fillMissingCaptions(meeting: meeting, context: context)
            do {
                let bilan = try WorkshopExport.exportAll(meeting: meeting,
                                                         store: state.store,
                                                         into: destination)
                NSWorkspace.shared.activateFileViewerSelecting([bilan.indexPath])
            } catch {
                erreur = "Export impossible : \(error.localizedDescription)"
            }
        }
    }
}
