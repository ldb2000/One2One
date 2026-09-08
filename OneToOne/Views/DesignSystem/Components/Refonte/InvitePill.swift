import SwiftUI

/// Pilule d'invite : `＋ assigner`, `＋ échéance`, `＋ Ajouter un risque`.
///
/// C'est la primitive qui porte la règle « aucune zone vide sans invite »
/// (spec, chantier 1, critère 1). Tant que le champ n'est pas renseigné, elle
/// réclame en `accent/action` ; renseignée, elle passe en `accent/ok` — ou
/// reste neutre quand la valeur affichée n'engage personne (une durée, une
/// charge).
struct InvitePill: View {

    enum Etat: CaseIterable, Sendable {
        /// Rien n'est renseigné : la pilule réclame.
        case invite
        /// La valeur est là et elle engage quelqu'un.
        case renseignee
        /// La valeur est là et elle n'engage personne.
        case neutre

        var encre: Color {
            switch self {
            case .invite: One2OneToken.actionInk
            case .renseignee: One2OneToken.okDeep
            case .neutre: One2OneToken.ink3
            }
        }

        var fond: Color {
            switch self {
            case .invite: One2OneToken.actionBg
            case .renseignee: One2OneToken.okBg
            case .neutre: One2OneToken.surfaceAlt
            }
        }
    }

    let texte: String
    let etat: Etat
    let action: (() -> Void)?

    init(_ texte: String, etat: Etat = .invite, action: (() -> Void)? = nil) {
        self.texte = texte
        self.etat = etat
        self.action = action
    }

    private var etiquette: some View {
        Text(texte)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(etat.encre)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(etat.fond))
    }

    var body: some View {
        if let action {
            Button(action: action) { etiquette }
                .buttonStyle(.plain)
                .accessibilityLabel(texte)
        } else {
            etiquette
        }
    }
}

#Preview("InvitePill") {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
            InvitePill("＋ assigner")
            InvitePill("＋ échéance")
        }
        HStack(spacing: 6) {
            InvitePill("Yann", etat: .renseignee)
            InvitePill("11 sept.", etat: .renseignee)
            InvitePill("2h", etat: .neutre)
        }
        HStack(spacing: 6) {
            InvitePill("＋ Ajouter un risque", action: {})
            InvitePill("＋ Ajouter", action: {})
        }
    }
    .padding(20)
    .background(One2OneToken.surface)
}
