import SwiftUI

/// Le badge de risque du tableau du Portfolio (capture `1a-portfolio.png`).
///
/// **Deux accents, pas quatre** (décision **D2**, validée le 2026-09-09) :
/// `report` pour ce qui alerte (Élevé, Critique), `warn` pour ce qui se
/// surveille (Modéré). « Faible » n'est pas un accent mais un neutre, `ink4` —
/// le handoff proposait `okBg`/`okDeep`, et D2 ne rouvre pas une décision de
/// la refonte réunion (`MeetingKPI.Level.teinte`, table unique) pour un badge
/// que la capture 1a ne montre même pas. Un risque absent est un tiret.
struct RiskBadge: View {

    /// Même mesure que le badge de phase (handoff §1a).
    static let taille = PhaseBadge.taille

    let risk: RiskLevel?

    var body: some View {
        if let risk {
            Text(risk.label)
                .font(.plexSans(Self.taille, .medium))
                .foregroundStyle(Self.encre(risk))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                        .fill(Self.fond(risk))
                )
        } else {
            Text("—")
                .font(.plexSans(Self.taille))
                .foregroundStyle(One2OneToken.inkMuted)
        }
    }

    /// Le fond du badge. `surfaceAlt` pour « Faible » : la table unique de D2
    /// n'a pas de vert, et un fond neutre est ce qui reste cohérent avec une
    /// encre neutre.
    static func fond(_ risk: RiskLevel) -> Color {
        switch risk {
        case .faible:            return One2OneToken.surfaceAlt
        case .modere:            return One2OneToken.warnBg
        case .eleve, .critique:  return One2OneToken.reportBg
        }
    }

    /// L'encre du badge : la version foncée de l'accent que la table unique
    /// donne au niveau. `ink4` pour « Faible », qui n'a pas d'accent — donc
    /// pas de version foncée.
    static func encre(_ risk: RiskLevel) -> Color {
        switch risk {
        case .faible:            return One2OneToken.ink4
        case .modere:            return One2OneToken.warnInk
        case .eleve, .critique:  return One2OneToken.reportInk
        }
    }

    /// La teinte pleine du niveau, **lue dans la table unique**
    /// (`MeetingKPI.Level.teinte`, `RiskLevelTint.swift`) : elle sert au bord
    /// de la chip « Risque ≥ Modéré » de la barre de filtres, que la capture
    /// montre teintée.
    ///
    /// Passer par `MeetingKPI.Level` et non recopier les trois lignes : D2 dit
    /// « table de risque unique », et deux tables qui divergent feraient un
    /// badge d'une couleur et une chip d'une autre.
    static func teinte(_ risk: RiskLevel) -> Color {
        niveau(risk).teinte
    }

    /// La correspondance entre le niveau de risque d'un projet et le niveau
    /// d'indicateur de la refonte réunion. Les quatre cas portent les mêmes
    /// noms ; l'`enum` est simplement déclaré ailleurs.
    static func niveau(_ risk: RiskLevel) -> MeetingKPI.Level {
        switch risk {
        case .faible:   return .faible
        case .modere:   return .modere
        case .eleve:    return .eleve
        case .critique: return .critique
        }
    }
}

#Preview("RiskBadge") {
    HStack(spacing: 8) {
        ForEach(RiskLevel.allCases, id: \.self) { RiskBadge(risk: $0) }
        RiskBadge(risk: nil)
    }
    .padding(20)
    .background(One2OneToken.bgApp)
}
