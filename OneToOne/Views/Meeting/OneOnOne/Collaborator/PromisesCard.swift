import SwiftUI
import SwiftData

/// `CE QU'IL M'A PROMIS · 1 en retard` (capture 5a, colonne droite).
///
/// Les engagements du **manager**, triés par retard décroissant, avec une barre
/// gauche `accent/report` sur ceux qui sont en retard (spec §6.2). C'est la
/// seule vue de l'application où la parole du manager est comptée comme la
/// parole des autres — « y compris pour le manager, sans exception ».
///
/// Réemploie `CommitmentRow` du lot 11 ? Non : ses pilules sont celles de la
/// capture 2a (échéance, charge, criticité, confidentialité) et celles de la
/// capture 5a sont autres (`Promise le …`, `n reports`, `Relancer`). La carte
/// est proche, la lecture est différente — c'est l'ancienneté de la promesse
/// qui pèse ici, pas son échéance.
struct PromisesCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    var now: Date = Date()

    @Environment(\.modelContext) private var context
    /// La dernière relance, pour la dire sur place plutôt que dans un dialogue.
    @State private var derniereRelance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            entete
            let promesses = CollaboratorSessionModel.promises(thread, now: now)
            if promesses.isEmpty {
                Text(CollaboratorSessionModel.promisesEmptyInvite)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(promesses, id: \.persistentModelID) { promesse in
                    carte(promesse)
                }
            }
            if let relance = derniereRelance {
                Text(relance)
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.oneOnOneInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 6) {
            SectionLabel(CollaboratorSessionModel.promisesTitle)
            Spacer(minLength: 0)
            if let retard = CollaboratorSessionModel.lateBadge(thread, now: now) {
                Pill(retard, ton: .report)
                    .help("Une parole donnée dont l'échéance est passée")
            }
        }
    }

    // MARK: - Carte d'une promesse

    private func carte(_ promesse: Commitment) -> some View {
        let enRetard = CollaboratorSessionModel.isLate(promesse, now: now)
        return HStack(alignment: .top, spacing: 0) {
            // La barre gauche n'apparaît que sur un retard : partout ailleurs
            // elle deviendrait un liseré décoratif qu'on ne lit plus.
            if enRetard {
                Rectangle()
                    .fill(One2OneToken.report)
                    .frame(width: 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(promesse.text)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                pilules(promesse, enRetard: enRetard)
            }
            .padding(One2OneToken.cardPaddingMin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                    style: .continuous))
        .contextMenu { menu(promesse) }
    }

    /// L'échéance ou la date de la parole, le nombre de reports, puis
    /// `Relancer`. La date d'abord : c'est la seule qu'on cherche du regard.
    private func pilules(_ promesse: Commitment, enRetard: Bool) -> some View {
        HStack(spacing: 5) {
            if enRetard {
                // En retard, ce qui compte est **depuis quand** c'était promis,
                // pas la date qu'on a dépassée.
                Pill(CollaboratorSessionModel.promisedAtPill(promesse), ton: .report)
            } else if let echeance = CollaboratorSessionModel.duePill(promesse, now: now) {
                Pill(echeance, ton: .neutre)
            } else {
                Pill(CollaboratorSessionModel.promisedAtPill(promesse), ton: .neutre)
            }
            if let reports = CollaboratorSessionModel.deferralPill(promesse) {
                Pill(reports, ton: promesse.deferralCount > 2 ? .warn : .neutre)
            }
            if let frais = CollaboratorSessionModel.takenTodayPill(promesse, now: now) {
                Pill(frais, ton: .ok)
            }
            Spacer(minLength: 0)
            boutonRelancer(promesse)
        }
    }

    private func boutonRelancer(_ promesse: Commitment) -> some View {
        Button {
            let sujet = PromiseReminders.remind(
                promesse, in: thread,
                nextMeeting: OneOnOneThreadStore.nextMeeting(after: meeting, in: thread),
                in: context)
            derniereRelance = "Relance notée (\(sujet.remindedCount)) — "
                + "le sujet vous attend au prochain 1:1."
        } label: {
            Pill(CollaboratorSessionModel.remindButtonLabel, ton: .oneOnOne, bordee: true)
        }
        .buttonStyle(.plain)
        .help("Compte la relance et met le sujet à l'ordre du jour de votre prochain 1:1")
    }

    @ViewBuilder
    private func menu(_ promesse: Commitment) -> some View {
        Button("Marquer tenue") {
            CommitmentLedger.markKept(promesse, on: now)
            try? context.save()
        }
        Button("Marquer manquée") {
            CommitmentLedger.markMissed(promesse, on: now)
            try? context.save()
        }
        Button("Il l'a repoussée") {
            // `postpone` ne solde pas : la promesse reste ouverte et le
            // compteur monte — c'est ce compteur que la spec veut voir.
            CommitmentLedger.postpone(promesse)
            try? context.save()
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            context.delete(promesse)
            try? context.save()
        }
    }
}
