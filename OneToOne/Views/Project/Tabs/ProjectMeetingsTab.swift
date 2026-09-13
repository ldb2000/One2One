import SwiftUI
import SwiftData

/// L'onglet « Réunions & CR » de l'écran projet : toutes les réunions tenues
/// du projet, de la plus récente à la plus ancienne.
///
/// **Une liste aux jetons, et non les lignes de `MeetingsListView`.** Celles-ci
/// (`MeetingRowView`) sont écrites en fonte système et en couleurs système ;
/// `Views/Project/` est dans le périmètre Plex (décision **D17**), et les
/// reprendre aurait fait entrer la fonte système dans l'écran par la porte
/// d'un composant partagé — exactement ce que le garde-fou typographique
/// empêche. Les extraire proprement demanderait de retoucher la liste des
/// réunions, ce qui n'est pas l'intention de ce lot.
struct ProjectMeetingsTab: View {

    static let vide = "Aucune réunion tenue sur ce projet."
    static let largeurDate: CGFloat = 64
    static let tailleDate: CGFloat = 11
    static let tailleTitre: CGFloat = 13
    static let tailleResume: CGFloat = 12

    let lignes: [ProjectMeetingRow]
    let onOuvrir: (ProjectMeetingRow) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if lignes.isEmpty {
                    Text(Self.vide)
                        .font(.plexSans(12.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .padding(.vertical, 12)
                } else {
                    PilotageCard(marges: nil) {
                        ForEach(Array(lignes.enumerated()), id: \.element.id) { rang, ligne in
                            row(ligne).pilotageRowSeparator(rang < lignes.count - 1)
                        }
                    }
                }
            }
            .padding(.horizontal, PilotageTab.margeH)
            .padding(.top, PilotageTab.margeHaute)
            .padding(.bottom, PilotageTab.margeBasse)
        }
    }

    private func row(_ ligne: ProjectMeetingRow) -> some View {
        Button { onOuvrir(ligne) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(ligne.dateLabel)
                    .font(.plexMono(Self.tailleDate, .medium))
                    .foregroundStyle(One2OneToken.ink4)
                    .frame(width: Self.largeurDate, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let badge = ligne.badge {
                            MeetingTypeBadgeView(badge: badge)
                        }
                        Text(ligne.titre)
                            .font(.plexSans(Self.tailleTitre))
                            .foregroundStyle(One2OneToken.ink1)
                            .lineLimit(1)
                    }
                    if !ligne.resume.isEmpty {
                        Text(ligne.resume)
                            .font(.plexSans(Self.tailleResume))
                            .foregroundStyle(One2OneToken.ink3)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PilotageMetrics.margeH)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir « \(ligne.titre) »")
    }
}

/// Une ligne de l'onglet « Réunions & CR ».
///
/// Même forme que `ProjectPilotageState.MeetingRow`, avec la date complète :
/// la carte de pilotage montre trois réunions du trimestre (« 08/09 » suffit),
/// l'onglet montre tout l'historique et doit dire l'année.
struct ProjectMeetingRow: Identifiable, Equatable, Sendable {
    var id: PersistentIdentifier
    var stableID: UUID?
    var dateLabel: String
    var badge: MeetingTypeBadge?
    var titre: String
    var resume: String

    @MainActor
    init(_ meeting: Meeting) {
        id = meeting.persistentModelID
        stableID = meeting.stableID
        dateLabel = ProjectPilotageBuilder.jourMoisAnnee(meeting.date)
        badge = MeetingTypeBadge.from(meeting)
        titre = meeting.title.isEmpty ? "Réunion sans titre" : meeting.title
        resume = ProjectPilotageBuilder.resumeDeDecision(meeting)
    }
}
