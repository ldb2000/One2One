import SwiftUI

/// Timecode d'un élément horodaté : `mm:ss`, Plex Mono 500 à 10 px, **largeur
/// fixe** (spec §1.2).
///
/// La largeur est figée et non calculée : une colonne de timecodes dont la
/// largeur varie d'une ligne à l'autre décale tout le texte à sa droite, et
/// c'est justement ce que la conception évite en imposant `mm:ss` même au-delà
/// d'une heure.
struct TimecodeLabel: View {

    /// Largeur réservée : cinq caractères de Plex Mono à 10 px.
    static let width: CGFloat = 34

    let seconds: Double
    /// Teinte de l'accent quand le timecode est celui d'une décision ou d'un
    /// élément mis en avant. `nil` = encre de libellé mono du thème.
    let teinte: Color?
    @Environment(\.one2OneTheme) private var theme

    init(seconds: Double, teinte: Color? = nil) {
        self.seconds = seconds
        self.teinte = teinte
    }

    /// `mm:ss` depuis un nombre de secondes.
    ///
    /// Les minutes débordent au-delà de 59 (« toujours mm:ss ») ; les valeurs
    /// négatives ou non finies se lisent `00:00` ; les fractions sont
    /// tronquées, jamais arrondies — un timecode arrondi vers le haut désigne
    /// un instant que la tête de lecture n'a pas encore atteint.
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        Text(Self.format(seconds))
            .font(.plexMono(10, .medium))
            .monospacedDigit()
            .foregroundStyle(teinte ?? theme.colors.ink4)
            .frame(width: Self.width, alignment: .leading)
    }
}

#Preview("TimecodeLabel — papier") {
    VStack(alignment: .leading, spacing: 6) {
        TimecodeLabel(seconds: 0)
        TimecodeLabel(seconds: 252, teinte: One2OneToken.action)
        TimecodeLabel(seconds: 663, teinte: One2OneToken.report)
        TimecodeLabel(seconds: 920)
        TimecodeLabel(seconds: 3723)
    }
    .padding(20)
    .background(One2OneToken.surface)
}

#Preview("TimecodeLabel — séance") {
    VStack(alignment: .leading, spacing: 6) {
        TimecodeLabel(seconds: 252)
        TimecodeLabel(seconds: 663, teinte: One2OneToken.darkReport)
        TimecodeLabel(seconds: 1122, teinte: One2OneToken.darkAction)
    }
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
