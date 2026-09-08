import SwiftData
import SwiftUI

/// L'écran **6a — Atelier, planche plein cadre** : le mode En séance du type
/// Atelier. Grille `52 | 1fr | 314` (spec §7.2, capture
/// `6a-atelier-planche.png`), barre d'outils 32 px au-dessus.
///
/// Le **dock remplace le rail d'actions** (plan §5, lot 16) : c'est
/// `MeetingSpaceView` qui aiguille, cette vue occupe toute la largeur.
///
/// La pilule de présence de la maquette (`YP CA 2 personnes dessinent`) est
/// **masquée** : l'application est mono-utilisateur (décision D11, et la spec
/// §7.2 le prévoit — « sinon masquée »).
struct WorkshopSpaceView: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Ouvre le dock assistant existant (`⌘K`).
    @Binding var isAssistantOpen: Bool

    @Environment(\.modelContext) private var context

    private var state: WorkshopState { screen.workshop }
    private var playheadT: Double { screen.playhead.t }

    var body: some View {
        VStack(spacing: 0) {
            WorkshopToolbar(meeting: meeting, state: state, playheadT: playheadT)
            // Le bandeau vient **sous** la barre d'outils, dans le flux : en
            // superposition haute, il la recouvrait (constaté en recette le
            // 2026-09-07) et l'utilisateur perdait modes, couleurs et export.
            bandeauErreur
            HStack(spacing: 0) {
                WorkshopToolPalette(meeting: meeting, state: state)
                toile
                WorkshopDock(meeting: meeting,
                             state: state,
                             playheadT: playheadT,
                             onOpenAssistant: { isAssistantOpen = true })
            }
        }
        .background(One2OneToken.bgCanvas)
        .background { raccourcis }
        .task(id: meeting.persistentModelID) {
            await state.open(meeting: meeting, playheadT: playheadT, context: context)
        }
        .onDisappear { state.releaseBridge() }
    }

    // MARK: - Toile

    /// Fond `#fdfcfa` (`surfaceAlt`) et grille de points 18 px : les deux sont
    /// peints **par la page**, pour qu'ils suivent le panoramique et le zoom.
    /// Le fond Swift ne se voit donc qu'avant le premier rendu.
    @ViewBuilder
    private var toile: some View {
        ZStack {
            One2OneToken.surfaceAlt
            if let pont = state.bridge(for: meeting.ensuredStableID) as? WhiteboardWebBridge {
                WhiteboardWebView(bridge: pont)
                    .onAppear { brancher(pont) }
            } else {
                // Cas des tests et des doubles : pas de page à montrer.
                Text("Moteur de planches indisponible")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Branche la remontée de modifications : la page amortit à 400 ms, le
    /// magasin écrit la scène et régénère la vignette au plus toutes les 5 s.
    private func brancher(_ pont: WhiteboardWebBridge) {
        pont.onChange = { changement in
            Task { await state.apply(changement, meeting: meeting, context: context) }
        }
    }

    // MARK: - Raccourcis

    /// `⌘+` / `⌘-` pour le zoom, `⇧⌘0` pour ajuster (spec §7.2). Des boutons de
    /// taille nulle : un `.hidden()` ne recevrait plus le raccourci.
    private var raccourcis: some View {
        VStack(spacing: 0) {
            Button("Zoom avant") {
                Task { await state.zoom(to: state.zoomPercent + WorkshopState.zoomStep,
                                        meeting: meeting) }
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom arrière") {
                Task { await state.zoom(to: state.zoomPercent - WorkshopState.zoomStep,
                                        meeting: meeting) }
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Ajuster la planche") {
                Task { await state.fitToScreen(meeting: meeting) }
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Erreurs

    /// Un bandeau, pas une alerte : un bundle manquant ne doit pas bloquer la
    /// réunion (parade du plan §8).
    @ViewBuilder
    private var bandeauErreur: some View {
        if let message = state.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(One2OneToken.warnInk)
                Text(message)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.warnInk)
                Spacer(minLength: 8)
                Button("Fermer") { state.errorMessage = nil }
                    .buttonStyle(.plain)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(One2OneToken.warnBg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(One2OneToken.warn.opacity(0.3)).frame(height: 1)
            }
        }
    }
}
