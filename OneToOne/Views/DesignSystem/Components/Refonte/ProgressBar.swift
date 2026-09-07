import SwiftUI

/// Barre de progression fine des cartes KPI (capture 1a, carte ACTIONS).
/// 4 px de haut, rayon plein, portion faite en `accent/ok` par défaut.
struct ProgressBar: View {
    let valeur: Double
    let teinte: Color
    @Environment(\.one2OneTheme) private var theme

    init(valeur: Double, teinte: Color = One2OneToken.ok) {
        self.valeur = valeur
        self.teinte = teinte
    }

    /// Borne une progression à 0…1.
    ///
    /// `nan` vaut 0 : « 3 actions closes sur 0 action » est un rapport
    /// indéfini, et une largeur `nan` fait disparaître la barre sans rien dire.
    static func clamp(_ valeur: Double) -> Double {
        guard !valeur.isNaN else { return 0 }
        return min(max(valeur, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.hair)
                Capsule()
                    .fill(teinte)
                    .frame(width: geo.size.width * Self.clamp(valeur))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Progression")
        .accessibilityValue("\(Int(Self.clamp(valeur) * 100)) %")
    }
}

#Preview("ProgressBar — papier") {
    VStack(spacing: 14) {
        ProgressBar(valeur: 0)
        ProgressBar(valeur: 0.25)
        ProgressBar(valeur: 0.6, teinte: One2OneToken.warn)
        ProgressBar(valeur: 1)
    }
    .frame(width: 240)
    .padding(20)
    .background(One2OneToken.surface)
}

#Preview("ProgressBar — séance") {
    VStack(spacing: 14) {
        ProgressBar(valeur: 0.4, teinte: One2OneToken.darkAction)
        ProgressBar(valeur: 0.8, teinte: One2OneToken.darkWarn)
    }
    .frame(width: 240)
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
