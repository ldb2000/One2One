import SwiftUI
import SwiftData

/// L'onglet `Historique` du rail (spec §2.5) : « actions closes de la réunion
/// et actions déplacées/reportées, une ligne par entrée avec date ».
///
/// C'est le contrepoids de l'onglet `Actions`, qui masque tout ce qui est
/// terminé : sans cet onglet, cocher une action la ferait disparaître sans
/// trace, et c'est précisément ce qui empêche de dire en fin de séance ce qui
/// a été bouclé.
struct ActionsRailHistory: View {

    @Bindable var meeting: Meeting

    private var entrees: [ActionsRailGrouping.Entree] {
        ActionsRailGrouping.historique(for: meeting.tasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entrees.isEmpty {
                MeetingEmptyInvite(
                    titre: "Rien de bouclé pour l'instant",
                    invite: "Les actions cochées, abandonnées ou reportées d'une séance précédente s'inscriront ici."
                )
                .padding(.vertical, 12)
            } else {
                ForEach(entrees) { entree in
                    ligne(entree)
                    if entree.id != entrees.last?.id {
                        Rectangle().fill(One2OneToken.hair).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func ligne(_ entree: ActionsRailGrouping.Entree) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: entree.motif == .close ? "checkmark.circle" : "arrow.uturn.forward")
                .font(.system(size: 9))
                .foregroundStyle(entree.motif == .close ? One2OneToken.ok : One2OneToken.ink4)
            Text(entree.titre)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink3)
                .lineLimit(1)
            Spacer(minLength: 6)
            // Une date inconnue se dit, elle ne s'invente pas : les actions
            // closes avant l'ajout de `completedAt` n'en ont pas.
            MonoMeta(entree.date.map { ActionsRailGrouping.dateOrdinale($0) } ?? "—")
        }
        .padding(.vertical, One2OneToken.tableRowPaddingV / 2)
    }
}
