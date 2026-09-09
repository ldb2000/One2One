import SwiftUI

/// La barre de filtres du Portfolio (capture `1a-portfolio.png`, zone
/// « ~42 px ») : le champ de recherche de 230 px, les chips de facettes, et
/// sous elles, à droite, le menu de vues enregistrées.
///
/// **Les chips actives passent devant.** La capture montre « Entité : ASP » et
/// « Risque ≥ Modéré » d'abord, puis « Phase ⌄ », « Statut ⌄ » et « Chef de
/// projet ⌄ » en tirets. C'est la règle, pas l'ordre de ce cas particulier :
/// ce qui filtre se lit avant ce qui pourrait filtrer.
///
/// **Le menu de vues est sur sa propre ligne.** Le tableau du handoff le place
/// « à droite » de la barre ; la capture le pose en dessous, aligné à droite —
/// c'est la capture qui est suivie, la barre étant déjà pleine à cinq chips.
struct PortfolioFilterBar: View {

    /// Le texte d'invite du champ, au mot de la capture.
    static let invite = "Nom, code, sponsor..."
    /// Largeur du champ de recherche (handoff §1a).
    static let largeurChamp: CGFloat = 230
    /// Hauteur de la barre.
    static let hauteur: CGFloat = 42
    /// Corps d'une chip (handoff : « 12 pt/500 »).
    static let tailleChip: CGFloat = 12

    let model: PortfolioModel
    let vues: [PortfolioSavedView]
    let enregistrerVue: () -> Void
    let supprimerVue: (PortfolioSavedView) -> Void

    /// Les facettes, les actives d'abord.
    private var facettes: [PortfolioFacet] {
        let actives = PortfolioFacet.allCases.filter { !model.actives($0).isEmpty }
        return actives + PortfolioFacet.allCases.filter { model.actives($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                champDeRecherche
                ForEach(facettes, id: \.self) { facette in
                    chip(facette)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.hauteur)

            HStack {
                Spacer(minLength: 0)
                SavedViewMenu(vues: vues,
                              active: model.vueActive,
                              choisir: { model.appliquer($0) },
                              enregistrer: enregistrerVue,
                              supprimer: supprimerVue)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    // MARK: - Le champ

    private var champDeRecherche: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(One2OneToken.ink4)
            TextField(Self.invite,
                      text: Binding(get: { model.champDeRecherche },
                                    set: { model.rechercher($0) }))
                .textFieldStyle(.plain)
                .font(.plexSans(Self.tailleChip))
                .foregroundStyle(One2OneToken.ink1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: Self.largeurChamp)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Les chips

    @ViewBuilder
    private func chip(_ facette: PortfolioFacet) -> some View {
        let actives = model.actives(facette)
        if actives.isEmpty {
            // Chip inactive : pilule en tirets, libellé puis chevron.
            //
            // `.menuStyle(.button)` **et pas** `.borderlessButton` — c'est le
            // correctif de la recette du 2026-09-09 (capture
            // `recette/lot-2-p1a-v1.png`). `.borderlessButton` passe par un
            // bouton AppKit, qui **extrait** de l'étiquette un titre et une
            // image et les redessine lui-même, image en tête : la pilule et
            // ses tirets disparaissaient et le chevron sortait **avant** le
            // libellé (« ⌄ Risque »). Le style `.button` rend l'étiquette
            // telle qu'elle est écrite, et honore `.menuIndicator(.hidden)`.
            Menu {
                menuDeValeurs(facette)
            } label: {
                pilule(libelle: facette.libelle, encre: One2OneToken.ink4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.rayonChip, style: .continuous)
                            .strokeBorder(One2OneToken.dashedBorder,
                                          style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filtrer par \(facette.libelle.lowercased())")
        } else {
            // Chip active : la croix doit rester cliquable à part, donc la
            // pilule est dessinée par le `HStack` qui porte les deux, et
            // l'étiquette du menu se réduit à son texte. C'est ce rendu que la
            // recette a validé — il ne change pas.
            HStack(spacing: 5) {
                Menu {
                    menuDeValeurs(facette)
                } label: {
                    Text(facette.libelleActif(actives))
                        .font(.plexSans(Self.tailleChip, .medium))
                        .foregroundStyle(encre(facette))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    model.effacer(facette)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(encre(facette))
                }
                .buttonStyle(.plain)
                .help("Retirer le filtre \(facette.libelle)")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Self.rayonChip, style: .continuous)
                    .fill(fond(facette))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.rayonChip, style: .continuous)
                    .strokeBorder(bord(facette), lineWidth: 1)
            )
        }
    }

    /// Le contenu d'une chip inactive : libellé 12 pt/500 puis chevron de 9 pt,
    /// dans cet ordre — c'est l'ordre que la capture montre et celui qu'un
    /// bouton AppKit inversait.
    private func pilule(libelle: String, encre: Color) -> some View {
        HStack(spacing: 4) {
            Text(libelle)
                .font(.plexSans(Self.tailleChip, .medium))
                .foregroundStyle(encre)
            Image(systemName: "chevron.down")
                .font(.system(size: Self.tailleChevron))
                .foregroundStyle(encre)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
    }

    /// Rayon d'une chip (handoff §1a : 20).
    private static let rayonChip: CGFloat = 20
    /// Chevron d'une chip et du menu de vues enregistrées.
    static let tailleChevron: CGFloat = 9

    /// L'encre d'une chip active. La chip de risque est teintée `report`,
    /// comme la capture la montre : c'est le seul filtre qui parle d'une
    /// alerte, et l'afficher en bleu d'action le ferait lire comme un réglage.
    private func encre(_ facette: PortfolioFacet) -> Color {
        facette == .risk ? One2OneToken.reportInk : One2OneToken.actionInk
    }

    private func fond(_ facette: PortfolioFacet) -> Color {
        facette == .risk ? One2OneToken.reportBg : One2OneToken.actionBg
    }

    private func bord(_ facette: PortfolioFacet) -> Color {
        (facette == .risk ? One2OneToken.report : One2OneToken.action).opacity(0.25)
    }

    /// Le menu de valeurs d'une facette : un bouton coché par valeur présente,
    /// et de quoi tout retirer.
    @ViewBuilder
    private func menuDeValeurs(_ facette: PortfolioFacet) -> some View {
        let actives = Set(model.actives(facette))
        ForEach(model.valeurs(de: facette), id: \.self) { valeur in
            Button {
                model.basculer(valeur, dans: facette)
            } label: {
                Text(actives.contains(valeur) ? "✓ \(prefixe(facette))\(valeur)"
                                              : "\(prefixe(facette))\(valeur)")
            }
        }
        if !actives.isEmpty {
            Divider()
            Button("Retirer ce filtre") { model.effacer(facette) }
        }
    }

    /// Le seuil de risque se lit « ≥ Modéré » jusque dans son menu : sans
    /// l'opérateur, cocher « Modéré » laisserait croire qu'on ne garde que les
    /// modérés.
    private func prefixe(_ facette: PortfolioFacet) -> String {
        facette == .risk ? "≥ " : ""
    }
}
