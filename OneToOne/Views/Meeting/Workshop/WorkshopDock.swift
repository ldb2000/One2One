import AppKit
import SwiftData
import SwiftUI

/// Le dock droit de l'écran 6a : **314 px** (spec §7.2), trois onglets
/// `Planches n / Captures n / Pièces n`, la liste des planches, `＋ Planche` et
/// `Dupliquer`, et la barre d'assistant en pied.
///
/// Ce dock **remplace le rail d'actions** dans le type Atelier (plan §5,
/// lot 16) : la séance produit des planches, pas un tableau d'actions.
struct WorkshopDock: View {

    static let width: CGFloat = 314

    let meeting: Meeting
    let state: WorkshopState
    let playheadT: Double
    /// Ouvre le dock assistant existant (`⌘K`).
    let onOpenAssistant: () -> Void

    @Environment(\.modelContext) private var context

    private var planches: [Board] { state.boards(of: meeting) }
    private var active: Board? { state.activeBoard(of: meeting) }

    var body: some View {
        VStack(spacing: 0) {
            onglets
            Divider().overlay(One2OneToken.hair)

            switch state.dockTab {
            case .boards:
                listeDesPlanches
                boutons
            case .captures, .attachments:
                invite
            }

            Spacer(minLength: 0)
            Divider().overlay(One2OneToken.hair)
            piedAssistant
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(One2OneToken.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(One2OneToken.hair).frame(width: 1)
        }
    }

    // MARK: - Onglets

    private var onglets: some View {
        HStack(spacing: 14) {
            ForEach(WorkshopState.DockTab.allCases) { onglet in
                let actif = onglet == state.dockTab
                Button {
                    state.dockTab = onglet
                } label: {
                    HStack(spacing: 5) {
                        Text(onglet.label)
                            .font(.plexSans(12, actif ? .semibold : .regular))
                            .foregroundStyle(actif ? One2OneToken.ink1 : One2OneToken.ink3)
                        Text("\(compte(onglet))")
                            .font(.plexSans(11, .semibold))
                            .foregroundStyle(actif ? One2OneToken.workshop : One2OneToken.ink4)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(actif ? One2OneToken.workshopBg : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    /// Les compteurs de la capture. Captures et pièces arrivent au lot 17 : le
    /// compteur dit la vérité (0) plutôt qu'un chiffre inventé.
    private func compte(_ onglet: WorkshopState.DockTab) -> Int {
        switch onglet {
        case .boards:      return planches.count
        case .captures:    return 0
        case .attachments: return meeting.attachments.count
        }
    }

    // MARK: - Liste des planches

    private var listeDesPlanches: some View {
        List {
            ForEach(planches, id: \.persistentModelID) { planche in
                ligne(planche)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { offsets, destination in
                state.move(from: offsets, to: destination, meeting: meeting, context: context)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Borne la hauteur : la parade du plan §2.4 point 4 contre
        // `_NSDetectedLayoutRecursion` interdit un `ScrollView` non borné.
        .frame(maxHeight: 420)
    }

    private func ligne(_ planche: Board) -> some View {
        let actif = planche.stableID == active?.stableID
        return Button {
            Task { await state.select(planche, meeting: meeting, context: context) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                vignette(planche)
                VStack(alignment: .leading, spacing: 3) {
                    Chip(planche.mode.label.uppercased(), ton: .neutre)
                    TextField("", text: Binding(
                        get: { planche.title },
                        set: { planche.title = $0; try? context.save() }
                    ))
                    .textFieldStyle(.plain)
                    .font(.plexSans(12, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
                    Text(sousTitre(planche))
                        .font(.plexMono(10))
                        .foregroundStyle(One2OneToken.ink4)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(actif ? One2OneToken.workshopBg : One2OneToken.surface))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(actif ? One2OneToken.workshop : One2OneToken.cardBorder,
                                  lineWidth: actif ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }

    /// `08:15 · Yann`, ou `34:20 · en cours` pour la planche active de la
    /// séance — comme sur la capture.
    private func sousTitre(_ planche: Board) -> String {
        let timecode = MeetingPlayhead.mmss(planche.t)
        let auteur = planche.authorNames.isEmpty ? "—" : planche.authorNames
        return "\(timecode) · \(auteur)"
    }

    /// Vignette 60 × 40 (spec §7.2). Une planche sans vignette montre son mode
    /// plutôt qu'un cadre vide.
    private func vignette(_ planche: Board) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .fill(One2OneToken.surfaceAlt)
            if let data = state.store.thumbnailData(board: planche, meeting: meeting),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                                style: .continuous))
            } else {
                Text(planche.mode.label.uppercased())
                    .font(.plexMono(7.5, .semibold))
                    .foregroundStyle(One2OneToken.ink4)
            }
        }
        .frame(width: 60, height: 40)
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(One2OneToken.hair, lineWidth: 1))
    }

    // MARK: - Boutons

    private var boutons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.addBoard(meeting: meeting, t: playheadT, context: context) }
            } label: {
                Text("＋ Planche")
                    .font(.plexSans(11.5, .semibold))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.workshop))
            }
            .buttonStyle(.plain)

            Button {
                Task { await state.duplicateActive(meeting: meeting, t: playheadT, context: context) }
            } label: {
                Text("Dupliquer")
                    .font(.plexSans(11.5, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .strokeBorder(One2OneToken.strongBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(active == nil)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Invites

    private var invite: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.dockTab.label.uppercased()).sectionLabel()
            Text(state.dockTab.invite ?? "")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Pied assistant

    private var piedAssistant: some View {
        Button(action: onOpenAssistant) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(One2OneToken.workshop)
                Text("L'assistant peut décrire les planches dans le rapport.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("⌘K")
                    .font(.plexMono(9.5, .medium))
                    .foregroundStyle(One2OneToken.ink4)
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .help("Ouvrir l'assistant")
    }
}
