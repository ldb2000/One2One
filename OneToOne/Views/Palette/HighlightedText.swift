import SwiftUI

/// Un texte dont les occurrences du terme cherché portent le fond `highlight`
/// — le jaune `#FFE9A8` de la capture `1c-palette-cmdk.png` (jeton **D12**).
///
/// **Une seule règle de correspondance.** Les plages viennent de
/// `ProjectSearch.highlightRanges`, celle qui décide déjà si un projet
/// correspond : sans cela, un projet trouvé par « etats » remonterait dans la
/// liste sans que « états » y soit surligné. C'est la même fonction, avec la
/// même pliure de casse et d'accents.
///
/// **Un `AttributedString` et non deux `Text` concaténés.** Un texte coupé en
/// morceaux ne se tronque pas proprement (`lineLimit` s'applique par morceau)
/// et perd sa césure ; l'attribut de fond, lui, suit le texte où qu'il se
/// coupe. `HighlightedText.attribue(_:terme:)` est pure et testée, ce que la
/// concaténation de vues n'aurait pas permis.
struct HighlightedText: View {

    let texte: String
    let terme: String
    var fonte: Font = .plexSans(13.5)
    var encre: Color = One2OneToken.ink1

    var body: some View {
        Text(Self.attribue(texte, terme: terme))
            .font(fonte)
            .foregroundStyle(encre)
    }

    /// Le texte, avec le fond `highlight` sur chaque occurrence du terme.
    ///
    /// Les décalages sont comptés en **caractères**, l'unité que partagent
    /// `String` et `AttributedString` : compter en octets ou en unités UTF-16
    /// décalerait le surlignage dès le premier accent, et les noms de projet
    /// en portent.
    ///
    /// Les bornes sont vérifiées avant l'appel à `index(_:offsetByCharacters:)`,
    /// qui **piège** hors plage et n'a pas de variante `limitedBy:`. Elles
    /// viennent de la même chaîne, donc le cas ne se produit pas ; un
    /// surlignage silencieusement omis reste préférable à un arrêt brutal.
    static func attribue(_ texte: String, terme: String) -> AttributedString {
        var attribue = AttributedString(texte)
        for plage in ProjectSearch.highlightRanges(in: texte, query: terme) {
            let depart = texte.distance(from: texte.startIndex, to: plage.lowerBound)
            let arrivee = texte.distance(from: texte.startIndex, to: plage.upperBound)
            let total = attribue.characters.count
            guard depart >= 0, arrivee <= total, depart < arrivee else { continue }
            let debut = attribue.index(attribue.startIndex, offsetByCharacters: depart)
            let fin = attribue.index(attribue.startIndex, offsetByCharacters: arrivee)
            attribue[debut..<fin].backgroundColor = One2OneToken.highlight
        }
        return attribue
    }
}

#Preview("HighlightedText") {
    VStack(alignment: .leading, spacing: 8) {
        HighlightedText(texte: "ASP – Installation nouvelle GED", terme: "ged")
        HighlightedText(texte: "RH – Migration GED documentaire", terme: "ged")
        HighlightedText(texte: "Refonte des états réglementaires", terme: "etats")
        HighlightedText(texte: "Aucune occurrence ici", terme: "ged")
    }
    .padding(20)
    .background(One2OneToken.surface)
}
