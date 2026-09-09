import SwiftUI

/// Un des trois groupes de la vue « À risque » (capture
/// `1f-vue-a-risque.png`) : un titre teinté, puis une carte dont chaque ligne
/// est un projet et son action.
///
/// **Rien n'est calculé ici** : le titre, le détail et l'intitulé de l'action
/// viennent d'`AtRiskBuilder` (décision **D11**). Ce fichier ne porte que la
/// géométrie et la table des teintes.
struct AtRiskGroup: View {

    // MARK: - Libellés et mesures du handoff §1f

    static let titreJalons = "JALON DÉPASSÉ"
    static let titreSilences = "SANS RÉUNION DEPUIS 30 J"
    static let titreFiches = "FICHE INCOMPLÈTE"

    /// « JALON DÉPASSÉ — 2 ». Le tiret est un cadratin, comme la maquette.
    static func titre(_ libelle: String, _ compte: Int) -> String {
        "\(libelle) — \(compte)"
    }

    /// Le bord gauche de la carte, teinté du motif.
    static let largeurDuBord: CGFloat = 3
    static let rayon: CGFloat = 7
    static let ecartTitreCarte: CGFloat = 9

    static let tailleNom: CGFloat = 13
    /// 12 pt : au-dessus du plancher de 11,5 pt d'`inkMuted` (§1.2).
    static let tailleDetail: CGFloat = 12
    static let tailleAction: CGFloat = 12.5

    static let margeLigneH: CGFloat = 16
    static let margeLigneV: CGFloat = 12
    static let ecartNomDetail: CGFloat = 3

    // MARK: - Entrées

    let libelle: String
    let teinte: Color
    let lignes: [AtRiskItem]
    /// Le nom cliqué, hors action : ouvre l'écran projet (onglet Pilotage).
    let onOuvrir: (AtRiskItem) -> Void
    /// Le lien de droite.
    let onAgir: (AtRiskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Self.ecartTitreCarte) {
            // `sectionLabel(_:)` et non `.sectionLabel().foregroundStyle(…)` :
            // le modificateur peint le texte lui-même, une teinte posée
            // par-dessus ne l'atteindrait pas.
            Text(Self.titre(libelle, lignes.count))
                .sectionLabel(teinte)
            carte
        }
    }

    private var carte: some View {
        VStack(spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                if index > 0 {
                    Rectangle()
                        .fill(One2OneToken.hair)
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                }
                AtRiskRow(ligne: ligne, onOuvrir: onOuvrir, onAgir: onAgir)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(One2OneToken.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(teinte)
                .frame(width: Self.largeurDuBord)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.rayon, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.rayon, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Une ligne

/// Une ligne de la carte : le nom du projet, son détail, et l'action à droite.
struct AtRiskRow: View {

    let ligne: AtRiskItem
    let onOuvrir: (AtRiskItem) -> Void
    let onAgir: (AtRiskItem) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { onOuvrir(ligne) } label: {
                VStack(alignment: .leading, spacing: AtRiskGroup.ecartNomDetail) {
                    Text(ligne.title)
                        .font(.plexSans(AtRiskGroup.tailleNom, .medium))
                        .foregroundStyle(One2OneToken.ink1)
                        .lineLimit(1)
                    Text(ligne.detail)
                        .font(.plexSans(AtRiskGroup.tailleDetail))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir « \(ligne.title) »")

            Button { onAgir(ligne) } label: {
                Text(ligne.action.libelle)
                    .font(.plexSans(AtRiskGroup.tailleAction))
                    .foregroundStyle(One2OneToken.action)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(aide)
        }
        .padding(.leading, AtRiskGroup.margeLigneH + AtRiskGroup.largeurDuBord)
        .padding(.trailing, AtRiskGroup.margeLigneH)
        .padding(.vertical, AtRiskGroup.margeLigneV)
    }

    /// Ce que le lien fera, dit avant le clic.
    private var aide: String {
        switch ligne.action {
        case .replan:   return "Ouvrir la fiche complète pour replanifier le jalon"
        case .schedule: return "Créer une réunion de projet dans sept jours"
        case .complete: return "Ouvrir l'écran projet sur le champ à renseigner"
        }
    }
}
