import SwiftUI

/// Pile d'avatars de la refonte : pastilles de 19 px, chevauchement de −6 px,
/// six au maximum puis un `+n` (spec §1.2 et capture 1a).
///
/// Distincte de `MeetingAvatarStack`, qui sert les écrans non refondus avec sa
/// propre géométrie : ce lot ne remplace pas l'existant.
struct AvatarStack: View {

    static let diametre: CGFloat = 19
    /// Espacement horizontal entre pastilles. Négatif : elles se chevauchent.
    static let chevauchement: CGFloat = -6

    let noms: [String]
    let maxVisibles: Int
    @Environment(\.one2OneTheme) private var theme

    init(noms: [String], maxVisibles: Int = 6) {
        self.noms = noms
        self.maxVisibles = maxVisibles
    }

    /// Répartition entre pastilles affichées et surplus compté.
    ///
    /// Fonction pure, testée : c'est elle qui porte la règle « max 6 puis +n »,
    /// et une pile de 6 exactement ne doit **pas** afficher « +0 ».
    static func layout(noms: [String], maxVisibles: Int) -> (visibles: [String], surplus: Int) {
        guard maxVisibles > 0 else { return ([], noms.count) }
        guard noms.count > maxVisibles else { return (noms, 0) }
        return (Array(noms.prefix(maxVisibles)), noms.count - maxVisibles)
    }

    var body: some View {
        let mise = Self.layout(noms: noms, maxVisibles: maxVisibles)
        HStack(spacing: Self.chevauchement) {
            ForEach(Array(mise.visibles.enumerated()), id: \.offset) { _, nom in
                pastille(Avatar.initiales(de: nom), aide: nom)
            }
            if mise.surplus > 0 {
                pastille("+\(mise.surplus)", aide: "\(mise.surplus) participants de plus")
            }
        }
    }

    private func pastille(_ texte: String, aide: String) -> some View {
        Text(texte)
            .font(.plexSans(8.5, .semibold))
            .foregroundStyle(theme.colors.ink3)
            .frame(width: Self.diametre, height: Self.diametre)
            .background(Circle().fill(theme.colors.pill))
            .overlay(Circle().strokeBorder(theme.colors.card, lineWidth: 1.5))
            .help(aide)
    }
}

#Preview("AvatarStack — papier") {
    VStack(alignment: .leading, spacing: 12) {
        AvatarStack(noms: ["Patrice Y", "Nicolas L", "Claire-Amélie P"])
        AvatarStack(noms: ["Patrice Y", "Nicolas L", "Claire-Amélie P",
                           "Laurent S", "Camille A", "Loïc D"])
        AvatarStack(noms: (1...9).map { "Participant \($0)" })
    }
    .padding(20)
    .background(One2OneToken.surface)
}

#Preview("AvatarStack — séance") {
    AvatarStack(noms: ["Patrice Y", "Nicolas L", "Claire-Amélie P",
                       "Laurent S", "Camille A", "Loïc D"])
        .padding(20)
        .background(One2OneToken.darkBase)
        .one2OneTheme(.session)
}
