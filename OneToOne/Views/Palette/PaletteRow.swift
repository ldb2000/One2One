import SwiftUI

/// Les deux formes de ligne de la palette `⌘K` (capture
/// `1c-palette-cmdk.png`) : un projet, ou une action.
///
/// Elles partagent leur géométrie — 8 pt de haut, 10 pt de côté, 10 pt entre
/// la colonne de gauche et le texte, rayon 7 sur le fond `actionBg` de la
/// ligne sélectionnée — et c'est `PaletteRowFrame` qui la tient. Deux vues qui
/// dessineraient chacune leur fond finiraient par ne plus s'aligner.
enum PaletteRowMetrics {
    /// `padding: 8px 10px` de la maquette.
    static let paddingV: CGFloat = 8
    static let paddingH: CGFloat = 10
    /// L'écart entre la pastille (ou l'icône) et le texte.
    static let gap: CGFloat = 10
    /// Le nom du projet et le libellé d'une action : 13,5 pt.
    static let tailleLibelle: CGFloat = 13.5
    /// La sous-ligne mono : 10,5 pt.
    static let tailleSousLigne: CGFloat = 10.5
    /// Le `↩` de droite, et l'icône d'action : 10 pt.
    static let tailleTouche: CGFloat = 10
    /// Le diamètre de la pastille de statut (handoff §1c).
    static let taillePastille: CGFloat = 9
    /// La colonne de gauche, pour que pastille et icône s'alignent.
    static let colonneGauche: CGFloat = 14
}

/// Le cadre d'une ligne : le fond de sélection et les marges.
private struct PaletteRowFrame<Content: View>: View {
    let selectionnee: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, PaletteRowMetrics.paddingV)
            .padding(.horizontal, PaletteRowMetrics.paddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(selectionnee ? One2OneToken.actionBg : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

/// La ligne d'un projet : pastille de statut, nom surligné, sous-ligne mono,
/// et le `↩` que la capture ne montre **que** sur la ligne sélectionnée.
struct PaletteProjectRow: View {

    let projet: Project
    let terme: String
    let selectionnee: Bool

    var body: some View {
        PaletteRowFrame(selectionnee: selectionnee) {
            HStack(alignment: .center, spacing: PaletteRowMetrics.gap) {
                StatusIcon(status: projet.status, size: PaletteRowMetrics.taillePastille)
                    .frame(width: PaletteRowMetrics.colonneGauche, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    HighlightedText(texte: projet.name,
                                    terme: terme,
                                    fonte: .plexSans(PaletteRowMetrics.tailleLibelle))
                        .lineLimit(1)
                    Text(PaletteModel.sousLigne(projet))
                        .font(.plexMono(PaletteRowMetrics.tailleSousLigne))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Le rappel de la touche d'activation, sur la ligne du curseur
                // seulement : le montrer partout ferait quatre `↩` empilés et
                // n'indiquerait plus rien.
                if selectionnee {
                    Text("↩")
                        .font(.plexMono(PaletteRowMetrics.tailleTouche))
                        .foregroundStyle(One2OneToken.actionInk)
                }
            }
        }
    }
}

/// La ligne d'une action : icône neutre et libellé citant le terme.
struct PaletteActionRow: View {

    let action: PaletteModel.Action
    let terme: String
    let selectionnee: Bool

    var body: some View {
        PaletteRowFrame(selectionnee: selectionnee) {
            HStack(alignment: .center, spacing: PaletteRowMetrics.gap) {
                Image(systemName: action.icone)
                    .font(.system(size: 11))
                    .foregroundStyle(One2OneToken.ink4)
                    .frame(width: PaletteRowMetrics.colonneGauche, alignment: .center)

                Text(PaletteModel.libelle(action, terme: terme))
                    .font(.plexSans(PaletteRowMetrics.tailleLibelle))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if selectionnee {
                    Text("↩")
                        .font(.plexMono(PaletteRowMetrics.tailleTouche))
                        .foregroundStyle(One2OneToken.actionInk)
                }
            }
        }
    }
}
