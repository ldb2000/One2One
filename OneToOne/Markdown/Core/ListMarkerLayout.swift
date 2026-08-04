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

    /// Espace, en points, laissé entre le marqueur et le début du texte.
    static let markerTrailingGap: CGFloat = 4

    /// Police et couleur fixes du marqueur — indépendantes du style du
    /// *texte* de l'item. `MarkdownLayoutManager` lisait auparavant `.font`/
    /// `.foregroundColor` au premier caractère de l'item, donc un item en
    /// gras/lien/code inline dessinait sa case/puce en gras/bleu/monospace
    /// grisé (mesuré). Un marqueur n'est pas de l'inline stylé, c'est un
    /// repère structurel : une seule apparence, quel que soit le contenu.
    static let markerFont = NSFont.systemFont(ofSize: StyleRenderer.baseFontSize)
    static let markerColor = NSColor.labelColor

    /// Indentation du texte d'un item de liste — la même valeur pour la
    /// première ligne et les lignes de repli.
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
    /// libérée.
    ///
    /// Cette marge (`indentPerLevel`, 16pt) suffit à une puce ou une case à
    /// cocher, mais pas à un item numéroté à deux ou trois chiffres : mesuré
    /// à la police du marqueur, `"10."` fait ~17,3pt et `"123."` ~25,1pt, au-
    /// delà des 12pt utilisables (16 moins `markerTrailingGap`) — le
    /// marqueur se retrouverait rogné sur son bord gauche. La colonne
    /// réservée au marqueur s'élargit donc au besoin
    /// (`max(indentPerLevel, largeur du marqueur + gouttière)`) ; la
    /// progression *entre* niveaux (16pt) reste inchangée, seule la colonne
    /// du niveau le plus profond (celui qui porte effectivement `info`)
    /// s'adapte. Contrepartie acceptée : deux items d'un même niveau dont
    /// les marqueurs ont des largeurs différentes (ex. `"9."` puis `"10."`)
    /// peuvent démarrer leur texte à des abscisses légèrement différentes —
    /// préférable à un marqueur tronqué, et non visuellement vérifiable
    /// depuis ce chantier de toute façon.
    static func textIndent(for info: ListInfo) -> CGFloat {
        let level = CGFloat(max(0, info.level))
        let markerWidth = (markerText(for: info) as NSString)
            .size(withAttributes: [.font: markerFont])
            .width
        let markerColumn = max(indentPerLevel, markerWidth + markerTrailingGap)
        return level * indentPerLevel + markerColumn
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
