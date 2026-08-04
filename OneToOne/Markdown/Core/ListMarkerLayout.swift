import AppKit

/// Calcule le texte et l'indentation du marqueur affiché en tête d'un item de
/// liste (puce, numéro, case à cocher) — jamais écrit dans le storage, voir
/// `MarkdownLayoutManager` pour le dessin proprement dit. Fonctions pures,
/// testables sans vue vivante.
enum ListMarkerLayout {

    /// Incrément d'indentation par niveau d'imbrication, en points. Valeur
    /// reprise de l'ancien `StyleRenderer.applyVisualStyle`
    /// (`baseIndent = level * 16 + 16`) : le niveau 0 reste à 16pt, chaque
    /// niveau supplémentaire ajoute 16pt — l'imbrication n'est pas touchée
    /// par ce chantier.
    static let indentPerLevel: CGFloat = 16

    /// Indentation du texte d'un item de liste à `level` donné — la même
    /// valeur pour la première ligne et les lignes de repli.
    ///
    /// Avant ce chantier, `firstLineHeadIndent` valait `headIndent - 12` :
    /// un écart qui ne réservait de la place à *rien* tant qu'aucun marqueur
    /// n'était dessiné, et qui plaçait le texte de la première ligne — seul
    /// contenu réel de cette ligne, le storage ne portant aucun caractère de
    /// marqueur — 12pt plus à gauche que les lignes de repli (mesuré :
    /// niveau 0 donnait `firstLineHeadIndent = 4`, quasi au bord du
    /// conteneur). Un marqueur ne peut se dessiner qu'à *gauche* du texte,
    /// donc à gauche de `firstLineHeadIndent` : le préserver à 4 n'aurait
    /// laissé aucune place. Les deux valeurs sont donc désormais égales, et
    /// `MarkdownLayoutManager` dessine le marqueur dans la marge ainsi
    /// libérée, sans changer la progression par niveau (16, 32, 48…),
    /// c'est-à-dire sans changer l'indentation visible du **texte** d'un
    /// item, seulement la position d'un marqueur qui n'existait pas avant.
    static func textIndent(for level: Int) -> CGFloat {
        CGFloat(max(0, level)) * indentPerLevel + indentPerLevel
    }

    /// Texte du marqueur affiché pour `info`. `index` retombe sur `1` par
    /// défaut pour un item ordonné, comme `MarkdownSerializer.prefix(for:)`.
    /// `checked` distingue les deux états d'une case à cocher ; `nil` (ne
    /// devrait pas arriver pour `.task`, `MarkdownParser` pose toujours une
    /// valeur) se comporte comme décoché.
    static func markerText(for info: ListInfo) -> String {
        switch info.kind {
        case .bullet:
            return "•"
        case .ordered:
            return "\(info.index ?? 1)."
        case .task:
            return info.checked == true ? "☑" : "☐"
        }
    }
}
