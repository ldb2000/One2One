import SwiftUI

/// La feuille de diff des propositions de l'assistant (spec §4.3 : « bouton
/// `Revoir` → diff champ par champ, acceptation individuelle »).
///
/// Chaque ligne montre la valeur enregistrée, la valeur proposée et la
/// citation qui la justifie. `Accepter` écrit dans le **brouillon**, jamais
/// dans `Project` : il faudra encore `Enregistrer` dans le panneau. `Ignorer`
/// retire la ligne sans rien changer.
struct ProjectCardSuggestionsSheet: View {

    static let title = "PROPOSITIONS DE L'ASSISTANT"
    static let acceptLabel = "Accepter"
    static let ignoreLabel = "Ignorer"
    static let emptyNotice = "Toutes les propositions ont été traitées."
    /// Message d'une proposition que le brouillon ne sait pas appliquer.
    static let refusedNotice = "Proposition inapplicable en l'état : à reporter à la main."

    let updates: [ProjectCardUpdate]
    @Binding var draft: ProjectCardDraft
    let onClose: () -> Void

    /// Identifiants des lignes déjà traitées, acceptées ou ignorées.
    @State private var handled: Set<String> = []
    /// Identifiants des lignes que le brouillon a refusées.
    @State private var refused: Set<String> = []

    private var remaining: [ProjectCardUpdate] {
        updates.filter { !handled.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Self.title).sectionLabel()
                Spacer()
                Button("Fermer", action: onClose)
                    .buttonStyle(.plain)
                    .font(.plexSans(11, .medium))
                    .foregroundStyle(One2OneToken.action)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(One2OneToken.hair)

            ScrollView {
                VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                    if remaining.isEmpty {
                        Text(Self.emptyNotice)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink3)
                            .padding(.top, 8)
                    } else {
                        ForEach(remaining) { proposition in
                            row(proposition)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 420)
        .background(One2OneToken.bgCanvas)
    }

    private func row(_ proposition: ProjectCardUpdate) -> some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(proposition.field.label).sectionLabel()
                    Text(proposition.displayLabel)
                        .font(.plexSans(12, .semibold))
                        .foregroundStyle(One2OneToken.ink1)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }

                HStack(alignment: .top, spacing: 8) {
                    valueBlock(titre: "ENREGISTRÉ",
                               texte: proposition.current.isEmpty ? "—" : proposition.current,
                               encre: One2OneToken.ink3,
                               fond: One2OneToken.surfaceAlt)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(One2OneToken.ink4)
                        .padding(.top, 16)
                    valueBlock(titre: "PROPOSÉ",
                               texte: proposition.proposed,
                               encre: One2OneToken.actionInk,
                               fond: One2OneToken.actionBg)
                }

                if !proposition.evidence.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 8))
                            .foregroundStyle(One2OneToken.ink4)
                        Text(proposition.evidence)
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if refused.contains(proposition.id) {
                    Text(Self.refusedNotice)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.reportInk)
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(Self.ignoreLabel) { handled.insert(proposition.id) }
                        .buttonStyle(.plain)
                        .font(.plexSans(11, .medium))
                        .foregroundStyle(One2OneToken.ink3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                             style: .continuous)
                                .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                        )
                    Button(Self.acceptLabel) { accept(proposition) }
                        .buttonStyle(.plain)
                        .font(.plexSans(11, .medium))
                        .foregroundStyle(One2OneToken.onFilledButton)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                             style: .continuous)
                                .fill(One2OneToken.action)
                        )
                }
            }
        }
    }

    private func valueBlock(titre: String, texte: String, encre: Color, fond: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre).sectionLabel()
            Text(texte)
                .font(.plexSans(12, .medium))
                .foregroundStyle(encre)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous).fill(fond)
        )
    }

    /// Accepter n'écrit que dans le brouillon. Une proposition que le brouillon
    /// ne sait pas appliquer — jalon inconnu, montant illisible — reste
    /// affichée avec sa mention : l'assistant ne devine pas à la place de
    /// l'utilisateur.
    private func accept(_ proposition: ProjectCardUpdate) {
        if ProjectCardSuggestions.accept(proposition, in: &draft) {
            refused.remove(proposition.id)
            handled.insert(proposition.id)
        } else {
            refused.insert(proposition.id)
        }
    }
}
