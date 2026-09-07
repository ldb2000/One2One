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

    var encre: Color {
        switch self {
        case .neutre: One2OneToken.ink3
        case .action: One2OneToken.actionInk
        case .report: One2OneToken.reportInk
        case .ok: One2OneToken.okDeep
        case .warn: One2OneToken.warnInk
        case .oneOnOne: One2OneToken.oneOnOneInk
        case .workshop: One2OneToken.workshop
        }
    }

    var fond: Color {
        switch self {
        case .neutre: One2OneToken.surfaceAlt
        case .action: One2OneToken.actionBg
        case .report: One2OneToken.reportBg
        case .ok: One2OneToken.okBg
        case .warn: One2OneToken.warnBg
        case .oneOnOne: One2OneToken.oneOnOneBg
        case .workshop: One2OneToken.workshopBg
        }
    }
}

/// Chip : étiquette courte à angles peu arrondis (rayon 5–6, spec §1.2). Sert
/// aux thèmes, aux familles de sujets récurrents et aux commandes `/action`
/// affichées en permanence sous le composeur de notes.
struct Chip: View {
    let texte: String
    let ton: ChipTon

    init(_ texte: String, ton: ChipTon = .neutre) {
        self.texte = texte
        self.ton = ton
    }

    var body: some View {
        Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(ton.encre)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ton.fond)
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
