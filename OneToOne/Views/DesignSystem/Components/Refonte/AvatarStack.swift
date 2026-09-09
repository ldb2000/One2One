import SwiftUI

/// Pile d'avatars de la refonte : pastilles de 19 px, chevauchement de −6 px,
/// six au maximum puis un `+n` (spec §1.2 et capture 1a).
///
/// Seule pile d'avatars de l'application depuis le lot 19 : `MeetingAvatarStack`,
/// qui servait les écrans non refondus avec sa propre géométrie, est partie avec
/// le dashboard, son dernier hôte. Les pastilles unitaires (`AvatarCircle`,
/// `AvatarMini`) restent, elles, employées par les écrans hors refonte.
struct AvatarStack: View {

    /// Diamètre par défaut, spec §1.2 : les pastilles du bandeau et de la
    /// carte Présence.
    static let diametre: CGFloat = 19
    /// Diamètre de la carte « INTERLOCUTEURS » de l'écran projet (handoff
    /// §1d, décision **D12**).
    static let diametreProjet: CGFloat = 26
    /// Espacement horizontal entre pastilles, **à 19 pt**. Négatif : elles se
    /// chevauchent. `chevauchement(pour:)` l'échelonne pour les autres
    /// tailles, sinon deux pastilles de 26 pt se toucheraient à peine.
    static let chevauchement: CGFloat = -6

    /// Le chevauchement d'un diamètre donné, proportionnel à celui de §1.2.
    static func chevauchement(pour diametre: CGFloat) -> CGFloat {
        chevauchement * diametre / Self.diametre
    }

    let noms: [String]
    let maxVisibles: Int
    /// Diamètre des pastilles. La conception en emploie deux : 19 pt partout,
    /// 26 pt sur l'écran projet.
    let diametre: CGFloat
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
         diametre: CGFloat = AvatarStack.diametre,
         initiales: @escaping (String) -> String = Avatar.initiales(de:)) {
        self.noms = noms
        self.maxVisibles = maxVisibles
        self.diametre = diametre
        self.initiales = initiales
    }

    /// La taille des initiales, proportionnelle au diamètre : 8,5 pt à 19 pt,
    /// donc 11,6 pt à 26 pt. Un glyphe de 8,5 pt dans un disque de 26 flotte.
    static func tailleDesInitiales(_ diametre: CGFloat) -> CGFloat {
        8.5 * diametre / Self.diametre
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
        let derniere = mise.visibles.count - 1
        HStack(spacing: Self.chevauchement(pour: diametre)) {
            ForEach(Array(mise.visibles.enumerated()), id: \.offset) { index, nom in
                // Couverte dès qu'une pastille la suit — la suivante, ou le
                // `+n`.
                pastille(initiales(nom), aide: nom,
                         couverte: index < derniere || mise.surplus > 0)
            }
            if mise.surplus > 0 {
                pastille("+\(mise.surplus)", aide: "\(mise.surplus) participants de plus",
                         couverte: false)
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
    /// `couverte` : une autre pastille chevauche son bord droit de 6 px.
    ///
    /// Les initiales sont alors centrées dans la **partie visible** et non
    /// dans le disque entier. Sans cela, deux lettres de 8,5 px semi-gras
    /// mesurent une douzaine de pixels centrés dans 19, donc s'étendent
    /// jusqu'au bord droit — que la pastille suivante recouvre : la recette
    /// finale lisait « C̸A CF LC LS NL PY » là où le semis dit
    /// « CA CF LD LS NL PY », la seconde lettre de chaque paire mangée par le
    /// disque voisin. La géométrie de §1.2 (19 px, chevauchement −6) est
    /// inchangée ; c'est le glyphe qui se recentre.
    private func pastille(_ texte: String, aide: String, couverte: Bool) -> some View {
        Text(texte)
            .font(.plexSans(Self.tailleDesInitiales(diametre), .semibold))
            .foregroundStyle(theme.colors.ink3)
            .lineLimit(1)
            .fixedSize()
            .frame(width: diametre + Self.chevauchement(pour: diametre), height: diametre)
            .frame(width: diametre, height: diametre,
                   alignment: couverte ? .leading : .center)
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
