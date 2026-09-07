import SwiftUI

/// Une ligne de note du mode séance dont les mentions `@Prénom` sont des
/// **pilules** (capture `1b-mode-seance.png` : « Qui donne le feu vert ?
/// `@Yann` »).
///
/// Pourquoi une mise en page et non un `Text` attribué : une pilule a un fond
/// arrondi, et `AttributedString.backgroundColor` ne donne qu'un rectangle
/// plein qui, sur une mention en fin de ligne, se colle au bord du bloc. Le
/// prix à payer est la sélection du texte, perdue sur les lignes qui portent
/// une mention — en séance on prend des notes, on ne copie pas les siennes.
///
/// Le découpage vient de `SessionMentionRuns`, testé à part : ici il n'y a que
/// du dessin.
struct MentionFlow: View {

    let fragments: [SessionMentionRuns.Run]
    let couleurs: One2OneColors

    var body: some View {
        WrapLayout(horizontalSpacing: 0, verticalSpacing: 3) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                switch element {
                case .mot(let mot):
                    Text(mot)
                        .font(.plexSans(12))
                        .foregroundStyle(couleurs.ink2)
                case .mention(let nom):
                    Text("@\(nom)")
                        .font(.plexSans(11.5, .medium))
                        .foregroundStyle(couleurs.actionInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(couleurs.pill)
                        )
                }
            }
        }
    }

    /// Ce que la mise en page dispose : des mots (l'espace collé à droite, pour
    /// que le retour à la ligne tombe entre les mots et non au milieu) et des
    /// mentions.
    private enum Element {
        case mot(String)
        case mention(String)
    }

    /// Découpe les fragments de texte en mots, en gardant les espaces avec le
    /// mot qui les précède : sans cela, un retour à la ligne mangerait
    /// l'espace et « feu vert ?@Yann » serait recollé.
    private var elements: [Element] {
        var resultat: [Element] = []
        for fragment in fragments {
            switch fragment {
            case .mention(let nom):
                resultat.append(.mention(nom))
            case .texte(let texte):
                var mot = ""
                for caractere in texte {
                    mot.append(caractere)
                    if caractere == " " {
                        resultat.append(.mot(mot))
                        mot = ""
                    }
                }
                if !mot.isEmpty { resultat.append(.mot(mot)) }
            }
        }
        return resultat
    }
}

/// Mise en page en flot : les sous-vues se rangent de gauche à droite et
/// passent à la ligne quand la largeur proposée est atteinte.
///
/// SwiftUI n'en fournit pas ; celle-ci est volontairement minimale — elle ne
/// sert qu'à faire couler une ligne de note dont un fragment est une pilule.
struct WrapLayout: Layout {

    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        let lignes = decoupe(subviews: subviews, largeurMax: largeur)
        let hauteur = lignes.reduce(0) { total, ligne in
            total + ligne.hauteur
        } + verticalSpacing * CGFloat(max(0, lignes.count - 1))
        let largeurUtile = lignes.map(\.largeur).max() ?? 0
        return CGSize(width: min(largeur.isFinite ? largeur : largeurUtile, max(largeurUtile, 0)),
                      height: hauteur)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let lignes = decoupe(subviews: subviews, largeurMax: bounds.width)
        var y = bounds.minY
        for ligne in lignes {
            var x = bounds.minX
            for index in ligne.indices {
                let taille = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (ligne.hauteur - taille.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(taille)
                )
                x += taille.width + horizontalSpacing
            }
            y += ligne.hauteur + verticalSpacing
        }
    }

    private struct Ligne {
        var indices: [Int] = []
        var largeur: CGFloat = 0
        var hauteur: CGFloat = 0
    }

    private func decoupe(subviews: Subviews, largeurMax: CGFloat) -> [Ligne] {
        var lignes: [Ligne] = []
        var courante = Ligne()
        for index in subviews.indices {
            let taille = subviews[index].sizeThatFits(.unspecified)
            let largeurProjetee = courante.indices.isEmpty
                ? taille.width
                : courante.largeur + horizontalSpacing + taille.width
            if !courante.indices.isEmpty, largeurProjetee > largeurMax {
                lignes.append(courante)
                courante = Ligne(indices: [index], largeur: taille.width, hauteur: taille.height)
            } else {
                courante.indices.append(index)
                courante.largeur = largeurProjetee
                courante.hauteur = max(courante.hauteur, taille.height)
            }
        }
        if !courante.indices.isEmpty { lignes.append(courante) }
        return lignes
    }
}
