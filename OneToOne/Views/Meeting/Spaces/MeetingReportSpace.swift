import SwiftUI
import SwiftData

/// Les invites des blocs optionnels vides (plan §5, lot 15 n° 6 : « afficher
/// une invite plutôt qu'une section vide »).
///
/// Séparées de la vue pour être vérifiables sans monter SwiftUI, et parce que
/// la règle est du métier : ce n'est pas au rendu de décider quand un manque
/// mérite d'être signalé. Une case décochée n'invite à rien — l'utilisateur a
/// déjà répondu à la question.
@MainActor
enum MeetingReportSpaceInvites {

    static func forMeeting(_ meeting: Meeting) -> [String] {
        var invites: [String] = []
        let options = meeting.reportAttachmentOptions
        if options.attachPinned, ReportOptionalBlocks.pinnedPieces(of: meeting).isEmpty {
            invites.append(ReportOptionalBlocks.pinnedEmptyInvite)
        }
        if ReportOptionalBlocks.captures(of: meeting).isEmpty {
            invites.append(ReportOptionalBlocks.capturesEmptyInvite)
        }
        return invites
    }
}

/// L'espace `Rapport` (spec §1.1). Extrait tel quel de `MeetingView` : aperçu
/// HTML, éditeur markdown, éditeur de décisions, en-tête du rapport et renvoi
/// vers le panneau d'actions.
///
/// Deux changements par rapport à l'ancien onglet :
///
/// 1. Le `ContentUnavailableView` (« Aucun rapport ») devient une
///    `MeetingEmptyInvite` avec un bouton : le critère d'acceptation n° 1
///    demande une invite d'action, pas le constat d'un manque.
/// 2. Le bandeau d'avertissement passe aux jetons `One2OneToken` — aucune
///    couleur hors de la table.
///
/// La refonte du bloc rapport lui-même (citations, blocs de sources) est le
/// lot 15 ; ici, seule la coquille change.
struct MeetingReportSpace<Toolbar: View>: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    /// Mode édition markdown du rapport.
    @Binding var editMode: Bool
    /// Sauvegarde différée (l'éditeur écrit à chaque frappe).
    let debouncedSave: () -> Void
    /// Sauvegarde immédiate.
    let saveNow: () -> Void
    /// Lance la génération du rapport.
    let onGenerate: () -> Void
    /// La barre « Template · Aperçu/Éditer · Générer », restée dans
    /// `MeetingView` : elle lit l'état de génération, qui y vit.
    @ViewBuilder let toolbar: Toolbar

    var body: some View {
        VStack(spacing: 0) {
            if !meeting.reportRevisions.isEmpty, meeting.rawTranscript.isEmpty {
                avertissementTranscriptionPerdue
            }

            if meeting.summary.isEmpty {
                MeetingEmptyInvite(
                    space: .report,
                    mode: .review,
                    libelleAction: meeting.rawTranscript.isEmpty && !meeting.hasPlayableAudio
                        ? nil
                        : "Générer le rapport",
                    action: meeting.rawTranscript.isEmpty && !meeting.hasPlayableAudio
                        ? nil
                        : onGenerate
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                toolbar
                    .padding(.horizontal, 8).padding(.top, 4)
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
                invitesBlocsVides
                if editMode {
                    editeur
                } else {
                    MeetingReportPreview(html: ReportHTMLBuilder.build(
                        meeting: meeting,
                        template: meeting.reportTemplate,
                        includeTranscript: false,
                        managerName: settings.ownerName,
                        managerRole: settings.ownerRole
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// Les blocs optionnels que le rapport ne peut pas remplir, dits une fois
    /// en tête plutôt qu'en sections vides dans le document.
    @ViewBuilder
    private var invitesBlocsVides: some View {
        let invites = MeetingReportSpaceInvites.forMeeting(meeting)
        if !invites.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(invites, id: \.self) { invite in
                    Text(invite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    /// Une transcription supprimée par l'éditeur audio laisse un rapport
    /// orphelin : le dire, sinon la régénération semble impossible sans raison.
    private var avertissementTranscriptionPerdue: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(One2OneToken.warn)
            Text("Transcription supprimée après édition audio — re-transcrire pour mettre à jour le rapport.")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.warnInk)
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                .fill(One2OneToken.warnBg)
        )
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private var editeur: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MarkdownEditorView(
                    text: Binding(
                        get: { meeting.summary },
                        set: { meeting.summary = $0; debouncedSave() }
                    ),
                    textViewID: "reportEditor.\(meeting.persistentModelID.hashValue)"
                )
                .frame(minHeight: 280)

                Rectangle().fill(One2OneToken.hair).frame(height: 1)
                decisionsEditor
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
                metaHeaderEditor
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
                actionsNotice
            }
            .padding(12)
        }
    }

    // MARK: - Décisions

    @ViewBuilder
    private var decisionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("DÉCISIONS").sectionLabel()
                MonoMeta("\(meeting.decisions.count)", emphase: !meeting.decisions.isEmpty)
                Spacer()
                Button {
                    meeting.decisions.append("")
                    saveNow()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(One2OneToken.action)
                }
                .buttonStyle(.plain)
                .help("Ajouter une décision")
            }

            if meeting.decisions.isEmpty {
                Text("Aucune décision. Ces lignes apparaîtront automatiquement comme tableau « Relevé de décisions » dans le rapport.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(meeting.decisions.enumerated()), id: \.offset) { idx, _ in
                    HStack(spacing: 6) {
                        Text("D\(idx + 1)")
                            .font(.plexMono(10))
                            .foregroundStyle(One2OneToken.ink4)
                            .frame(width: 28, alignment: .leading)
                        TextField("Décision…", text: Binding(
                            get: { idx < meeting.decisions.count ? meeting.decisions[idx] : "" },
                            set: { newValue in
                                guard idx < meeting.decisions.count else { return }
                                meeting.decisions[idx] = newValue
                                debouncedSave()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button {
                            guard idx < meeting.decisions.count else { return }
                            meeting.decisions.remove(at: idx)
                            saveNow()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(One2OneToken.ink4)
                        }
                        .buttonStyle(.plain)
                        .help("Supprimer cette décision")
                    }
                }
            }
        }
    }

    // MARK: - En-tête du rapport

    @ViewBuilder
    private var metaHeaderEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EN-TÊTE DU RAPPORT").sectionLabel()

            champ("Référencés (non présents)",
                  placeholder: "ex: Zied · Nicolas Hauvinet · Travaux McKinsey",
                  valeur: Binding(
                    get: { meeting.referencedAbsent },
                    set: { meeting.referencedAbsent = $0; debouncedSave() }
                  ))

            champ("Prochaine échéance",
                  placeholder: "ex: Partage du modèle puis présentation McKinsey",
                  valeur: Binding(
                    get: { meeting.nextDeadline },
                    set: { meeting.nextDeadline = $0; debouncedSave() }
                  ))
        }
    }

    private func champ(_ libelle: String,
                       placeholder: String,
                       valeur: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(libelle)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink4)
            TextField(placeholder, text: valeur)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Renvoi vers le panneau d'actions

    @ViewBuilder
    private var actionsNotice: some View {
        HStack(spacing: 7) {
            Text("PLAN D'ACTIONS").sectionLabel()
            MonoMeta("\(meeting.tasks.count)", emphase: !meeting.tasks.isEmpty)
            Spacer()
            Text("↗ Éditer dans l'espace Réunion, mode Relire")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
        }
        .padding(.vertical, 4)
    }
}
