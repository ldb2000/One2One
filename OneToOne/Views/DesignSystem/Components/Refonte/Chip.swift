import SwiftUI

/// Ton d'une chip ou d'une pilule : le couple encre/fond que la spec §1.2
/// associe à chaque accent.
///
/// Chaque couple atteint 4,5:1 (les chips font 10–10,5 px, donc sous le seuil
/// de 12 px), à une exception près que la table impose : `ok` mesure 4,43:1,
/// faute d'encre `accent/ok` plus profonde. Cf.
/// `One2OneTokensTests.okDeepOnOkBackgroundIsJustBelowThreshold`.
enum ChipTon: CaseIterable, Sendable {
    case neutre
    case action
    case report
    case ok
    case warn
    case oneOnOne
    case workshop

    var encre: Color { encre(.paper) }

    var fond: Color { fond(.paper) }

    /// L'encre dans un thème donné.
    ///
    /// Le mode séance du lot 4 affiche les mêmes chips (`/action`, `/décision`,
    /// `/risque`, `/citer` du composeur de notes) sur `#1c1a17` : les couples
    /// encre/fond de la palette claire y sont illisibles. En `.paper`, les
    /// valeurs résolues sont **exactement** celles d'avant — le rendu clair ne
    /// change pas (cf. `One2OneThemeTests`).
    func encre(_ theme: One2OneTheme) -> Color {
        let c = theme.colors
        switch self {
        case .neutre: return c.ink3
        case .action: return c.actionInk
        case .report: return c.reportInk
        case .ok: return theme == .paper ? One2OneToken.okDeep : c.ok
        case .warn: return c.warnInk
        case .oneOnOne: return theme == .paper ? One2OneToken.oneOnOneInk : c.ink2
        case .workshop: return theme == .paper ? One2OneToken.workshop : c.ink2
        }
    }

    /// Le fond dans un thème donné.
    ///
    /// La palette `dark/*` ne publie pas de fond doux par accent : sur fond
    /// sombre, une chip se distingue par sa **pilule** (`dark/pill`) et par
    /// son encre, pas par sept fonds teintés qui, à 7 % d'opacité près,
    /// seraient tous le même gris.
    func fond(_ theme: One2OneTheme) -> Color {
        guard theme == .paper else { return theme.colors.pill }
        switch self {
        case .neutre: return One2OneToken.surfaceAlt
        case .action: return One2OneToken.actionBg
        case .report: return One2OneToken.reportBg
        case .ok: return One2OneToken.okBg
        case .warn: return One2OneToken.warnBg
        case .oneOnOne: return One2OneToken.oneOnOneBg
        case .workshop: return One2OneToken.workshopBg
        }
    }
}

/// Chip : étiquette courte à angles peu arrondis (rayon 5–6, spec §1.2). Sert
/// aux thèmes, aux familles de sujets récurrents et aux commandes `/action`
/// affichées en permanence sous le composeur de notes.
struct Chip: View {
    let texte: String
    let ton: ChipTon
    @Environment(\.one2OneTheme) private var theme

    init(_ texte: String, ton: ChipTon = .neutre) {
        self.texte = texte
        self.ton = ton
    }

    var body: some View {
        Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(ton.encre(theme))
            // Une chip tient sur **une** ligne (spec §1.2 : « Pilule / chip …
            // rayon 11 px, padding 2–3 × 7–8 »). Sans cela, une chip posée
            // dans une colonne étroite ou dans une grille adaptative se replie
            // au milieu d'un mot — la recette du lot 9 l'a vu sur
            // « PostgreS / QL », celle de la vague 1–4 sur « / décisio / n ».
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ton.fond(theme))
            )
    }
}

#Preview("Chip") {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
            Chip("migration")
            Chip("budget")
            Chip("2h", ton: .neutre)
        }
        HStack(spacing: 6) {
            Chip("/action", ton: .action)
            Chip("/décision", ton: .report)
            Chip("/risque", ton: .warn)
            Chip("/citer")
        }
        HStack(spacing: 6) {
            Chip("tenu", ton: .ok)
            Chip("charge", ton: .oneOnOne)
            Chip("atelier", ton: .workshop)
        }
    }
    .padding(20)
    .background(One2OneToken.surface)
}
