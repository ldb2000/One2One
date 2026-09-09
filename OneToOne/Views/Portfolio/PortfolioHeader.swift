import SwiftUI

/// L'en-tête du Portfolio (capture `1a-portfolio.png`, zone « ~48 px ») :
/// titre, sous-titre, segmenté « Tableau / Groupé par entité », bouton
/// « ＋ Nouveau projet ».
struct PortfolioHeader: View {

    /// Le titre de l'écran, tel que le handoff §1a l'écrit.
    ///
    /// **La capture affiche « Portfolio » et le tableau du handoff
    /// « Projets ».** Le tableau gagne : c'est lui qui spécifie la zone, il
    /// nomme aussi le sous-titre complet (« 62 actifs · 8 entités · 14
    /// archivés », là où la capture s'arrête aux entités), et « Portfolio »
    /// est déjà le libellé de l'entrée de barre latérale qui mène ici —
    /// répéter le nom de la destination en titre d'écran n'apporte rien.
    static let titre = "Projets"

    /// Le libellé du bouton d'ajout, au caractère de la capture (le `＋` est
    /// une pleine chasse, U+FF0B).
    static let nouveauProjet = "＋ Nouveau projet"

    /// Titre d'écran, handoff §Typographie : `plexSans(17, .semibold)`.
    static let tailleTitre: CGFloat = 17
    /// Sous-titre : 12 pt.
    static let tailleSousTitre: CGFloat = 12
    /// Libellé du bouton plein : 12 pt.
    static let tailleBouton: CGFloat = 12
    /// Hauteur de la zone.
    static let hauteur: CGFloat = 48

    let sousTitre: String
    @Binding var mode: PortfolioModel.Mode
    let nouveau: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Self.titre)
                .font(.plexSans(Self.tailleTitre, .semibold))
                .foregroundStyle(One2OneToken.ink1)

            Text(sousTitre)
                .font(.plexSans(Self.tailleSousTitre))
                .foregroundStyle(One2OneToken.inkMuted)
                .lineLimit(1)

            Spacer(minLength: 12)

            SegmentedMode(selection: $mode,
                          options: PortfolioModel.Mode.allCases,
                          taille: Self.tailleBouton,
                          libelle: \.libelle)

            Button(action: nouveau) {
                Text(Self.nouveauProjet)
                    .font(.plexSans(Self.tailleBouton, .medium))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.action)
                    )
            }
            .buttonStyle(.plain)
            .help("Créer un projet et l'ouvrir")
        }
        .frame(height: Self.hauteur)
        .padding(.horizontal, 22)
    }
}
