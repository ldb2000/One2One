import SwiftUI

/// Le badge de type d'une réunion, tel que la carte « DERNIÈRES RÉUNIONS » de
/// la capture `1d-ecran-projet-pilotage.png` le dessine : un rectangle de
/// rayon 4, 11 pt medium, marges 6/1.
///
/// La **règle** est dans `MeetingTypeBadge` (`Services/Project/`, décision
/// **D10**) ; ce fichier ne porte que les trois couples de teintes du handoff
/// §1d, séparés en table statique pour qu'un test les lise sans monter de vue.
struct MeetingTypeBadgeView: View {

    /// Taille du libellé (handoff §1d).
    static let taille: CGFloat = 11

    let badge: MeetingTypeBadge

    var body: some View {
        Text(badge.libelle)
            .font(.plexSans(Self.taille, .medium))
            .foregroundStyle(Self.encre(badge))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                    .fill(Self.fond(badge))
            )
            .fixedSize()
    }

    /// Le fond : `reportBg` pour un COPIL, `workshopBg` pour un atelier,
    /// `oneOnOneBg` pour un 1:1 (handoff §1d).
    static func fond(_ badge: MeetingTypeBadge) -> Color {
        switch badge {
        case .copil:    return One2OneToken.reportBg
        case .atelier:  return One2OneToken.workshopBg
        case .oneOnOne: return One2OneToken.oneOnOneBg
        }
    }

    /// L'encre : la version foncée de chaque accent. `workshop` est déjà
    /// l'encre — son jeton de base vaut `#1F6B6B` —, comme sur `PhaseBadge`.
    static func encre(_ badge: MeetingTypeBadge) -> Color {
        switch badge {
        case .copil:    return One2OneToken.reportInk
        case .atelier:  return One2OneToken.workshop
        case .oneOnOne: return One2OneToken.oneOnOneInk
        }
    }
}

#Preview("MeetingTypeBadgeView") {
    HStack(spacing: 8) {
        ForEach(MeetingTypeBadge.allCases, id: \.self) { MeetingTypeBadgeView(badge: $0) }
    }
    .padding(20)
    .background(One2OneToken.surface)
}
