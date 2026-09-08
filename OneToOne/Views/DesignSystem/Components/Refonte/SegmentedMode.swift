import SwiftUI

/// Sélecteur segmenté de la refonte : `Préparer / En séance / Relire`,
/// `Liste / Calendrier / Eisenhower`. Le segment actif est **plein `ink/1`**
/// avec un texte inversé (capture 1a), les autres sont transparents.
///
/// Générique sur la valeur : le sélecteur de mode temporel, celui des vues du
/// rail d'actions et ceux des lots suivants sont le même composant.
struct SegmentedMode<Valeur: Hashable>: View {
    @Binding var selection: Valeur
    let options: [Valeur]
    let libelle: (Valeur) -> String
    /// Taille du libellé. Par défaut la **pilule** de §1.2 (10 → 10,5 px), qui
    /// est ce que sont les sélecteurs internes à un panneau — filtre du tiroir
    /// Ressources, vues du tableau d'actions.
    ///
    /// La barre d'espaces demande 11,5 → 12 px : `Préparer / En séance / Relire`
    /// n'y est pas un filtre mais le **mode de l'écran**, et la capture
    /// `1a-cockpit.png` le montre à la taille d'un titre de carte. Rendu à
    /// 10,5 px, il se lisait comme un réglage secondaire (retour d'usage du
    /// 2026-09-08).
    let taille: CGFloat
    @Environment(\.one2OneTheme) private var theme

    init(selection: Binding<Valeur>,
         options: [Valeur],
         taille: CGFloat = 10.5,
         libelle: @escaping (Valeur) -> String) {
        self._selection = selection
        self.options = options
        self.taille = taille
        self.libelle = libelle
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let actif = option == selection
                Button {
                    selection = option
                } label: {
                    Text(libelle(option))
                        .font(.plexSans(taille, .medium))
                        .foregroundStyle(actif ? theme.colors.card : theme.colors.ink3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                                .fill(actif ? theme.colors.ink1 : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
    }
}

#Preview("SegmentedMode") {
    struct Apercu: View {
        @State private var mode = "En séance"
        @State private var vue = "Liste"
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedMode(selection: $mode,
                              options: ["Préparer", "En séance", "Relire"],
                              libelle: { $0 })
                SegmentedMode(selection: $vue,
                              options: ["Liste", "Calendrier", "Eisenhower"],
                              libelle: { $0 })
            }
            .padding(20)
            .background(One2OneToken.bgApp)
        }
    }
    return Apercu()
}
