import SwiftUI

/// L'en-tête violet pâle de la préparation du 1:1 subi (capture 5b) : avatar,
/// `1:1 avec Yann — demain 14:00`,
/// `Préparation · 2 min · dernier point le 21 août`, badge `Collaborateur`.
///
/// Même parti que `PrepHeader` au lot 12 — un bandeau collé en tête de la
/// carte, pas une carte de plus — mais **sans bouton** : la préparation d'un
/// entretien subi ne démarre pas l'entretien, c'est mon manager qui l'ouvre.
/// Le seul geste de cet écran est en pied, et c'est de porter mes sujets.
struct CollabPrepHeader: View {

    /// Deux lignes de texte, un avatar de 34 px, la respiration de la capture.
    static let height: CGFloat = 62
    static let avatarSize: CGFloat = 34

    let model: CollabPrepHeaderModel

    var body: some View {
        HStack(spacing: 11) {
            AvatarSide(initials: model.initials,
                       identity: model.identity,
                       diametre: Self.avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.plexSans(14, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Text(model.meta)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink3)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)
            badgeRole
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(One2OneToken.oneOnOneBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// Le badge **bordé** de la capture, et non une pilule pleine : sur
    /// l'en-tête, qui est déjà `oneOnOneBg`, un fond doux serait invisible, et
    /// un violet plein le ferait passer pour un bouton — alors qu'il ne dit
    /// qu'une chose, la seule qui compte : dans cet entretien, je ne mène pas
    /// (critère chantier 5 n° 1).
    private var badgeRole: some View {
        Text(model.badge)
            .font(.plexSans(11, .semibold))
            .foregroundStyle(One2OneToken.oneOnOneInk)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Capsule(style: .continuous).fill(One2OneToken.surface))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(One2OneToken.oneOnOne.opacity(0.55), lineWidth: 1)
            }
            .help("Cet entretien est mené par votre manager — vos notes et vos sujets "
                  + "restent privés jusqu'à un geste explicite.")
    }
}

#Preview("CollabPrepHeader") {
    CollabPrepHeader(model: CollabPrepHeaderModel(
        title: "1:1 avec Yann — demain 14:00",
        meta: "Préparation · 2 min · dernier point le 21 août",
        badge: "Collaborateur",
        initials: "YP",
        identity: "Yann PENVEN"))
        .frame(width: 940)
        .padding(20)
        .background(One2OneToken.bgCanvas)
}
