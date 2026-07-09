import SwiftUI

/// Barre d'onglets de la réunion avec soulignement animé (`matchedGeometryEffect`).
/// Les cases disponibles sont définies par ``MeetingView/MeetingSection``.
struct MeetingTabsUnderline: View {
    @Binding var selection: MeetingView.MeetingSection
    /// Nombre de pièces jointes, affiché en badge sur l'onglet Documents quand > 0.
    let attachmentsCount: Int
    /// Vrai si un rapport existe, affiche une coche sur l'onglet Rapport.
    let hasReport: Bool
    /// Vrai si le réglage de transcription live est actif ; contrôle
    /// l'affichage de l'onglet « Direct » (sinon onglet vide inutile).
    let showLiveTab: Bool
    let date: Date
    /// Bascule le mode édition de la grille ; affiché seulement sur Vue d'ensemble.
    @Binding var isEditingLayout: Bool

    @Namespace private var underlineNS

    var body: some View {
        HStack(spacing: 28) {
            ForEach(MeetingView.MeetingSection.allCases.filter { $0 != .liveTranscript || showLiveTab }) { section in
                tab(section)
            }
            Spacer()
            Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                .font(.caption).foregroundColor(.secondary)
            if selection == .overview {
                Button { isEditingLayout.toggle() } label: {
                    Label("Personnaliser", systemImage: "square.grid.2x2")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MeetingTheme.hairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tab(_ section: MeetingView.MeetingSection) -> some View {
        let isActive = selection == section
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = section }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(section.rawValue)
                        .font(isActive ? .body.weight(.semibold) : .body)
                        .foregroundColor(isActive ? .primary : .secondary)
                    badge(for: section)
                }
                if isActive {
                    Rectangle()
                        .fill(MeetingTheme.accentOrange)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underlineNS)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    /// Badge contextuel de l'onglet : compteur de pièces jointes (`attachmentsCount`)
    /// sur Documents, coche sur Rapport si `hasReport`, rien sinon.
    @ViewBuilder
    private func badge(for section: MeetingView.MeetingSection) -> some View {
        switch section {
        case .documents where attachmentsCount > 0:
            Text("\(attachmentsCount)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary))
        case .report where hasReport:
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundColor(MeetingTheme.accentOrange)
        default:
            EmptyView()
        }
    }
}
