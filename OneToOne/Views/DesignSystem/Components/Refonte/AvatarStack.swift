import SwiftUI

/// Pile d'avatars de la refonte : pastilles de 19 px, chevauchement de −6 px,
/// six au maximum puis un `+n` (spec §1.2 et capture 1a).
///
/// Seule pile d'avatars de l'application depuis le lot 19 : `MeetingAvatarStack`,
/// qui servait les écrans non refondus avec sa propre géométrie, est partie avec
/// le dashboard, son dernier hôte. Les pastilles unitaires (`AvatarCircle`,
/// `AvatarMini`) restent, elles, employées par les écrans hors refonte.
struct AvatarStack: View {

    static let diametre: CGFloat = 19
    /// Espacement horizontal entre pastilles. Négatif : elles se chevauchent.
    static let chevauchement: CGFloat = -6

    let noms: [String]
    let maxVisibles: Int
    /// Comment abréger un nom en pastille. Par défaut `Avatar.initiales(de:)`,
    /// qui prend la première lettre du premier mot et celle du dernier
    /// (« Pierre-Yves Nallet » → `PN`).
    ///
    /// Le bandeau d'indicateurs passe `MeetingKPIBuilder.initials`, qui traite
    /// le tiret comme un séparateur de mots (« Pierre-Yves Nallet » → `PY`) :
    /// c'est ce que montre la capture `1a-cockpit.png`, et une pastille d'une
    /// seule lettre y est illisible. Les deux règles coexistent plutôt que
    /// l'une n'écrase l'autre, parce que les écrans non refondus emploient
    /// `Avatar` partout ailleurs.
    let initiales: (String) -> String
    @Environment(\.one2OneTheme) private var theme

    init(noms: [String],
         maxVisibles: Int = 6,
         initiales: @escaping (String) -> String = Avatar.initiales(de:)) {
        self.noms = noms
        self.maxVisibles = maxVisibles
        self.initiales = initiales
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
                pastille(initiales(nom), aide: nom)
            }
            if mise.surplus > 0 {
                pastille("+\(mise.surplus)", aide: "\(mise.surplus) participants de plus")
            }
        }
    }

    /// Une pastille.
    ///
    /// Le fond est `base` et **non** `pill` : en thème `.paper`, `pill` résout
    /// vers `surface` (`#ffffff`), c'est-à-dire exactement le fond de la carte
    /// Présence — les six pastilles y étaient invisibles et ne restaient que
    /// six paires d'initiales flottantes (recette visuelle de la vague 1–4 sur
    /// `1a-cockpit.png`). `base` (`bg/app`, `#f7f4ee`) est le seul jeton neutre
    /// qui se détache de `surface`, et il se détache aussi de `dark/card` en
    /// thème `.session`. L'anneau reste `card` : c'est lui qui sépare deux
    /// pastilles chevauchées.
    private func pastille(_ texte: String, aide: String) -> some View {
        Text(texte)
            .font(.plexSans(8.5, .semibold))
            .foregroundStyle(theme.colors.ink3)
            .frame(width: Self.diametre, height: Self.diametre)
            .background(Circle().fill(theme.colors.base))
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
