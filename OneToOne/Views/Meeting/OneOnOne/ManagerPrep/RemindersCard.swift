import SwiftUI
import SwiftData

/// La carte `À NE PAS OUBLIER` de la capture 2b : les trois règles du lot 10
/// dans leur ordre, et le bouton qui les verse à l'ordre du jour.
struct PrepRemindersModel: Equatable, Sendable {

    var reminders: [ReminderRules.Reminder]
    /// Faux quand tout est déjà à l'ordre du jour — ou qu'il n'y a rien à
    /// verser.
    var isAgendaButtonEnabled: Bool

    var isEmpty: Bool { reminders.isEmpty }

    @MainActor
    static func build(_ thread: OneOnOneThread, now: Date) -> PrepRemindersModel {
        let rappels = ReminderRules.reminders(for: thread, now: now)
        return PrepRemindersModel(
            reminders: rappels,
            isAgendaButtonEnabled: !rappels.isEmpty
                && !ReminderRules.areAllOnAgenda(rappels, in: thread)
        )
    }
}

/// La carte `À NE PAS OUBLIER` (capture 2b) : une puce colorée par règle et le
/// bouton `Mettre à l'ordre du jour`.
struct RemindersCard: View {

    static let dotSize: CGFloat = 7

    let model: PrepRemindersModel
    /// Crée les sujets d'ordre du jour correspondants.
    let onFillAgenda: () -> Void

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("À ne pas oublier")
                    .sectionLabel()
                    // Le seul libellé de section teinté de l'écran : la carte
                    // porte ce qu'on risque d'oublier, et la capture la
                    // distingue ainsi des deux autres de la rangée.
                    .foregroundStyle(One2OneToken.reportInk)

                if model.isEmpty {
                    MeetingEmptyInvite(
                        titre: "Rien qui traîne",
                        invite: "Aucun engagement de votre côté en retard, aucun sujet resté "
                              + "trois fois sans décision, aucune réussite à saluer."
                    )
                } else {
                    ForEach(model.reminders) { rappel in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(rappel.tone.color)
                                .frame(width: Self.dotSize, height: Self.dotSize)
                                // Aligné sur la première ligne de texte et non
                                // sur le haut du bloc : un rappel de deux
                                // lignes ne doit pas décrocher sa puce.
                                .padding(.top, 4)
                            Text(rappel.text)
                                .font(.plexSans(12))
                                .foregroundStyle(One2OneToken.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }

                    Button(action: onFillAgenda) {
                        Text(model.isAgendaButtonEnabled
                             ? "Mettre à l'ordre du jour"
                             : "Déjà à l'ordre du jour")
                            .font(.plexSans(11.5, .medium))
                            .foregroundStyle(One2OneToken.oneOnOneInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                                 style: .continuous)
                                    .fill(One2OneToken.oneOnOneBg)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isAgendaButtonEnabled)
                    .opacity(model.isAgendaButtonEnabled ? 1 : 0.55)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
