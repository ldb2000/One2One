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
    @Environment(\.one2OneTheme) private var theme

    init(selection: Binding<Valeur>, options: [Valeur], libelle: @escaping (Valeur) -> String) {
        self._selection = selection
        self.options = options
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
                        .font(.plexSans(10.5, .medium))
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
