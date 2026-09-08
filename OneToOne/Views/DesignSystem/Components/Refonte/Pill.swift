import SwiftUI

/// Pilule : étiquette courte à bords ronds (rayon 11, padding 2–3 × 7–8,
/// Plex Sans 500 à 10–10,5 px — spec §1.2). Sert aux états (`● Privé — vous
/// deux`, `● Capture · Teams 4`), aux badges de type et aux compteurs.
///
/// `bordee` ajoute le contour que les captures montrent sur les pilules d'état
/// actif (`● Partage actif`) plutôt qu'un fond plein seul.
struct Pill: View {
    let texte: String
    let ton: ChipTon
    let bordee: Bool

    init(_ texte: String, ton: ChipTon = .neutre, bordee: Bool = false) {
        self.texte = texte
        self.ton = ton
        self.bordee = bordee
    }

    var body: some View {
        Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(ton.encre)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(ton.fond))
            .overlay {
                if bordee {
                    Capsule(style: .continuous)
                        .strokeBorder(ton.encre.opacity(0.35), lineWidth: 1)
                }
            }
    }
}

#Preview("Pill") {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
            Pill("Global")
            Pill("Projet", ton: .action)
            Pill("Rapport ✓", ton: .report)
            Pill("Atelier", ton: .workshop)
        }
        HStack(spacing: 6) {
            Pill("● Privé — vous deux", ton: .oneOnOne, bordee: true)
            Pill("● Capture · Teams 4", ton: .ok, bordee: true)
            Pill("Source perdue", ton: .warn, bordee: true)
        }
    }
    .padding(20)
    .background(One2OneToken.bgApp)
}
