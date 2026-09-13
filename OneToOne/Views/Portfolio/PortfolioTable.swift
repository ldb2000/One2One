import SwiftUI
import SwiftData

/// Le tableau du Portfolio (capture `1a-portfolio.png`) : un en-tête de 30 px
/// et des lignes de 44 px, huit colonnes, tri au clic sur l'en-tête.
///
/// **Une grille de largeurs fixes, pas une `Table`.** `Table` de SwiftUI
/// impose son propre chrome (fond, séparateurs, sélection système) et ne sait
/// pas mettre deux textes de tailles différentes dans une cellule — ce que la
/// colonne « Projet » demande (nom 13 pt, `code · type` en mono 10,5 pt). Les
/// largeurs du handoff sont donc posées à la main, et la colonne du nom prend
/// la place restante.
///
/// **Rien n'est calculé ici** (décision **D11**) : les lignes arrivent déjà
/// filtrées et triées de `PortfolioModel`.
struct PortfolioTable: View {

    // MARK: - Mesures (handoff §1a)

    /// Hauteur de l'en-tête.
    static let hauteurEntete: CGFloat = 30
    /// Hauteur d'une ligne.
    static let hauteurLigne: CGFloat = 44
    /// Marge horizontale du tableau.
    static let marge: CGFloat = 22
    /// Écart entre deux colonnes.
    static let ecart: CGFloat = 12

    /// Les largeurs des colonnes, dans l'ordre de la capture.
    ///
    /// Le handoff donne `22 | 1fr | 88 | 92 | 88 | 126 | 78` — sept colonnes,
    /// alors que la capture en montre **huit** : « Jalon » s'intercale entre
    /// « Chef de projet » et « Dernière réu. ». Les six premières largeurs
    /// sont celles du handoff ; « Jalon » (72) et « Dernière réu. » (92) sont
    /// mesurées sur la capture 2×.
    static let largeurPastille: CGFloat = 22
    static let largeurEntite: CGFloat = 88
    static let largeurPhase: CGFloat = 92
    static let largeurRisque: CGFloat = 88
    static let largeurChef: CGFloat = 126
    static let largeurJalon: CGFloat = 72
    static let largeurDerniereReunion: CGFloat = 92

    /// Nom du projet : corps du handoff.
    static let tailleNom: CGFloat = 13
    /// `code · type` : mono 10,5 pt.
    static let tailleCode: CGFloat = 10.5
    /// Entité, chef de projet, dernière réunion : secondaire.
    static let tailleCellule: CGFloat = 12.5
    /// Cellule « Jalon » : mono 11 pt.
    static let tailleJalon: CGFloat = 11

    /// L'invite d'un tableau que les facettes ont vidé.
    static let aucunResultat = "Aucun projet ne correspond"

    // MARK: - Entrées

    let lignes: [PortfolioRow]
    let tri: PortfolioSort
    let selection: Set<PersistentIdentifier>
    /// Décalage vertical du numéro de ligne, pour que l'alternance de fond
    /// reste continue d'un groupe à l'autre en mode « Groupé par entité ».
    var decalage: Int = 0
    /// Affiche l'en-tête de colonnes. Le mode groupé n'en met qu'un, en tête.
    var avecEntete: Bool = true
    let trierPar: (PortfolioSort.Column) -> Void
    let ouvrir: (PortfolioRow) -> Void
    let basculerSelection: (PortfolioRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if avecEntete { entete }
            if lignes.isEmpty && avecEntete {
                Text(Self.aucunResultat)
                    .font(.plexSans(Self.tailleCellule))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.marge)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(lignes.enumerated()), id: \.element.id) { rang, ligne in
                    self.ligne(ligne, rang: rang + decalage)
                }
            }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: Self.ecart) {
            // La colonne de pastille n'a pas de libellé sur la capture.
            Spacer().frame(width: Self.largeurPastille)
            libelleTriable(.name, alignement: .leading, largeur: nil)
            libelleTriable(.entity, alignement: .leading, largeur: Self.largeurEntite)
            libelleTriable(.phase, alignement: .leading, largeur: Self.largeurPhase)
            libelleTriable(.risk, alignement: .leading, largeur: Self.largeurRisque)
            libelleTriable(.manager, alignement: .leading, largeur: Self.largeurChef)
            libelleTriable(.milestone, alignement: .leading, largeur: Self.largeurJalon)
            libelleTriable(.lastMeeting, alignement: .leading, largeur: Self.largeurDerniereReunion)
        }
        .padding(.horizontal, Self.marge)
        .frame(height: Self.hauteurEntete)
        .background(One2OneToken.bgApp)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    @ViewBuilder
    private func libelleTriable(_ colonne: PortfolioSort.Column,
                                alignement: Alignment,
                                largeur: CGFloat?) -> some View {
        Button {
            trierPar(colonne)
        } label: {
            HStack(spacing: 4) {
                Text(colonne.header)
                    .sectionLabel()
                if tri.column == colonne {
                    Text(tri.ascending ? "↑" : "↓")
                        .sectionLabel()
                }
                if alignement == .leading { Spacer(minLength: 0) }
            }
            .frame(width: largeur, alignment: alignement)
        }
        .buttonStyle(.plain)
        .help("Trier par \(colonne.header.lowercased())")
    }

    // MARK: - Ligne

    @ViewBuilder
    private func ligne(_ ligne: PortfolioRow, rang: Int) -> some View {
        let choisie = selection.contains(ligne.id)
        HStack(spacing: Self.ecart) {
            HStack(spacing: 0) {
                StatusIcon(status: ligne.statusLabel)
                Spacer(minLength: 0)
            }
            .frame(width: Self.largeurPastille)

            VStack(alignment: .leading, spacing: 2) {
                Text(ligne.name)
                    .font(.plexSans(Self.tailleNom, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Text("\(ligne.code) · \(ligne.type)")
                    .font(.plexMono(Self.tailleCode))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ligne.entityLabel)
                .font(.plexSans(Self.tailleCellule))
                .foregroundStyle(ligne.entity == nil ? One2OneToken.inkMuted : One2OneToken.ink2)
                .lineLimit(1)
                .frame(width: Self.largeurEntite, alignment: .leading)

            PhaseBadge(phase: ligne.phase, brute: ligne.phaseRaw)
                .frame(width: Self.largeurPhase, alignment: .leading)

            RiskBadge(risk: ligne.risk)
                .frame(width: Self.largeurRisque, alignment: .leading)

            chefDeProjet(ligne)
                .frame(width: Self.largeurChef, alignment: .leading)

            Text(ligne.nextMilestone.libelle)
                .font(.plexMono(Self.tailleJalon, .medium))
                .foregroundStyle(ligne.nextMilestone.estAlerte
                                 ? One2OneToken.reportInk
                                 : (ligne.nextMilestone == MilestoneCell.none
                                    ? One2OneToken.inkMuted : One2OneToken.ink2))
                .lineLimit(1)
                .frame(width: Self.largeurJalon, alignment: .leading)

            Text(ligne.lastMeetingLabel)
                .font(.plexSans(Self.tailleCellule))
                .foregroundStyle(One2OneToken.ink4)
                .lineLimit(1)
                .frame(width: Self.largeurDerniereReunion, alignment: .leading)
        }
        .padding(.horizontal, Self.marge)
        .frame(height: Self.hauteurLigne)
        .background(choisie ? One2OneToken.actionBg : fond(rang))
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
        .contentShape(Rectangle())
        // ⇧-clic entre dans la sélection multiple ; le clic simple ouvre le
        // projet. La priorité haute est indispensable : sans elle, le
        // `onTapGesture` avale le clic avant que le modificateur soit lu.
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { basculerSelection(ligne) })
        .onTapGesture { ouvrir(ligne) }
    }

    /// La colonne « Chef de projet » — « Non affecté » en italique et en
    /// `inkMuted` quand la relation manque (décision **D3**).
    @ViewBuilder
    private func chefDeProjet(_ ligne: PortfolioRow) -> some View {
        if let manager = ligne.manager {
            Text(manager)
                .font(.plexSans(Self.tailleCellule))
                .foregroundStyle(One2OneToken.ink2)
                .lineLimit(1)
        } else {
            Text(ProjectPeople.nonAffecte)
                .font(.plexSansItalic(Self.tailleCellule))
                .foregroundStyle(One2OneToken.inkMuted)
                .lineLimit(1)
        }
    }

    /// Lignes alternées `surface` / `surfaceAlt` (handoff §1a).
    private func fond(_ rang: Int) -> Color {
        rang.isMultiple(of: 2) ? One2OneToken.surface : One2OneToken.surfaceAlt
    }
}
