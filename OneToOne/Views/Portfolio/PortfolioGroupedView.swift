import SwiftUI
import SwiftData

/// Le mode « Groupé par entité » du segmenté de l'en-tête : **les mêmes
/// lignes**, rangées sous un en-tête d'entité et son compteur.
///
/// Les mêmes lignes et le même composant (`PortfolioTable`) : le groupement
/// est une fonction pure (`PortfolioBuilder.groups`) et un en-tête de section,
/// pas un second tableau. L'alternance de fond continue d'un groupe au
/// suivant, d'où le décalage passé à chaque tranche.
struct PortfolioGroupedView: View {

    /// Le libellé du groupe des projets sans entité, tel que
    /// `PortfolioBuilder.groups` le nomme.
    static let sansEntite = PortfolioBuilder.sansEntite

    /// Un en-tête de groupe ouvre la fiche de son entité — sauf celui des
    /// orphelins, qui n'en désigne aucune.
    ///
    /// C'est le seul chemin vers `EntityDetailView` depuis la fenêtre
    /// principale depuis que l'arbre par entité de la barre latérale a été
    /// retiré (lot 6, variante 2a du handoff).
    static func estCliquable(_ entite: String) -> Bool { entite != sansEntite }

    /// L'invite d'un groupement vide.
    static let aucunResultat = PortfolioTable.aucunResultat

    let groupes: [(entite: String, lignes: [PortfolioRow])]
    let tri: PortfolioSort
    let selection: Set<PersistentIdentifier>
    let trierPar: (PortfolioSort.Column) -> Void
    let ouvrir: (PortfolioRow) -> Void
    let basculerSelection: (PortfolioRow) -> Void
    /// Ouvrir la fiche de l'entité que nomme un en-tête de groupe.
    let ouvrirEntite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if groupes.isEmpty {
                Text(Self.aucunResultat)
                    .font(.plexSans(PortfolioTable.tailleCellule))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .padding(.horizontal, PortfolioTable.marge)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(decalages.enumerated()), id: \.element.entite) { _, groupe in
                    enteteDeGroupe(groupe.entite, nombre: groupe.lignes.count)
                    PortfolioTable(lignes: groupe.lignes,
                                   tri: tri,
                                   selection: selection,
                                   decalage: groupe.decalage,
                                   avecEntete: false,
                                   trierPar: trierPar,
                                   ouvrir: ouvrir,
                                   basculerSelection: basculerSelection)
                }
            }
        }
    }

    /// Les groupes, chacun avec le rang de sa première ligne dans l'ensemble —
    /// ce qui fait tenir l'alternance `surface` / `surfaceAlt`.
    private var decalages: [(entite: String, lignes: [PortfolioRow], decalage: Int)] {
        var resultat: [(entite: String, lignes: [PortfolioRow], decalage: Int)] = []
        var cumul = 0
        for groupe in groupes {
            resultat.append((groupe.entite, groupe.lignes, cumul))
            cumul += groupe.lignes.count
        }
        return resultat
    }

    @ViewBuilder
    private func enteteDeGroupe(_ entite: String, nombre: Int) -> some View {
        let contenu = HStack(spacing: 6) {
            Text(entite)
                .sectionLabel()
            Text("\(nombre)")
                .font(.plexMono(PortfolioTable.tailleJalon))
                .foregroundStyle(One2OneToken.ink4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PortfolioTable.marge)
        .frame(height: PortfolioTable.hauteurEntete)
        .contentShape(Rectangle())
        .background(One2OneToken.bgApp)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }

        if Self.estCliquable(entite) {
            Button { ouvrirEntite(entite) } label: { contenu }
                .buttonStyle(.plain)
                .help(entite)
        } else {
            contenu
        }
    }
}
