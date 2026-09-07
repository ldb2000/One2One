import SwiftUI
import SwiftData

/// Ce que l'en-tête de l'écran de préparation 1:1 affiche de la personne et de
/// la séance (capture 2b) : `LN`, `Laurent NOMINÉ`,
/// `Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026`.
///
/// **Modèle pur**, testable sans écran : le rang de séance et l'ordinal
/// français sont exactement le genre de détail qu'une vue calcule mal et qu'un
/// test attrape tout de suite.
struct PrepHeaderModel: Equatable, Sendable {

    var name: String
    var initials: String
    /// `rôle · nᵉ 1:1 · date`, sans séparateur orphelin quand une part manque.
    var subtitle: String
    /// Rang de la séance dans le fil, à partir de 1. `0` hors du fil.
    var sessionNumber: Int

    /// Le nom qu'affiche l'en-tête faute de collaborateur rattaché au fil.
    /// Repris de `PersonCardModel`, qui le porte pour les deux écrans depuis
    /// l'intégration de la vague 5.
    static var fallbackName: String { PersonCardModel.fallbackName }

    /// L'ancienneté, quand la carte veut la dire : `dans l'équipe depuis
    /// 3 ans`. L'en-tête de 2b ne la montre pas — sa méta porte le rang de
    /// séance et la date — mais elle se lit d'ici, par `OneOnOneSeniority`,
    /// sans second calcul.
    @MainActor
    static func seniority(of thread: OneOnOneThread, now: Date) -> String? {
        OneOnOneSeniority.label(joinedAt: thread.collaborator?.joinedAt, now: now)
    }

    /// **Le nom, le rôle et l'avatar viennent de `PersonCardModel`** (lot 11),
    /// pas d'une seconde lecture du collaborateur : la carte personne de la
    /// séance (2a) et cet en-tête (2b) montrent la même personne, et deux
    /// lectures finissaient par deux libellés. Ce qui reste propre à 2b est le
    /// **rang de séance** — `14ᵉ 1:1` — et la date en année pleine.
    @MainActor
    static func build(meeting: Meeting, thread: OneOnOneThread) -> PrepHeaderModel {
        let nom = PersonCardModel.name(of: thread)
        let rang = OneOnOneThreadStore.sessionNumber(of: meeting, in: thread)

        var parts: [String] = []
        let role = PersonCardModel.role(of: thread)
        if !role.isEmpty { parts.append(role) }
        if rang > 0 { parts.append("\(ordinal(rang)) 1:1") }
        parts.append(OneOnOneDateFormat.dayMonthYear(meeting.date))

        return PrepHeaderModel(
            name: nom,
            initials: PersonCardModel.initials(of: thread),
            subtitle: parts.joined(separator: " · "),
            sessionNumber: rang
        )
    }

    /// L'ordinal français des captures : `1ᵉʳ`, `14ᵉ`. Lettres modificatrices
    /// Unicode et non des exposants typographiques : le rendu doit tenir dans
    /// un `Text` d'une seule police.
    static func ordinal(_ n: Int) -> String {
        n <= 1 ? "\(n)ᵉʳ" : "\(n)ᵉ"
    }
}

/// L'en-tête violet pâle de l'écran de préparation (capture 2b) : avatar, nom,
/// méta, badges `1:1` et `Privé`, `Historique` et `Démarrer l'entretien`.
struct PrepHeader: View {

    /// Hauteur de la barre, telle que la capture la montre : deux lignes de
    /// texte, un avatar de 34 px et 13 px de respiration.
    static let height: CGFloat = 64
    static let avatarSize: CGFloat = 34

    let model: PrepHeaderModel
    /// Déplie l'historique complet du fil.
    let onShowHistory: () -> Void
    /// Passe en séance et démarre l'enregistrement.
    let onStart: () -> Void
    /// Vrai quand l'enregistrement ne peut pas démarrer (transcription ou
    /// rapport en cours) : le bouton reste visible mais inactif.
    var isStartDisabled = false

    var body: some View {
        HStack(spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.plexSans(14, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Text(model.subtitle)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink3)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            badgeType
            pilulePrivee

            Spacer(minLength: 12)

            boutonSecondaire("Historique", action: onShowHistory)
            boutonPrimaire("Démarrer l'entretien", action: onStart)
                .disabled(isStartDisabled)
                .opacity(isStartDisabled ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(One2OneToken.oneOnOneBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// La pastille du domaine 1:1 (`AvatarSide`, lot 11) et non un second
    /// dessin : même diamètre de 34 px, même palette, même bulle d'aide.
    private var avatar: some View {
        AvatarSide(initials: model.initials,
                   identity: model.name,
                   diametre: Self.avatarSize)
    }

    /// Le badge de type, **violet plein** : la capture le montre rempli, là où
    /// `Pill(ton: .oneOnOne)` porte le fond doux `#f4f1f6` — invisible sur
    /// l'en-tête, qui est déjà de cette teinte.
    private var badgeType: some View {
        Text("1:1")
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(One2OneToken.onFilledButton)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(One2OneToken.oneOnOne))
    }

    private var pilulePrivee: some View {
        Text("Privé")
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(One2OneToken.ink3)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(One2OneToken.surface))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
            }
            .help("Les notes de cet entretien ne concernent que vous deux.")
    }

    private func boutonSecondaire(_ titre: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(11.5, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func boutonPrimaire(_ titre: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(11.5, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.oneOnOne)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("PrepHeader") {
    PrepHeader(model: PrepHeaderModel(name: "Laurent NOMINÉ",
                                      initials: "LN",
                                      subtitle: "Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026",
                                      sessionNumber: 14),
               onShowHistory: {},
               onStart: {})
        .frame(width: 1_180)
        .padding(20)
        .background(One2OneToken.bgCanvas)
}
