import SwiftUI
import SwiftData

/// L'onglet `Risques` du rail (spec §2.5) : les `ProjectAlert` soulevées par la
/// réunion, puis celles du projet, « point coloré par sévérité, ajout inline ».
///
/// Les risques de la réunion d'abord : ce sont ceux dont on vient de parler.
/// Ceux du projet suivent, en rappel — sans eux, un risque ouvert au COPIL
/// précédent disparaîtrait de la vue au moment précis où il faut le rouvrir.
///
/// La lecture de la sévérité et sa teinte sont celles du bandeau
/// d'indicateurs (`MeetingKPIBuilder.level(fromSeverity:)`,
/// `MeetingKPIBand.teinte(_:)`) : deux définitions finiraient par peindre le
/// même risque de deux couleurs selon l'endroit de l'écran.
struct ActionsRailRisks: View {

    @Bindable var meeting: Meeting
    let onSave: () -> Void

    /// Les valeurs brutes historiques de `ProjectAlert.severityRaw`, dans
    /// l'ordre de gravité décroissante.
    static let severites = ["Critique", "Élevé", "Modéré", "Faible"]

    @Environment(\.modelContext) private var context
    /// Le champ d'ajout est déplié. Inline, jamais une modale : c'est la même
    /// règle que pour les actions.
    @State private var ajoutOuvert = false
    @State private var nouveauRisque = ""
    @State private var graviteChoisie = "Modéré"
    @FocusState private var champRisque: Bool

    /// Les risques de la réunion, du plus grave au plus faible.
    private var risquesDeLaReunion: [ProjectAlert] {
        Self.triees(meeting.meetingAlerts.filter { !$0.isResolved })
    }

    /// Les risques ouverts du projet que la réunion n'a pas elle-même
    /// soulevés — le rappel.
    private var risquesDuProjet: [ProjectAlert] {
        let dejaListes = Set(meeting.meetingAlerts.map(\.persistentModelID))
        let alertes = (meeting.project?.alerts ?? [])
            .filter { !$0.isResolved && !dejaListes.contains($0.persistentModelID) }
        return Self.triees(alertes)
    }

    /// Tri par gravité décroissante, puis par date décroissante.
    static func triees(_ alertes: [ProjectAlert]) -> [ProjectAlert] {
        alertes.sorted { gauche, droite in
            let ng = MeetingKPIBuilder.level(fromSeverity: gauche.severity)
            let nd = MeetingKPIBuilder.level(fromSeverity: droite.severity)
            if ng != nd { return ng < nd }        // `Level` est ordonné du plus grave
            return gauche.date > droite.date
        }
    }

    /// Teinte du point de sévérité, celle du bandeau d'indicateurs.
    static func teinte(_ severite: String) -> Color {
        MeetingKPIBand.teinte(MeetingKPIBuilder.level(fromSeverity: severite))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if risquesDeLaReunion.isEmpty && risquesDuProjet.isEmpty && !ajoutOuvert {
                MeetingEmptyInvite(
                    titre: "Aucun risque ouvert",
                    invite: "Un point de vigilance qui revient deux fois est un risque — notez-le ici.",
                    libelleAction: "＋ Ajouter un risque",
                    action: ouvrirAjout
                )
                .padding(.vertical, 12)
            } else {
                if !risquesDeLaReunion.isEmpty {
                    section("Soulevés en séance — \(risquesDeLaReunion.count)",
                            alertes: risquesDeLaReunion)
                }
                if !risquesDuProjet.isEmpty {
                    section("Ouverts sur le projet — \(risquesDuProjet.count)",
                            alertes: risquesDuProjet)
                }
                if ajoutOuvert {
                    champDAjout
                } else {
                    InvitePill("＋ Ajouter un risque", action: ouvrirAjout)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ libelle: String, alertes: [ProjectAlert]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                SectionLabel(libelle)
                Spacer(minLength: 0)
            }
            ForEach(alertes) { alerte in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(Self.teinte(alerte.severity))
                        .frame(width: MeetingKPIBand.riskDot, height: MeetingKPIBand.riskDot)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alerte.title)
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !alerte.detail.isEmpty {
                            Text(alerte.detail)
                                .font(.plexSans(10.5))
                                // 10,5 px : `ink/4` (spec §1.2).
                                .foregroundStyle(One2OneToken.ink4)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        alerte.isResolved = true
                        onSave()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9))
                            .foregroundStyle(One2OneToken.ink4)
                    }
                    .buttonStyle(.plain)
                    .help("Marquer le risque résolu")
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Ajout inline

    private func ouvrirAjout() {
        ajoutOuvert = true
        champRisque = true
    }

    private var champDAjout: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("Nouveau risque…", text: $nouveauRisque)
                .textFieldStyle(.plain)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink1)
                .focused($champRisque)
                .onSubmit(creer)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
                )
            HStack(spacing: 5) {
                ForEach(Self.severites, id: \.self) { severite in
                    Button {
                        graviteChoisie = severite
                    } label: {
                        Text(severite)
                            .font(.plexSans(10.5, .medium))
                            .foregroundStyle(graviteChoisie == severite
                                             ? One2OneToken.onFilledButton
                                             : One2OneToken.ink4)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(graviteChoisie == severite
                                          ? Self.teinte(severite)
                                          : One2OneToken.surfaceAlt)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button("Annuler") {
                    nouveauRisque = ""
                    ajoutOuvert = false
                }
                .buttonStyle(.plain)
                .font(.plexSans(10.5))
                .foregroundStyle(One2OneToken.ink4)
            }
        }
    }

    private func creer() {
        let titre = nouveauRisque.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titre.isEmpty else { return }
        let alerte = ProjectAlert(title: titre, severity: graviteChoisie)
        context.insert(alerte)
        alerte.meeting = meeting
        alerte.project = meeting.project
        onSave()
        nouveauRisque = ""
        // Le champ reste ouvert et focalisé : un risque en amène souvent un
        // second, et refermer obligerait à re-cliquer.
    }
}
