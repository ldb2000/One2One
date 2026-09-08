import SwiftUI
import SwiftData

/// `CE QUE JE VEUX OBTENIR` (capture 5b, troisième bloc) : mes sujets privés,
/// **cochés par défaut**, et le champ pointillé `Ajouter…`.
///
/// Cochés parce que je les ai écrits pour les dire : l'écran n'a pas à me
/// demander de confirmer une intention que j'ai déjà notée. Décocher veut dire
/// « pas cette fois » — le sujet reste dans mon brouillon, il ne part pas à
/// l'ordre du jour de cette séance-là.
struct WantedCard: View {

    let items: [OneOnOneAgendaItem]
    /// Les sujets **décochés** : la carte coche par défaut, l'état d'écran ne
    /// retient donc que le refus.
    let dropped: Set<PersistentIdentifier>
    let onToggle: (PersistentIdentifier) -> Void
    /// Le composeur `Ajouter…`. Rend `true` quand la ligne a été créée, pour
    /// que le champ se vide.
    let onAdd: (String) -> Bool

    @State private var brouillon = ""

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(WantedItemsBuilder.title)
                    .sectionLabel()
                    // Le violet de la capture : c'est le seul bloc où c'est moi
                    // qui parle.
                    .foregroundStyle(One2OneToken.oneOnOneInk)

                if items.isEmpty {
                    Text(WantedItemsBuilder.emptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.persistentModelID) { sujet in
                            ligne(sujet)
                        }
                    }
                }

                OneOnOneInlineComposer(placeholder: WantedItemsBuilder.composerPlaceholder,
                                       text: $brouillon,
                                       onSubmit: ajouter)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ligne(_ sujet: OneOnOneAgendaItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CollabPrepCheckbox(isOn: !dropped.contains(sujet.persistentModelID),
                               help: WantedItemsBuilder.checkboxHelp) {
                onToggle(sujet.persistentModelID)
            }
            .padding(.top, 1)
            Text(sujet.text)
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func ajouter() {
        guard onAdd(brouillon) else { return }
        brouillon = ""
    }
}
