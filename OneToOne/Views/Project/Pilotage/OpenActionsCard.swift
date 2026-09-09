import SwiftUI

/// La carte « ACTIONS EN COURS » de l'onglet Pilotage (capture
/// `1d-ecran-projet-pilotage.png`) : au plus quatre actions ouvertes, les
/// retards d'abord, et « Tout voir » vers l'onglet Actions.
///
/// Cocher une case **solde l'action tout de suite** : c'est le geste que la
/// carte rend possible, et le seul. Tout le reste — réaffecter, redater,
/// commenter — est le travail de l'onglet Actions.
struct OpenActionsCard: View {

    // MARK: - Libellés et mesures du handoff §1d

    static let titre = "ACTIONS EN COURS"
    static let lien = "Tout voir"
    static let vide = "Aucune action ouverte sur ce projet."

    static let cote: CGFloat = 14
    static let epaisseurCase: CGFloat = 1.5
    static let tailleTitre: CGFloat = 13
    static let tailleSousLigne: CGFloat = 11.5
    static let tailleEcheance: CGFloat = 11

    let actions: [ProjectPilotageState.ActionRow]
    let onToutVoir: () -> Void
    let onCocher: (ProjectPilotageState.ActionRow) -> Void

    var body: some View {
        PilotageCard(marges: nil) {
            PilotageCardHeader(titre: Self.titre, lien: Self.lien, action: onToutVoir)
            if actions.isEmpty {
                Text(Self.vide)
                    .font(.plexSans(Self.tailleSousLigne))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .padding(.horizontal, PilotageMetrics.margeH)
                    .padding(.vertical, 11)
            } else {
                ForEach(Array(actions.enumerated()), id: \.element.id) { rang, ligne in
                    row(ligne)
                        .pilotageRowSeparator(rang < actions.count - 1)
                }
            }
        }
    }

    private func row(_ ligne: ProjectPilotageState.ActionRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            case_(ligne)
            VStack(alignment: .leading, spacing: 1) {
                Text(ligne.title)
                    .font(.plexSans(Self.tailleTitre))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Text(ligne.sousLigne)
                    .font(.plexSans(Self.tailleSousLigne))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ligne.echeanceLabel)
                .font(.plexMono(Self.tailleEcheance, .medium))
                .foregroundStyle(Self.teinteDEcheance(ligne.echeance))
                .fixedSize()
        }
        .padding(.horizontal, PilotageMetrics.margeH)
        .padding(.vertical, 9)
    }

    /// La case à cocher : bordée de `report` quand l'action est en retard,
    /// du tireté neutre sinon (handoff : « bord `report` si en retard, sinon
    /// `rgba(0,0,0,.24)` » — c'est `dashedBorder`, le jeton le plus proche).
    private func case_(_ ligne: ProjectPilotageState.ActionRow) -> some View {
        Button { onCocher(ligne) } label: {
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(ligne.enRetard ? One2OneToken.report : One2OneToken.dashedBorder,
                              lineWidth: Self.epaisseurCase)
                .frame(width: Self.cote, height: Self.cote)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Marquer « \(ligne.title) » comme faite")
    }

    /// Rouge pour un retard, encre lisible pour une date, encre effacée pour
    /// une action sans échéance.
    static func teinteDEcheance(_ echeance: ProjectPilotageState.ActionRow.Echeance) -> Color {
        switch echeance {
        case .retard: return One2OneToken.reportInk
        case .date:   return One2OneToken.ink3
        case .aucune: return One2OneToken.inkMuted
        }
    }
}
