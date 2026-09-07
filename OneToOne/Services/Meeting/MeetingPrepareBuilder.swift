import Foundation
import SwiftData

/// Ce que le mode Préparer met dans sa colonne principale (spec §2.2) :
/// « Actions ouvertes reportées + derniers points + alertes ».
struct MeetingPrepareContext: Equatable, Sendable {

    /// Une action reportée d'une réunion antérieure.
    struct CarriedAction: Equatable, Sendable, Identifiable {
        var id: PersistentIdentifier
        var title: String
        /// Titre de la réunion d'où elle vient — le « REPORTÉES DU <date> » de
        /// la spec §2.5 a besoin de savoir d'où.
        var fromTitle: String
        var fromDate: Date?
        var deferralCount: Int
    }

    /// Un « dernier point » : titre, date et résumé en une phrase.
    struct LastPoint: Equatable, Sendable, Identifiable {
        var id: PersistentIdentifier
        var title: String
        var date: Date
        var shortSummary: String
    }

    var carriedActions: [CarriedAction] = []
    /// Trois au plus, de la plus récente à la plus ancienne.
    var lastPoints: [LastPoint] = []
    var alertTitles: [String] = []
}

/// Assemble le contenu du mode Préparer. Aucune écriture : le versement des
/// sujets permanents reste à `PrepCarryoverService.drainStandingIntoMeeting`,
/// appelé par la vue à son apparition — comme le faisait l'onglet Préparation.
enum MeetingPrepareBuilder {

    /// Nombre de réunions passées affichées dans « DERNIERS POINTS »
    /// (spec §5 lot 1 : « 3 dernières réunions du même projet »).
    static let lastPointsCount = 3

    @MainActor
    static func build(meeting: Meeting, allMeetings: [Meeting]) -> MeetingPrepareContext {
        MeetingPrepareContext(
            carriedActions: carriedActions(meeting: meeting),
            lastPoints: lastPoints(meeting: meeting, allMeetings: allMeetings),
            alertTitles: alertTitles(meeting: meeting)
        )
    }

    /// Les actions de cette réunion qui viennent d'une réunion antérieure et
    /// **restent ouvertes** : une action reportée puis close n'est plus un
    /// sujet de préparation.
    @MainActor
    private static func carriedActions(meeting: Meeting) -> [MeetingPrepareContext.CarriedAction] {
        meeting.tasks
            .filter { $0.carriedFromMeeting != nil && !$0.isCompleted }
            .sorted { gauche, droite in
                // Les plus reportées d'abord : ce sont celles qui traînent.
                if gauche.deferralCount != droite.deferralCount {
                    return gauche.deferralCount > droite.deferralCount
                }
                return gauche.title.localizedCaseInsensitiveCompare(droite.title) == .orderedAscending
            }
            .map { tache in
                MeetingPrepareContext.CarriedAction(
                    id: tache.persistentModelID,
                    title: tache.title,
                    fromTitle: tache.carriedFromMeeting?.title ?? "",
                    fromDate: tache.carriedFromMeeting?.date,
                    deferralCount: tache.deferralCount
                )
            }
    }

    /// Les trois dernières réunions **du même projet**, antérieures à celle-ci.
    ///
    /// Une réunion postérieure n'est pas un « dernier point » : la liste est
    /// filtrée sur la date et pas seulement triée, sinon préparer une réunion
    /// déjà planifiée pour la semaine suivante ferait remonter l'avenir.
    @MainActor
    private static func lastPoints(meeting: Meeting,
                                   allMeetings: [Meeting]) -> [MeetingPrepareContext.LastPoint] {
        guard let projet = meeting.project else { return [] }
        return allMeetings
            .filter { autre in
                autre.persistentModelID != meeting.persistentModelID
                    && autre.project?.persistentModelID == projet.persistentModelID
                    && autre.date < meeting.date
            }
            .sorted { $0.date > $1.date }
            .prefix(lastPointsCount)
            .map { autre in
                MeetingPrepareContext.LastPoint(
                    id: autre.persistentModelID,
                    title: autre.title,
                    date: autre.date,
                    shortSummary: autre.shortSummary
                )
            }
    }

    /// Les alertes non résolues du projet. Les alertes propres à la réunion
    /// (`meetingAlerts`) nourrissent le KPI Risques ; ici c'est le contexte du
    /// dossier qu'on prépare.
    @MainActor
    private static func alertTitles(meeting: Meeting) -> [String] {
        guard let projet = meeting.project else { return [] }
        return projet.alerts
            .filter { !$0.isResolved }
            .sorted { MeetingKPIBuilder.level(fromSeverity: $0.severity)
                        < MeetingKPIBuilder.level(fromSeverity: $1.severity) }
            .map(\.title)
    }
}
