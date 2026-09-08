import SwiftUI

/// `RESTÉ SANS RÉPONSE` (capture 5b, premier bloc) : ce qu'on m'a promis et qui
/// n'est pas venu, ce que j'ai demandé sans réponse, ce que j'ai posé trois
/// fois sans décision.
///
/// **Les cases sont décochées.** Porter une parole non tenue en séance est un
/// choix — parfois on préfère laisser passer une fois de plus —, et une carte
/// qui coche pour moi déciderait à ma place de ce que je vais réclamer. La
/// carte expose, elle ne choisit pas.
///
/// Tout le calcul est dans `UnansweredItemsBuilder`, qui est pur et testé : la
/// carte ne fait que rendre et cocher.
struct UnansweredCard: View {

    let items: [UnansweredItemsBuilder.Item]
    /// Les identifiants cochés — l'état d'écran, jamais une donnée.
    let checked: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(UnansweredItemsBuilder.title)
                    .sectionLabel()
                    // Le rouge de la capture : ces lignes-là sont des paroles
                    // en retard, pas un inventaire.
                    .foregroundStyle(One2OneToken.reportInk)

                if items.isEmpty {
                    Text(UnansweredItemsBuilder.emptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { ligne in
                            self.ligne(ligne)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ligne(_ item: UnansweredItemsBuilder.Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CollabPrepCheckbox(isOn: checked.contains(item.id),
                               help: UnansweredItemsBuilder.checkboxHelp) {
                onToggle(item.id)
            }
            // Alignée sur la première ligne de texte : un libellé de deux
            // lignes ne doit pas décrocher sa case.
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.plexSans(12.5))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if !item.sinceLabel.isEmpty {
                    Text(item.sinceLabel)
                        .font(.plexSans(11))
                        .foregroundStyle(One2OneToken.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
