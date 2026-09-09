import SwiftUI

/// La carte « DERNIÈRES RÉUNIONS » de l'onglet Pilotage (capture
/// `1d-ecran-projet-pilotage.png`) : trois réunions, leur date en mono sur
/// 44 pt, leur badge de type, leur titre et leur résumé de décision.
///
/// Cliquer une ligne ouvre la réunion, par le jeton de lancement — le même
/// chemin que la barre latérale, l'écran de recherche dans les CR et les
/// notifications.
struct RecentMeetingsCard: View {

    // MARK: - Libellés et mesures du handoff §1d

    static let titre = "DERNIÈRES RÉUNIONS"
    static let lien = "Historique"
    static let vide = "Aucune réunion tenue sur ce projet."

    /// Largeur de la colonne de date. `TimecodeLabel` fait 34 et n'est pas
    /// touché (décision **D12**) : ici la date est un `Text` mono de 44.
    static let largeurDate: CGFloat = 44
    static let tailleDate: CGFloat = 11
    static let tailleTitre: CGFloat = 13
    static let tailleResume: CGFloat = 12
    /// Interligne du résumé : 1.45 du handoff, exprimé en points ajoutés.
    static var interligneResume: CGFloat { tailleResume * 0.45 }

    let meetings: [ProjectPilotageState.MeetingRow]
    let onHistorique: () -> Void
    let onOuvrir: (ProjectPilotageState.MeetingRow) -> Void

    var body: some View {
        PilotageCard(marges: nil) {
            PilotageCardHeader(titre: Self.titre, lien: Self.lien, action: onHistorique)
            if meetings.isEmpty {
                Text(Self.vide)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .padding(.horizontal, PilotageMetrics.margeH)
                    .padding(.vertical, 11)
            } else {
                ForEach(Array(meetings.enumerated()), id: \.element.id) { rang, ligne in
                    row(ligne)
                        .pilotageRowSeparator(rang < meetings.count - 1)
                }
            }
        }
    }

    private func row(_ ligne: ProjectPilotageState.MeetingRow) -> some View {
        Button { onOuvrir(ligne) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(ligne.dateLabel)
                    .font(.plexMono(Self.tailleDate, .medium))
                    .foregroundStyle(One2OneToken.ink4)
                    .frame(width: Self.largeurDate, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let badge = ligne.badge {
                            MeetingTypeBadgeView(badge: badge)
                        }
                        Text(ligne.titre)
                            .font(.plexSans(Self.tailleTitre))
                            .foregroundStyle(One2OneToken.ink1)
                            .lineLimit(1)
                    }
                    if !ligne.resume.isEmpty {
                        Text(ligne.resume)
                            .font(.plexSans(Self.tailleResume))
                            .foregroundStyle(One2OneToken.ink3)
                            .lineSpacing(Self.interligneResume)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PilotageMetrics.margeH)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir « \(ligne.titre) »")
    }
}
