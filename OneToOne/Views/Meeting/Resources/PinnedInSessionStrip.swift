import SwiftUI

/// La bande `ÉPINGLÉ DANS LA SÉANCE` (spec §4.2, capture
/// `3a-tiroir-ressources.png`).
///
/// Des chips horodatées — `04:12 · Comptes_GitLab.png`, `12:08 ·
/// Chiffrage_Marine_v3` — **celle du moment courant en `accent/action`**, et un
/// clic qui déplace la tête de lecture. C'est la réponse au critère n° 3 du
/// chantier 3 : une pièce épinglée est retrouvable par son timecode, et
/// l'endroit où on la retrouve est ici.
///
/// La mention « Les pièces épinglées sont citées dans le rapport » dit ce que
/// l'épinglage engage. Le bloc de rapport lui-même arrive au lot 15 ; d'ici là
/// la phrase reste vraie de la liste `Meeting.pinnedAttachments`, qui est
/// exactement ce que ce bloc lira.
struct PinnedInSessionStrip: View {
    let meeting: Meeting
    let screen: MeetingScreenModel

    /// Tolérance de « moment courant », en secondes. La même que
    /// `MeetingPlayhead.marker(at:tolerance:)` élargie à la seconde : une chip
    /// qui ne s'allume qu'au centième de seconde près ne s'allume jamais.
    static let currentTolerance: Double = 1.5

    /// Les pièces épinglées **et** les captures horodatées, triées par
    /// timecode. Les deux sont « épinglées dans la séance » au sens de la
    /// capture, qui montre `04:12 · Comptes_GitLab.png` à côté d'un document.
    private var epinglees: [ResourceItem] {
        ResourceItem.all(for: meeting)
            .filter { $0.pinnedAtT != nil }
            .sorted { ($0.pinnedAtT ?? 0) < ($1.pinnedAtT ?? 0) }
    }

    var body: some View {
        if !epinglees.isEmpty {
            HStack(spacing: 8) {
                Text("ÉPINGLÉ DANS LA SÉANCE").sectionLabel()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(epinglees) { item in chip(item) }
                    }
                }
                Spacer(minLength: 8)
                Text("Les pièces épinglées sont citées dans le rapport")
                    .font(.plexSans(11))
                    // 11 px : `ink/4` (spec §1.2).
                    .foregroundStyle(One2OneToken.ink4)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(One2OneToken.surfaceAlt)
            .overlay(alignment: .top) {
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
            }
        }
    }

    /// Une chip : `mm:ss · nom`. Celle du moment courant est en
    /// `accent/action`, les autres neutres.
    private func chip(_ item: ResourceItem) -> some View {
        let t = item.pinnedAtT ?? 0
        let courante = Self.isCurrent(t: t, playhead: screen.playhead.t)
        return Button {
            screen.playhead.seek(to: t)
            if item.isPresentable { screen.resources.present(item.id) }
        } label: {
            HStack(spacing: 5) {
                Text(MeetingPlayhead.mmss(t))
                    .font(.plexMono(10))
                Text("·")
                    .font(.plexMono(10))
                    .opacity(0.5)
                Text(AttachmentPinning.displayName(item.name))
                    .font(.plexSans(10.5, .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(courante ? One2OneToken.actionInk : One2OneToken.ink3)
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(courante ? One2OneToken.actionBg : One2OneToken.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(courante ? One2OneToken.action.opacity(0.35)
                                           : One2OneToken.cardBorder,
                                  lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Revenir à \(MeetingPlayhead.mmss(t)) — \(item.name)")
    }

    /// Vrai si `t` est le moment courant. Fonction pure et `static` : la règle
    /// d'allumage se teste sans monter la vue.
    static func isCurrent(t: Double, playhead: Double) -> Bool {
        abs(t - playhead) <= currentTolerance
    }
}
