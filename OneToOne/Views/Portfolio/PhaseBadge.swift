import SwiftUI

/// Le badge de phase du tableau du Portfolio (capture `1a-portfolio.png`).
///
/// Les quatre couples du handoff, et **un cinquième pour ce que la table ne
/// connaît pas** : `Project.phase` reste une `String` libre (décision **D14**)
/// et le store contient « Réalisation ». Une valeur hors table s'affiche en
/// neutre — `ink4` sur `surfaceAlt` — plutôt que de disparaître ou de prendre
/// la teinte d'une phase qu'elle n'est pas.
struct PhaseBadge: View {

    /// Taille du libellé, handoff §1a : « Radius 4, 11,5 pt ».
    static let taille: CGFloat = 11.5

    /// La phase connue, ou `nil`.
    let phase: ProjectPhase?
    /// La valeur persistée, affichée telle quelle quand elle est hors table.
    let brute: String

    var body: some View {
        // Une phase vide n'a pas de badge : la colonne reste blanche, comme
        // pour une entité absente.
        if libelle.isEmpty {
            Text("—")
                .font(.plexSans(Self.taille))
                .foregroundStyle(One2OneToken.inkMuted)
        } else {
            Text(libelle)
                .font(.plexSans(Self.taille, .medium))
                .foregroundStyle(Self.encre(phase))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                        .fill(Self.fond(phase))
                )
        }
    }

    private var libelle: String {
        phase?.label ?? brute.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le fond du badge — les quatre couples du handoff, `surfaceAlt` hors
    /// table.
    static func fond(_ phase: ProjectPhase?) -> Color {
        switch phase {
        case .cadrage?: return One2OneToken.actionBg
        case .design?:  return One2OneToken.oneOnOneBg
        case .build?:   return One2OneToken.workshopBg
        case .run?:     return One2OneToken.okBg
        case nil:       return One2OneToken.surfaceAlt
        }
    }

    /// L'encre du badge. Chaque accent a sa version foncée, sauf `workshop`,
    /// dont le jeton de base est déjà l'encre (`#1F6B6B`) — c'est ce que dit le
    /// handoff (« Build `workshopBg` / `workshop` »).
    static func encre(_ phase: ProjectPhase?) -> Color {
        switch phase {
        case .cadrage?: return One2OneToken.actionInk
        case .design?:  return One2OneToken.oneOnOneInk
        case .build?:   return One2OneToken.workshop
        case .run?:     return One2OneToken.okDeep
        case nil:       return One2OneToken.ink4
        }
    }
}

#Preview("PhaseBadge") {
    HStack(spacing: 8) {
        ForEach(ProjectPhase.allCases, id: \.self) { phase in
            PhaseBadge(phase: phase, brute: phase.label)
        }
        PhaseBadge(phase: nil, brute: "Réalisation")
        PhaseBadge(phase: nil, brute: "")
    }
    .padding(20)
    .background(One2OneToken.bgApp)
}
