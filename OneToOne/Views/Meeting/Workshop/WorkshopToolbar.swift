import AppKit
import UniformTypeIdentifiers
import SwiftData
import SwiftUI

/// La deuxième ligne de l'écran 6a, **32 px** (spec §7.2) : sélecteur de mode
/// segmenté, cinq couleurs, trois épaisseurs, puis à droite
/// `Planche n sur m · dernière modif. il y a Xs` et `Exporter PNG / SVG`.
struct WorkshopToolbar: View {

    static let height: CGFloat = 32

    let meeting: Meeting
    let state: WorkshopState
    /// Timecode courant, pour horodater une planche créée par le changement de
    /// mode.
    let playheadT: Double

    @Environment(\.modelContext) private var context

    private var planches: [Board] { state.boards(of: meeting) }
    private var active: Board? { state.activeBoard(of: meeting) }

    var body: some View {
        HStack(spacing: 12) {
            selecteurDeMode
            separateur
            couleurs
            separateur
            epaisseurs

            Spacer(minLength: 12)

            compteur
            boutonExporter
        }
        .padding(.horizontal, MeetingTopChromeBar.paddingHorizontal)
        .frame(height: Self.height)
        .background(One2OneToken.bgApp)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.cardBorder).frame(height: 1)
        }
    }

    /// Filet vertical entre les groupes de la barre, comme sur la capture.
    private var separateur: some View {
        Rectangle()
            .fill(One2OneToken.cardBorder)
            .frame(width: 1, height: 18)
    }

    // MARK: - Mode

    /// Le sélecteur applique la règle §7.1 par `WorkshopState.requestMode` :
    /// changer de mode crée une planche, sauf si la courante est vide.
    private var selecteurDeMode: some View {
        SegmentedMode(selection: Binding(
            get: { active?.mode ?? .sketch },
            set: { mode in
                Task { await state.requestMode(mode, meeting: meeting, t: playheadT, context: context) }
            }
        ), options: BoardMode.allCases, libelle: \.label)
    }

    // MARK: - Couleurs

    private var couleurs: some View {
        HStack(spacing: 8) {
            ForEach(WorkshopPalette.entries) { entree in
                let actif = entree.hex.caseInsensitiveCompare(state.colorHex) == .orderedSame
                Button {
                    Task { await state.apply(colorHex: entree.hex, meeting: meeting) }
                } label: {
                    Circle()
                        .fill(entree.color)
                        .frame(width: 18, height: 18)
                        // Anneau blanc + contour sur l'active (spec §7.2).
                        .overlay {
                            if actif {
                                Circle().strokeBorder(One2OneToken.surface, lineWidth: 2)
                            }
                        }
                        .overlay {
                            if actif {
                                Circle()
                                    .strokeBorder(One2OneToken.ink1.opacity(0.55), lineWidth: 1)
                                    .padding(-2.5)
                            }
                        }
                        .padding(2.5)
                }
                .buttonStyle(.plain)
                .help(entree.label)
                .accessibilityLabel(entree.label)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Épaisseurs

    private var epaisseurs: some View {
        HStack(spacing: 4) {
            ForEach(WhiteboardStroke.allCases) { epaisseur in
                let actif = epaisseur == state.stroke
                Button {
                    Task { await state.apply(stroke: epaisseur, meeting: meeting) }
                } label: {
                    Text(epaisseur.label)
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(actif ? One2OneToken.ink1 : One2OneToken.ink3)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                                .fill(actif ? One2OneToken.surface : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                                .strokeBorder(actif ? One2OneToken.strongBorder : One2OneToken.hair,
                                              lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Compteur

    /// `Planche 3 sur 4 · dernière modif. il y a 12 s`. Le délai est rafraîchi
    /// par `TimelineView` : sans lui, « il y a 12 s » resterait faux jusqu'au
    /// prochain trait.
    private var compteur: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexte in
            Text(libelle(now: contexte.date))
                .font(.plexSans(10.5))
                .foregroundStyle(One2OneToken.ink4)
                .lineLimit(1)
        }
    }

    private func libelle(now: Date) -> String {
        let index = active?.index ?? 0
        let compteur = BoardOrdering.counterLabel(index: index, total: planches.count)
        guard let active else { return compteur }
        let fraicheur = BoardOrdering.freshnessLabel(updatedAt: active.updatedAt, now: now)
        return "\(compteur) · \(fraicheur)"
    }

    // MARK: - Export

    private var boutonExporter: some View {
        Menu {
            Button("Exporter en PNG…") { Task { await exporter(.png) } }
            Button("Exporter en SVG…") { Task { await exporter(.svg) } }
        } label: {
            Text("Exporter PNG / SVG")
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Exporter la planche courante en PNG ou en SVG")
    }

    private enum Format { case png, svg }

    private func exporter(_ format: Format) async {
        guard let active else { return }
        let nom = WorkshopExport.fileName(board: active,
                                          extension: format == .png ? "png" : "svg")
        switch format {
        case .png:
            guard let data = await state.exportPNG(meeting: meeting) else {
                state.errorMessage = "Export PNG impossible"
                return
            }
            enregistrer(data: data, nom: nom, type: .png)
        case .svg:
            guard let texte = await state.exportSVG(meeting: meeting) else {
                state.errorMessage = "Export SVG impossible"
                return
            }
            enregistrer(data: Data(texte.utf8), nom: nom, type: .svg)
        }
    }

    private func enregistrer(data: Data, nom: String, type: UTType) {
        let panneau = NSSavePanel()
        panneau.nameFieldStringValue = nom
        panneau.allowedContentTypes = [type]
        panneau.canCreateDirectories = true
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            state.errorMessage = "Écriture impossible : \(error.localizedDescription)"
        }
    }
}
