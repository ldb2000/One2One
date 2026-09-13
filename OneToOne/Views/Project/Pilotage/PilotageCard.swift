import SwiftUI

/// Les marges d'une carte de pilotage.
///
/// Dans un `enum` à part et non en membres statiques de `PilotageCard` :
/// celui-ci est générique, et `PilotageCard.margeH` demanderait d'en nommer le
/// paramètre à chaque lecture.
enum PilotageMetrics {
    /// Marges d'une carte à contenu simple (« PÉRIMÈTRE & CONTEXTE », les
    /// cartes de la colonne latérale). Les cartes à lignes, elles, posent
    /// leurs marges ligne par ligne : un séparateur doit aller d'un bord à
    /// l'autre.
    static let margeH: CGFloat = 13
    static let margeV: CGFloat = 12
    /// Écart entre deux cartes d'une colonne (handoff §1d).
    static let ecartCartes: CGFloat = 14
}

/// Le châssis commun des cartes de l'onglet « Pilotage » : fond `surface`,
/// bord `cardBorder`, rayon 7 (handoff §1d).
///
/// Écrit une fois : cinq cartes le partagent, et une sixième écrite ailleurs
/// finirait par ne plus avoir le même rayon.
struct PilotageCard<Contenu: View>: View {

    /// Marges internes appliquées par la carte, ou `nil` pour une carte à
    /// lignes qui gère les siennes.
    var marges: EdgeInsets?
    @ViewBuilder let contenu: Contenu

    init(marges: EdgeInsets? = EdgeInsets(top: PilotageMetrics.margeV,
                                          leading: PilotageMetrics.margeH,
                                          bottom: PilotageMetrics.margeV,
                                          trailing: PilotageMetrics.margeH),
         @ViewBuilder contenu: () -> Contenu) {
        self.marges = marges
        self.contenu = contenu()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { contenu }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(marges ?? EdgeInsets())
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(One2OneToken.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
            )
    }
}

/// L'en-tête d'une carte à lignes : le libellé de section à gauche, un lien
/// à droite (« Tout voir », « Historique »), un filet en dessous.
struct PilotageCardHeader: View {

    /// Taille du lien de droite (handoff §1d) — au-dessus du plancher de
    /// 11,5 pt d'`inkMuted`, et de toute façon en `actionInk`.
    static let tailleLien: CGFloat = 11.5

    let titre: String
    var lien: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(titre).sectionLabel()
            Spacer(minLength: 8)
            if let lien, let action {
                Button(action: action) {
                    Text(lien)
                        .font(.plexSans(Self.tailleLien))
                        .foregroundStyle(One2OneToken.actionInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PilotageMetrics.margeH)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }
}

/// Le filet qui sépare deux lignes d'une carte. Posé en superposition basse
/// plutôt qu'en `Divider` : un `Divider` prend de la hauteur et décalerait la
/// grille de 44 pt.
struct PilotageRowSeparator: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if visible {
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
            }
        }
    }
}

extension View {
    func pilotageRowSeparator(_ visible: Bool) -> some View {
        modifier(PilotageRowSeparator(visible: visible))
    }
}
