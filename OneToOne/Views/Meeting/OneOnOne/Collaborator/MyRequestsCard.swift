import SwiftUI
import SwiftData

/// `MES DEMANDES EN COURS` (capture 5a, colonne gauche) : ce que j'ai demandé,
/// où ça en est, et depuis combien de temps.
///
/// Ce n'est pas une seconde table : une demande **est** un sujet d'ordre du
/// jour qui attend une réponse (`OneOnOneAgendaItem` de `kind: .request`,
/// lot 10). La carte est un filtre, pas un magasin — séparer les deux aurait
/// obligé à synchroniser deux listes que l'utilisateur voit comme une seule.
///
/// La carte montre aussi les demandes **accordées** malgré son titre : une
/// réponse obtenue est justement ce qu'on veut avoir sous les yeux quand on
/// repose la question suivante.
struct MyRequestsCard: View {

    let thread: OneOnOneThread
    var now: Date = Date()

    @Environment(\.modelContext) private var context

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(CollaboratorSessionModel.requestsTitle)
                let demandes = CollaboratorSessionModel.requests(thread)
                if demandes.isEmpty {
                    Text(CollaboratorSessionModel.requestsEmptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(demandes, id: \.persistentModelID) { demande in
                        ligne(demande)
                    }
                }
            }
        }
    }

    private func ligne(_ demande: OneOnOneAgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(demande.text)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Pill(demande.requestStatus.label,
                     ton: CollaboratorSessionModel.requestTone(demande, now: now))
            }
            // L'historique court de la spec : la date d'origine et le nombre de
            // relances. C'est l'ancienneté qui donne du poids à la demande, et
            // c'est elle qui la fait passer en `report` au-delà de 60 jours.
            let historique = AgendaCarryover.requestHistoryLabel(demande)
            if !historique.isEmpty {
                Text(historique)
                    .font(.plexSans(11))
                    // `ink/4` et non `ink/muted` : §1.2 réserve `ink/muted` aux
                    // placeholders de 11,5 px et plus, et exige 4,5:1 sous 12 px.
                    .foregroundStyle(One2OneToken.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .help(aide(demande))
        .contextMenu { menu(demande) }
    }

    private func aide(_ demande: OneOnOneAgendaItem) -> String {
        switch AgendaCarryover.requestLevel(demande, now: now) {
        case .report where demande.requestStatus != .refused:
            return "Sans réponse depuis plus de \(AgendaCarryover.unansweredRequestDays) jours"
        case .report:
            return "Demande refusée — clic droit pour changer son statut"
        case .ok, .warn:
            return "Clic droit pour changer son statut ou compter une relance"
        }
    }

    @ViewBuilder
    private func menu(_ demande: OneOnOneAgendaItem) -> some View {
        Menu("Statut") {
            ForEach(RequestStatus.allCases) { statut in
                Button(demande.requestStatus == statut ? "✓ \(statut.label)" : statut.label) {
                    demande.requestStatus = statut
                    // Une demande accordée ou refusée est tranchée : elle ne
                    // reste pas à l'ordre du jour de la séance suivante.
                    demande.state = (statut == .granted || statut == .refused) ? .done : .todo
                    try? context.save()
                }
            }
        }
        Button("Compter une relance") {
            AgendaCarryover.remind(demande)
            try? context.save()
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            context.delete(demande)
            try? context.save()
        }
    }
}
