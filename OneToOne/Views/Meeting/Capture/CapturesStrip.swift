import SwiftData
import SwiftUI

/// La bande de captures, en pied de la colonne principale (spec §5.3, capture
/// `4a-capture-selecteur.png`) : en-tête `Captures de la séance · 3 · source
/// Teams`, vignettes 132 × 76 horodatées, tuile de capture manuelle, et la
/// colonne d'état de la capture sélectionnée.
///
/// Reprise de `TeamsCapture/Cockpit/CaptureRail.swift` pour la mise en page ;
/// les décisions (ordre, légendes, invites, lignes d'état) sont dans
/// `CaptureStripModel`, testé à part.
///
/// **Jamais vide sans invite** : la bande dit ce qu'elle attend, et cette
/// attente n'est pas la même selon le type de réunion ni selon que la
/// détection tourne.
struct CapturesStrip: View {

    let coordinator: CaptureSessionCoordinator
    @ObservedObject var service: ScreenCaptureService
    @Environment(\.modelContext) private var context

    private var state: CaptureState { coordinator.screen.capture }
    private var captures: [SlideCapture] { coordinator.captures }

    /// Géométrie de la capture 4a.
    private static let tileWidth: CGFloat = 132
    private static let tileHeight: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            entete
            if captures.isEmpty {
                bandeVide
            } else {
                HStack(alignment: .top, spacing: 12) {
                    vignettes
                    colonneDEtat
                        .frame(width: 210, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.vertical, One2OneToken.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(One2OneToken.surface))
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1))
        .background {
            // Le raccourci vit sur la vue de la bande, jamais sur la tuile :
            // celle-ci est une cellule de grille défilante, non instanciée dès
            // que la bande défile — le raccourci disparaîtrait précisément dans
            // les séances longues, celles où il sert le plus (leçon de
            // `CaptureRail.swift`). `.opacity(0)` et non `.hidden()`, qui
            // rendrait le bouton non interactif.
            Button("") { Task { await coordinator.captureNow() } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .opacity(0)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 8) {
            Text("Captures de la séance")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Pill(CaptureState.stripSubtitle(count: captures.count,
                                            source: service.configuration?.source ?? state.selected?.source),
                 ton: .ok)
            Spacer(minLength: 0)
            if let mention = mentionDuDeclencheur {
                Text(mention)
                    .font(.plexMono(9.5, .medium))
                    .foregroundStyle(One2OneToken.ink4)
            }
        }
    }

    /// La mention du déclencheur automatique de l'en-tête (spec §5.3).
    /// Absente quand rien n'écrit tout seul : annoncer un automatisme qui ne
    /// tourne pas ferait attendre des captures qui ne viendront pas.
    private var mentionDuDeclencheur: String? {
        guard service.hasOpenSession, let configuration = service.configuration else { return nil }
        var parties: [String] = []
        if configuration.detectsAutomatically { parties.append("auto") }
        if let intervalle = configuration.periodicCapture {
            parties.append("+ \(Int(intervalle.components.seconds) / 60) min")
        }
        return parties.isEmpty ? nil : parties.joined(separator: " ")
    }

    // MARK: - Vignettes

    private var vignettes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(captures, id: \.persistentModelID) { capture in
                    vignette(capture)
                }
                tuileManuelle
            }
            .padding(.bottom, 2)
        }
    }

    private func vignette(_ capture: SlideCapture) -> some View {
        let choisie = state.selectedCaptureID == capture.id
        return Button {
            state.selectedCaptureID = capture.id
            if let t = capture.t { coordinator.screen.playhead.seek(to: t) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                image(for: capture)
                    .frame(width: Self.tileWidth, height: Self.tileHeight)
                    .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview))
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                            .strokeBorder(choisie ? One2OneToken.action : One2OneToken.cardBorder,
                                          lineWidth: choisie ? 2 : 1))
                Text(CaptureStripModel.legend(for: capture,
                                              interval: service.configuration?.periodicCapture))
                    .font(.plexMono(10))
                    .foregroundStyle(choisie ? One2OneToken.actionInk : One2OneToken.ink4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(CaptureStripModel.title(for: capture))
        .contextMenu { menu(for: capture) }
    }

    @ViewBuilder
    private func image(for capture: SlideCapture) -> some View {
        if let vignette = CaptureThumbnailCache.shared.thumbnail(forPath: capture.imagePath) {
            Image(decorative: vignette, scale: 2, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Fichier disparu : un cadre muet qui le dit, plutôt qu'une
            // vignette vide qu'on prendrait pour une capture noire.
            ZStack {
                RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                    .fill(One2OneToken.surfaceAlt)
                Text("Image introuvable")
                    .font(.plexSans(10))
                    .foregroundStyle(One2OneToken.ink4)
            }
        }
    }

    /// Dernière tuile de la bande : capturer à la main, sans quitter l'écran
    /// (spec §5.3, capture 4a : `Capturer ⌘⇧S` en pointillés).
    private var tuileManuelle: some View {
        Button {
            Task { await coordinator.captureNow() }
        } label: {
            VStack(spacing: 4) {
                Text("Capturer")
                    .font(.plexSans(11.5, .medium))
                    .foregroundStyle(One2OneToken.actionInk)
                Text("⌘⇧S")
                    .font(.plexMono(10))
                    .foregroundStyle(One2OneToken.ink4)
            }
            .frame(width: Self.tileWidth, height: Self.tileHeight)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                    .fill(One2OneToken.actionBg2))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                    .strokeBorder(One2OneToken.action,
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Capturer ce qui est à l'écran maintenant (⌘⇧S)")
    }

    // MARK: - Colonne d'état

    private var colonneDEtat: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(CaptureStripModel.statusLines(for: selection)) { ligne in
                ligneDEtat(ligne)
            }
            if let capture = selection, let insertion = actionsDeSelection(capture) {
                insertion
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// La capture dont la colonne parle : celle qu'on a cliquée, sinon la
    /// dernière — la colonne d'état ne doit jamais être vide quand la bande a
    /// des vignettes.
    private var selection: SlideCapture? {
        if let id = state.selectedCaptureID, let trouvee = captures.first(where: { $0.id == id }) {
            return trouvee
        }
        return captures.last
    }

    @ViewBuilder
    private func ligneDEtat(_ ligne: CaptureStripModel.StatusLine) -> some View {
        switch ligne.mark {
        case .done:
            HStack(spacing: 6) {
                Text("✓").font(.plexSans(11, .semibold)).foregroundStyle(One2OneToken.okDeep)
                Text(ligne.label).font(.plexSans(11.5)).foregroundStyle(One2OneToken.ink2)
            }
        case .missing:
            HStack(spacing: 6) {
                Text("–").font(.plexSans(11, .semibold)).foregroundStyle(One2OneToken.ink4)
                Text(ligne.label).font(.plexSans(11.5)).foregroundStyle(One2OneToken.ink4)
            }
        case .toggle:
            Button {
                basculerRapport()
            } label: {
                HStack(spacing: 6) {
                    Text("○").font(.plexSans(11, .semibold)).foregroundStyle(One2OneToken.ink4)
                    Text(ligne.label).font(.plexSans(11.5)).foregroundStyle(One2OneToken.ink2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Joindre cette capture au rapport envoyé")
        }
    }

    /// `＋ Note` : insère la capture dans la colonne de notes au timecode où
    /// elle a été prise (spec §5.3). Absent sans timecode : une carte de note
    /// sans instant ne serait rattachée à rien.
    @ViewBuilder
    private func actionsDeSelection(_ capture: SlideCapture) -> AnyView? {
        AnyView(
            HStack(spacing: 8) {
                Button("＋ Note") {
                    CaptureNoteInsertion.insert(capture, in: coordinator.meeting, context: context)
                    coordinator.refreshMarkers()
                }
                .buttonStyle(.plain)
                .font(.plexSans(11.5, .medium))
                .foregroundStyle(One2OneToken.actionInk)
                .help("Insérer cette capture dans les notes, au timecode de la capture")

                Button("＋ Action") {
                    coordinator.screen.requestAction(from: CaptureNoteInsertion.actionDraft(for: capture))
                }
                .buttonStyle(.plain)
                .font(.plexSans(11.5, .medium))
                .foregroundStyle(One2OneToken.actionInk)
                .help("Créer une action depuis cette capture")
            }
            .padding(.top, 2)
        )
    }

    private func basculerRapport() {
        guard let capture = selection else { return }
        capture.includeInReport.toggle()
        try? context.save()
    }

    @ViewBuilder
    private func menu(for capture: SlideCapture) -> some View {
        Button("Insérer dans les notes") {
            CaptureNoteInsertion.insert(capture, in: coordinator.meeting, context: context)
            coordinator.refreshMarkers()
        }
        Button(capture.includeInReport ? "Ne pas joindre au rapport" : "Joindre au rapport") {
            capture.includeInReport.toggle()
            try? context.save()
        }
        Divider()
        Button("Supprimer la capture", role: .destructive) {
            CaptureThumbnailCache.shared.forget(path: capture.imagePath)
            service.deleteSlide(capture)
            if state.selectedCaptureID == capture.id { state.selectedCaptureID = nil }
            coordinator.refreshMarkers()
        }
    }

    // MARK: - Bande vide

    private var bandeVide: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(CaptureStripModel.emptyInvite(
                    kind: coordinator.meeting.kind,
                    detectsAutomatically: service.configuration?.detectsAutomatically
                        ?? state.detectsAutomatically,
                    hasSource: service.hasOpenSession || state.selected != nil))
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                if !service.hasOpenSession {
                    Button("Choisir la source…") { state.showPopover = true }
                        .buttonStyle(.plain)
                        .font(.plexSans(11.5, .medium))
                        .foregroundStyle(One2OneToken.actionInk)
                }
            }
            Spacer(minLength: 0)
            tuileManuelle
        }
    }
}
