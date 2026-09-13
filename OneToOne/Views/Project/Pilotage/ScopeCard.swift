import SwiftUI

/// La carte « PÉRIMÈTRE & CONTEXTE » de l'onglet Pilotage (capture
/// `1d-ecran-projet-pilotage.png`).
///
/// C'est le premier champ **édité au clic** de l'application (décision
/// **D9**) : on lit un paragraphe, on clique dessus, il devient un champ ;
/// `⌘⏎` valide, `esc` referme sans rien écrire. Le pied pointillé le dit, et
/// dit aussi quand le périmètre a bougé pour la dernière fois.
struct ScopeCard: View {

    // MARK: - Libellés et mesures du handoff §1d

    static let titre = "PÉRIMÈTRE & CONTEXTE"
    static let placeholder = "Périmètre, contexte, dépendances…"
    /// Ce qu'affiche la carte quand personne n'a encore écrit de périmètre.
    static let vide = "Aucun périmètre décrit. Cliquer pour en écrire un."

    static let tailleTexte: CGFloat = 13
    /// Interligne 1.55 du handoff, exprimé en points ajoutés.
    static var interligne: CGFloat { tailleTexte * 0.55 }
    static let taillePied: CGFloat = 11.5

    let scopeText: String
    /// « Cliquer pour éditer · dernière mise à jour hier ».
    let pied: String
    let onValider: (String) -> Void

    var body: some View {
        PilotageCard {
            Text(Self.titre).sectionLabel()
                .padding(.bottom, 8)
            EditableInPlace(valeur: scopeText,
                            placeholder: Self.placeholder,
                            mode: .paragraphe,
                            fonte: .plexSans(Self.tailleTexte),
                            onValider: onValider) {
                Text(scopeText.isEmpty ? Self.vide : scopeText)
                    .font(.plexSans(Self.tailleTexte))
                    .foregroundStyle(scopeText.isEmpty ? One2OneToken.inkMuted : One2OneToken.ink2)
                    .lineSpacing(Self.interligne)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            filet
            Text(pied)
                .font(.plexSans(Self.taillePied))
                .foregroundStyle(One2OneToken.inkMuted)
        }
    }

    /// Le filet **tireté** du haut du pied : `dashedBorder`, le jeton posé au
    /// lot 0 précisément pour ces deux endroits de la capture 1d.
    private var filet: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .strokeBorder(One2OneToken.dashedBorder,
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(height: 1)
            )
            .padding(.top, 10)
            .padding(.bottom, 9)
    }
}
