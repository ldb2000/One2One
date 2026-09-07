import SwiftUI
import SwiftData

/// Le panneau `✳ ASSISTANT ⌘K` en pied de la colonne droite du mode séance
/// (spec §2.6 : « Panneau assistant en bas de colonne droite : question,
/// réponse, puces de sources horodatées cliquables », capture
/// `1b-mode-seance.png`).
///
/// Ni bulles, ni fil déroulant : un seul échange à l'écran, le dernier. En
/// séance on pose une question et on lit la réponse ; relire la conversation
/// est un geste de relecture, et il a son écran (mode Relire, lot 5).
struct SessionAssistantPanel: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    let assistant: MeetingAssistantController
    /// Ouvre la réunion d'une source qui n'est pas la séance en cours.
    let onOpenMeeting: (UUID, Double?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }
    @FocusState private var champFocalise: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
            if let echange = assistant.dernier {
                carte(echange)
            } else {
                invite
            }
            champ
        }
        .padding(.horizontal, 14)
        .overlay {
            // `⌘K` (spec §1.4) : en mode séance, l'assistant n'est pas une
            // feuille à ouvrir — il est déjà là. `⌘K` lui rend le clavier.
            Button("") { champFocalise = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var entete: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(c.action)
            Text("Assistant").sectionLabel()
            Spacer(minLength: 6)
            Text("⌘K")
                .font(.plexMono(10))
                .foregroundStyle(c.ink4)
        }
    }

    /// L'invite du panneau vide. « Jamais un écran vide » : la première
    /// suggestion de `MeetingAssistantDock` est déjà datée et actionnable, on
    /// la réemploie plutôt que d'inventer un texte gris.
    private var invite: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MeetingAssistantDock.suggestions(for: meeting, historique: []),
                    id: \.self) { suggestion in
                Button {
                    assistant.demander(suggestion, meeting: meeting,
                                       settings: settings, context: context)
                } label: {
                    Text(suggestion)
                        .font(.plexSans(12))
                        .foregroundStyle(c.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Poser cette question à l'assistant")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(c.card)
        )
    }

    /// La carte de la capture : question **en gras**, réponse en markdown,
    /// puces de sources horodatées.
    private func carte(_ echange: MeetingAssistantController.Echange) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(echange.question)
                .font(.plexSans(12.5, .semibold))
                .foregroundStyle(c.ink1)
                .fixedSize(horizontal: false, vertical: true)

            if assistant.enCours, echange.reponse.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(assistant.phase.label ?? "Recherche…")
                        .font(.plexSans(11.5))
                        .foregroundStyle(c.ink4)
                }
            } else if let erreur = assistant.erreur, echange.reponse.isEmpty {
                Text(erreur)
                    .font(.plexSans(11.5))
                    .foregroundStyle(c.reportInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MarkdownText(markdown: echange.reponse)
                    .font(.plexSans(12))
                    .foregroundStyle(c.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !echange.sources.isEmpty { puces(echange.sources) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(c.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(c.cardBorder, lineWidth: 1)
        )
    }

    /// Les puces `1 sept. 08:12 ↗` et `15:20 ↗`.
    ///
    /// Deux destinations selon la source : dans la séance, le clic replace la
    /// tête de lecture (on ne quitte pas le plein écran pour relire une note
    /// posée il y a trois minutes) ; ailleurs, il ouvre la réunion d'origine.
    private func puces(_ sources: [MeetingAssistantController.Source]) -> some View {
        HStack(spacing: 6) {
            ForEach(sources) { source in
                Button {
                    if source.estDansLaSeance {
                        screen.playhead.seek(to: source.t ?? 0)
                    } else if let id = source.meetingStableID {
                        onOpenMeeting(id, source.t)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(source.libelle)
                            .font(.plexMono(10, .medium))
                            .monospacedDigit()
                        Text("↗").font(.plexSans(9))
                    }
                    .foregroundStyle(c.actionInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(c.pill))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(source.estDansLaSeance
                      ? "Replacer la lecture à \(source.libelle)"
                      : "Ouvrir la réunion source du \(source.libelle)")
            }
            Spacer(minLength: 0)
        }
    }

    /// `Poser une question…` + le bouton d'envoi bleu de la capture.
    private var champ: some View {
        HStack(spacing: 8) {
            TextField("Poser une question…",
                      text: Binding(get: { screen.session.assistantDraft },
                                    set: { screen.session.assistantDraft = $0 }))
                .textFieldStyle(.plain)
                .font(.plexSans(12))
                .foregroundStyle(c.ink1)
                .focused($champFocalise)
                .onSubmit(envoyer)
            Button(action: envoyer) {
                Image(systemName: assistant.enCours ? "hourglass" : "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .frame(width: 30, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                         style: .continuous)
                            .fill(One2OneToken.action)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(assistant.enCours
                      || screen.session.assistantDraft
                          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Envoyer la question (⏎)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(c.pill)
        )
    }

    private func envoyer() {
        let question = screen.session.assistantDraft
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        assistant.demander(question, meeting: meeting, settings: settings, context: context)
        screen.session.assistantDraft = ""
    }
}

/// Le bloc `CAPTURÉ CETTE SÉANCE` : trois compteurs en pied de colonne droite
/// (capture `1b-mode-seance.png` : `4 ACTIONS · 1 DÉCISION · 2 RISQUES`, le 2
/// en ambre).
struct SessionCapturedBlock: View {

    let compteurs: SessionCapturedSummary.Compteurs

    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Capturé cette séance").sectionLabel()
            HStack(spacing: 8) {
                tuile(compteurs.actions,
                      libelle: SessionCapturedSummary.libelle(compteurs.actions,
                                                              singulier: "action",
                                                              pluriel: "actions"),
                      teinte: c.ink1)
                tuile(compteurs.decisions,
                      libelle: SessionCapturedSummary.libelle(compteurs.decisions,
                                                              singulier: "décision",
                                                              pluriel: "décisions"),
                      teinte: c.ink1)
                // Le risque est le seul compteur teinté sur la capture : c'est
                // le seul qui, en montant, appelle une décision.
                tuile(compteurs.risques,
                      libelle: SessionCapturedSummary.libelle(compteurs.risques,
                                                              singulier: "risque",
                                                              pluriel: "risques"),
                      teinte: compteurs.risques > 0 ? c.warn : c.ink1)
            }
        }
        .padding(.horizontal, 14)
    }

    private func tuile(_ valeur: Int, libelle: String, teinte: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(valeur)")
                .font(.plexSans(19, .semibold))
                .monospacedDigit()
                .foregroundStyle(teinte)
            Text(libelle).sectionLabel()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(c.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(c.cardBorder, lineWidth: 1)
        )
    }
}
