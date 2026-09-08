import SwiftUI
import SwiftData

/// Le rail de 320 px de l'écran de séance 1:1 (capture 2a, colonne droite) :
/// `ENGAGEMENTS DE CETTE SÉANCE` groupés par côté, `TENUS DEPUIS LE DERNIER
/// 1:1`, puis `CLÔTURER`.
///
/// Ce n'est **pas** `ActionsRail` : la spec §3.1 retire du type 1:1 les vues
/// Kanban et Post-it, les projets affectés et la présence. Ce rail-là ne montre
/// que des paroles données, et il se termine par les deux gestes qui closent un
/// entretien.
struct CommitmentsRail: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    /// Nom de l'utilisateur de l'application (`AppSettings.ownerName`), pour
    /// les initiales de « Moi ».
    let ownerName: String
    var now: Date = Date()

    @Environment(\.modelContext) private var context
    @State private var brouillon = ""
    /// Le côté qui portera l'engagement saisi dans le composeur du pied.
    @State private var coteDuBrouillon: OneOnOneSide?
    @State private var recapEnvoye: Bool?
    @State private var prochainPlanifie: Bool?

    private var cote: OneOnOneSide { coteDuBrouillon ?? thread.myRole }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                engagements
                separateur
                ledger
                separateur
                cloture
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(One2OneToken.bgApp)
    }

    // MARK: - Engagements de cette séance

    private var engagements: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(CommitmentsRailModel.commitmentsTitle)
            ForEach(CommitmentsRailModel.groups(for: meeting, in: thread,
                                                ownerName: ownerName,
                                                now: now)) { groupe in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        AvatarSide(initials: groupe.initials, identity: identite(de: groupe.side))
                        Text(groupe.title)
                            .font(.plexSans(12, .semibold))
                            .foregroundStyle(One2OneToken.ink1)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Button {
                            coteDuBrouillon = groupe.side
                        } label: {
                            Text("＋")
                                .font(.plexSans(12, .medium))
                                .foregroundStyle(cote == groupe.side
                                                 ? One2OneToken.oneOnOneInk
                                                 : One2OneToken.ink4)
                                .frame(width: 20, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Le prochain engagement saisi sera pour \(identite(de: groupe.side))")
                    }
                    if groupe.commitments.isEmpty {
                        Text(CommitmentsRailModel.emptyInvite(for: groupe.side, in: thread))
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(groupe.commitments, id: \.persistentModelID) { engagement in
                            CommitmentRow(commitment: engagement, now: now)
                        }
                    }
                }
            }
            composeur
        }
    }

    /// Le composeur inline du rail : l'autre porte d'entrée d'un engagement,
    /// à côté de `/engagement` dans les notes. Les deux passent par le même
    /// chemin d'écriture.
    private var composeur: some View {
        VStack(alignment: .leading, spacing: 4) {
            OneOnOneInlineComposer(
                placeholder: CommitmentsRailModel.commitmentComposerPlaceholder,
                text: $brouillon
            ) {
                let contexte = OneOnOneComposerContext(thread: thread, role: cote)
                contexte.apply("/engagement \(brouillon)", at: 0, to: meeting, in: context)
                brouillon = ""
            }
            Text("Pour \(identite(de: cote))")
                .font(.plexSans(10.5))
                .foregroundStyle(One2OneToken.inkMuted)
        }
    }

    // MARK: - Tenus depuis le dernier 1:1

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(CommitmentsRailModel.ledgerTitle)
            let lignes = CommitmentsRailModel.ledgerLines(for: meeting, in: thread,
                                                          ownerName: ownerName, now: now)
            if lignes.isEmpty {
                Text(CommitmentsRailModel.ledgerEmptyInvite)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(lignes) { ligne in
                    HStack(alignment: .top, spacing: 7) {
                        Text(ligne.symbol)
                            .font(.plexSans(11.5, .semibold))
                            .foregroundStyle(ligne.isMissed
                                             ? One2OneToken.report
                                             : One2OneToken.ok)
                        Text(ligne.text)
                            .font(.plexSans(11.5))
                            .foregroundStyle(ligne.isMissed
                                             ? One2OneToken.reportInk
                                             : One2OneToken.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            MonoMeta(ligne.initials)
                            if let reports = ligne.deferralLabel {
                                Text(reports)
                                    .font(.plexMono(10, .medium))
                                    .foregroundStyle(One2OneToken.report)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Clôturer

    private var cloture: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(CommitmentsRailModel.closingTitle)

            Button {
                recapEnvoye = OneOnOneRecapActions.sendRecap(
                    for: meeting,
                    thread: thread,
                    audience: OneOnOneConfidentiality.recapAudience(for: thread.myRole),
                    now: now)
            } label: {
                Text(CommitmentsRailModel.recapButtonLabel(for: thread))
                    .font(.plexSans(12, .semibold))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                            .fill(One2OneToken.oneOnOne)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvre un brouillon de mail avec le récap filtré")

            Button {
                Task { prochainPlanifie = await OneOnOneRecapActions.planNext(for: thread,
                                                                             now: now) }
            } label: {
                Text(CommitmentsRailModel.planNextButtonLabel(for: thread, now: now))
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                            .fill(One2OneToken.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                            .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Crée l'événement du prochain entretien dans votre calendrier")

            VStack(alignment: .leading, spacing: 2) {
                Text(CommitmentsRailModel.privacyFootnote)
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                if let compte = CommitmentsRailModel.excludedLinesLabel(for: meeting, in: thread) {
                    Text(compte)
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(One2OneToken.oneOnOneInk)
                }
                // Aucun dialogue bloquant : un refus d'autorisation ou une
                // adresse manquante se dit sur place (`OneOnOneRecapActions`
                // rend `false` plutôt que de poser une alerte).
                if recapEnvoye == false {
                    Text("Le brouillon n'a pas pu s'ouvrir — vérifiez l'adresse de la fiche.")
                        .font(.plexSans(10.5))
                        .foregroundStyle(One2OneToken.reportInk)
                }
                if prochainPlanifie == false {
                    Text("Aucun événement créé — cadence, autorisation ou calendrier manquants.")
                        .font(.plexSans(10.5))
                        .foregroundStyle(One2OneToken.reportInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Outils

    private var separateur: some View {
        Rectangle().fill(One2OneToken.hair).frame(height: 1)
    }

    private func identite(de side: OneOnOneSide) -> String {
        side == thread.myRole ? (ownerName.isEmpty ? "Moi" : ownerName)
                              : PersonCardModel.name(of: thread)
    }
}
