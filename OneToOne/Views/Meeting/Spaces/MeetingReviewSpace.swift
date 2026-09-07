import SwiftUI

/// Le mode Relire de l'espace Réunion : « Résumé + décisions + tableau
/// d'actions ; transcription repliée » (spec §2.2).
///
/// C'est la disposition que la décision **D0** identifie au « poste de
/// pilotage » de la capture `1c-poste-de-pilotage.png` : le contenu de 1c —
/// une phrase, les décisions prises, le tableau d'actions, pas de
/// transcription — est exactement la définition du mode Relire.
///
/// **Contenu provisoire** : la nav latérale de 190 px, le tableau dense à sept
/// colonnes et la frise audio pleine largeur arrivent au lot 5 ; la liste
/// d'actions est ici celle qui existe déjà, injectée par `MeetingView`.
struct MeetingReviewSpace<Actions: View>: View {
    let meeting: Meeting
    let kpi: MeetingKPI
    /// Vrai pendant la génération du résumé.
    let isSummarizing: Bool
    /// Lance la génération du résumé en une phrase.
    let onSummarize: () -> Void
    /// Repasse en mode En séance, où la transcription est dépliée.
    let onShowTranscript: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                enUnePhrase
                decisionsPrises
                actionsSection
                transcriptionRepliee
            }
            .padding(14)
        }
    }

    // MARK: - En une phrase

    private var enUnePhrase: some View {
        carte {
            HStack(spacing: 7) {
                Text("EN UNE PHRASE").sectionLabel()
                if !meeting.shortSummary.isEmpty {
                    Chip("généré", ton: .action)
                }
                Spacer(minLength: 0)
                if isSummarizing {
                    ProgressView().controlSize(.small)
                }
            }
            if meeting.shortSummary.isEmpty {
                MeetingEmptyInvite(
                    titre: "Pas encore de résumé",
                    invite: "Une phrase suffit à retrouver cette réunion dans six mois — générez-la depuis la transcription.",
                    libelleAction: isSummarizing ? nil : "Résumer",
                    action: isSummarizing ? nil : onSummarize
                )
            } else {
                Text(meeting.shortSummary)
                    .font(.plexSans(12.5))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !meeting.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(meeting.tags) { tag in
                            Chip(tag.name, ton: .neutre)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Décisions prises

    private var decisionsPrises: some View {
        carte {
            HStack(spacing: 7) {
                Text("DÉCISIONS PRISES").sectionLabel()
                MonoMeta("\(kpi.decisions.count)", emphase: kpi.decisions.count > 0)
                Spacer(minLength: 0)
            }
            if meeting.decisions.isEmpty {
                MeetingEmptyInvite(
                    titre: "Aucune décision consignée",
                    invite: "Tapez /décision dans les notes pendant la séance, ou ajoutez-les depuis le rapport."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(meeting.decisions.enumerated()), id: \.offset) { index, texte in
                        HStack(alignment: .top, spacing: 8) {
                            // Barre gauche `accent/report` : la marque des
                            // décisions dans toute la refonte (spec §2.4).
                            Rectangle()
                                .fill(One2OneToken.report)
                                .frame(width: 2)
                            Text(texte)
                                .font(.plexSans(12.5))
                                .foregroundStyle(One2OneToken.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, One2OneToken.tableRowPaddingV)
                        if index < meeting.decisions.count - 1 {
                            Rectangle().fill(One2OneToken.hair).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        carte {
            HStack(spacing: 7) {
                Text("ACTIONS").sectionLabel()
                MonoMeta("\(kpi.actions.total)", emphase: kpi.actions.total > 0)
                if kpi.actions.unassigned > 0 {
                    Text("\(kpi.actions.unassigned) sans responsable")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.report)
                }
                Spacer(minLength: 0)
            }
            if kpi.actions.total == 0 {
                MeetingEmptyInvite(
                    titre: "Aucune action",
                    invite: "Le composeur en pied de liste crée une action ; /action dans les notes en crée une horodatée."
                )
            }
            // La liste existante reste affichée même vide : c'est elle qui
            // porte le composeur, et le retirer priverait l'invite de sa
            // suite. Le tableau dense à sept colonnes arrive au lot 5.
            actions
                .frame(minHeight: 220)
        }
    }

    // MARK: - Transcription repliée

    /// « Transcription repliée » (spec §2.2) : elle n'est pas absente, elle est
    /// à un clic — sinon relire une réunion sans pouvoir vérifier une phrase
    /// serait un cul-de-sac.
    private var transcriptionRepliee: some View {
        carte {
            HStack(spacing: 7) {
                Text("TRANSCRIPTION").sectionLabel()
                if meeting.rawTranscript.isEmpty {
                    MonoMeta("aucune")
                } else {
                    MonoMeta("\(meeting.transcriptSegments.count) segments")
                }
                Spacer(minLength: 0)
                if !meeting.rawTranscript.isEmpty {
                    Button(action: onShowTranscript) {
                        Text("Déplier en séance")
                            .font(.plexSans(10.5, .medium))
                            .foregroundStyle(One2OneToken.actionInk)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: One2OneToken.radiusPill)
                                    .fill(One2OneToken.actionBg)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if meeting.rawTranscript.isEmpty {
                MeetingEmptyInvite(
                    titre: "Aucune transcription",
                    invite: "Enregistrez la séance, ou importez un WAV existant depuis le menu ⋯ → Importer."
                )
            }
        }
    }

    // MARK: - Fabrique de carte

    @ViewBuilder
    private func carte<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            content()
        }
        .padding(One2OneToken.cardPaddingMax)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }
}
