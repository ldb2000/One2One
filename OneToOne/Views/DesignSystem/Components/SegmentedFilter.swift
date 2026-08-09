import SwiftUI

/// Filtres en pilules à compteur intégré, comme « En retard 7 » de la capture 3.
/// L'option active est une pilule noire pleine ; les autres, un contour fin.
public struct SegmentedFilter<Option: Hashable>: View {

    public let options: [Option]
    @Binding public var selection: Option
    public let libelle: (Option) -> String
    public let compteur: (Option) -> Int

    public init(options: [Option],
                selection: Binding<Option>,
                libelle: @escaping (Option) -> String,
                compteur: @escaping (Option) -> Int) {
        self.options = options
        self._selection = selection
        self.libelle = libelle
        self.compteur = compteur
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let actif = option == selection
                Button { selection = option } label: {
                    HStack(spacing: 6) {
                        Text(libelle(option))
                        Text("\(compteur(option))")
                            .foregroundStyle(actif ? .white.opacity(0.7) : AppTheme.texteSecondaire)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(actif ? Color.white : AppTheme.textePrincipal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.rayonPilule)
                            .fill(actif ? Color.black : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.rayonPilule)
                            .stroke(actif ? Color.clear : AppTheme.separateur, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
