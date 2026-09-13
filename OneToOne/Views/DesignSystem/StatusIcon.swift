import SwiftUI

/// La pastille de statut d'un projet — le rond que les captures
/// `1a-portfolio.png` et `2b-sidebar-variante-arbre-replie.png` posent devant
/// chaque nom de projet (décision **D16**).
///
/// Elle vivait dans `ProjectListView.swift`, sur les couleurs système
/// (`.green`, `.yellow`, `.red`, `.gray`) — et cette vue-là disparaît au lot 2.
/// Deux changements, tous deux voulus :
///
/// 1. **Les jetons.** `ok` / `warn` / `report` / `inkMuted` au lieu des
///    couleurs système : `One2OneToken` est la seule source de couleurs du
///    dépôt, et le vert de la maquette n'est pas celui d'Apple.
/// 2. **La taille en paramètre**, 9 par défaut — la mesure de la colonne du
///    Portfolio (handoff §1a). La section « Projets » de la barre latérale
///    demande 10 ; les appels historiques passent `12`, la taille qu'ils
///    avaient, pour que la migration ne change que leur teinte.
///
/// La lecture du statut passe par `ProjectStatus` (décision **D14**) : casse,
/// accents et espaces de bord ignorés, et toute valeur hors table en neutre —
/// le portfolio externe écrit ce qu'il veut dans cette colonne.
struct StatusIcon: View {

    /// Le statut persisté, tel quel (`"Green"`, `"Yellow"`, `"Red"`,
    /// `"Unknown"`, ou n'importe quoi d'autre).
    let status: String

    /// Diamètre de la pastille, en points.
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(Self.teinte(status))
            .frame(width: size, height: size)
    }

    /// La teinte d'un statut persisté — la table du handoff (« Green `ok` ·
    /// Yellow `warn` · Red `report` · Unknown `inkMuted` »).
    ///
    /// Fonction pure et testée : c'est elle que le Portfolio (lot 2), l'écran
    /// projet (lot 4) et la vue « À risque » (lot 5) réutiliseront, et la
    /// couleur d'une pastille est le genre de détail qu'on réécrit sans le
    /// vouloir.
    static func teinte(_ status: String) -> Color {
        switch ProjectStatus(raw: status) {
        case .green?:  return One2OneToken.ok
        case .yellow?: return One2OneToken.warn
        case .red?:    return One2OneToken.report
        case .unknown?, nil: return One2OneToken.inkMuted
        }
    }
}
