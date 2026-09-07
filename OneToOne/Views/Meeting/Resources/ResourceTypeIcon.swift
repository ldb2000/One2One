import SwiftUI

/// L'icône typée d'une vignette du tiroir : 34 × 40, fond dédié par famille,
/// trois lettres au centre (spec §4.1, capture `3a-tiroir-ressources.png` —
/// `XLS` sur vert, `PNG` sur gris, `PDF` sur rose, `URL` sur bleu).
///
/// Un rectangle de proportion feuille A4, et non un symbole SF : c'est ce qui
/// permet de reconnaître un type d'un coup d'œil dans une colonne de 396 px,
/// là où douze glyphes gris se confondent. Le texte porte l'information, la
/// couleur la confirme — jamais l'inverse (une palette seule serait illisible
/// pour un daltonien).
struct ResourceTypeIcon: View {

    /// Largeur et hauteur imposées par la spec §4.1.
    static let width: CGFloat = 34
    static let height: CGFloat = 40

    let badge: String
    let tone: AttachmentCopyPolicy.BadgeTone
    /// La pièce est orpheline : l'icône le dit, sans attendre que l'utilisateur
    /// clique pour découvrir que le fichier a disparu.
    var isOrphan: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
            .fill(isOrphan ? One2OneToken.surfaceAlt : Self.background(tone))
            .frame(width: Self.width, height: Self.height)
            .overlay {
                RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                    .strokeBorder(isOrphan ? One2OneToken.strongBorder : Self.ink(tone).opacity(0.18),
                                  lineWidth: 1)
            }
            .overlay {
                if isOrphan {
                    Image(systemName: "questionmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(One2OneToken.ink4)
                } else {
                    Text(badge)
                        .font(.plexMono(8.5, .semibold))
                        .tracking(8.5 * 0.04)
                        .foregroundStyle(Self.ink(tone))
                }
            }
            .accessibilityLabel(isOrphan ? "Fichier introuvable" : badge)
    }

    /// Les cinq fonds. **Aucune couleur n'est nommée ici** : la table de
    /// `One2OneTokens` reste la seule (programme §7), et les cinq familles se
    /// servent des accents existants — vert pour un tableur, rose pour un
    /// document, bleu pour un lien, orange pour une présentation, gris neutre
    /// pour une image.
    static func background(_ tone: AttachmentCopyPolicy.BadgeTone) -> Color {
        switch tone {
        case .tableur:      One2OneToken.okBg
        case .image:        One2OneToken.surfaceAlt
        case .document:     One2OneToken.reportBg
        case .lien:         One2OneToken.actionBg
        case .presentation: One2OneToken.warnBg
        }
    }

    static func ink(_ tone: AttachmentCopyPolicy.BadgeTone) -> Color {
        switch tone {
        case .tableur:      One2OneToken.okDeep
        case .image:        One2OneToken.ink3
        case .document:     One2OneToken.reportInk
        case .lien:         One2OneToken.actionInk
        case .presentation: One2OneToken.warnInk
        }
    }
}

#Preview("Icônes typées") {
    HStack(spacing: 10) {
        ResourceTypeIcon(badge: "XLS", tone: .tableur)
        ResourceTypeIcon(badge: "PNG", tone: .image)
        ResourceTypeIcon(badge: "PDF", tone: .document)
        ResourceTypeIcon(badge: "URL", tone: .lien)
        ResourceTypeIcon(badge: "PPT", tone: .presentation)
        ResourceTypeIcon(badge: "DOC", tone: .document, isOrphan: true)
    }
    .padding(20)
    .background(One2OneToken.surface)
}
