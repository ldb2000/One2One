import Foundation
import UserNotifications
import SwiftData
import AppKit

@MainActor
final class MeetingNotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = MeetingNotificationService()

    private let center = UNUserNotificationCenter.current()

    enum Category {
        static let preStart = "MEETING_PRE_START"  // Outlook-style "starts in N min"
        static let start    = "MEETING_START"
        static let end      = "MEETING_END"
        static let recording = "RECORDING_STARTED"
    }

    enum Action {
        static let open  = "OPEN_MEETING"
        static let teams = "JOIN_TEAMS"
        static let snooze5 = "SNOOZE_5"
    }

    /// Catégories du parcours Teams auto-record (spec §5). Distinctes de
    /// `Category`, qui reste privé aux notifications de réunion.
    enum TeamsCategory {
        static let detected = "TEAMS_CALL_DETECTED"
        /// Variante émise quand un enregistrement tourne déjà : on propose de
        /// lier l'appel à la réunion en cours plutôt que d'en créer une
        /// seconde (spec D-10).
        static let link = "TEAMS_CALL_LINK"
        static let ended = "TEAMS_CALL_ENDED"
        static let transcriptReady = "TEAMS_TRANSCRIPT_READY"
        static let error = "TEAMS_RECORDING_ERROR"
    }

    /// Actions du parcours Teams. Les identifiants voyagent jusqu'au
    /// coordinateur via `teamsActionNotification`.
    enum TeamsAction {
        static let startRecord = "START_RECORD"
        static let linkToCurrent = "LINK_TO_CURRENT"
        static let snooze5 = "SNOOZE_TEAMS_5"
        static let dismiss = "DISMISS_TEAMS"
        static let stopAndFinalize = "STOP_AND_FINALIZE"
        static let continueRecording = "CONTINUE_RECORDING"
        static let generateReport = "GENERATE_REPORT"
        static let skipReport = "SKIP_REPORT"
        static let retrySTT = "RETRY_STT"
    }

    /// Posted quand l'utilisateur touche une action du parcours Teams.
    /// `userInfo` porte `actionID: String` et, si connue, `meetingID: String`.
    static let teamsActionNotification = Notification.Name("OneToOne.MeetingNotificationService.teamsAction")

    /// Posted when the user taps "Open" on a meeting notification. UserInfo
    /// carries `meetingID` (PersistentIdentifier.storeIdentifier as String).
    static let openMeetingNotification = Notification.Name("OneToOne.MeetingNotificationService.openMeeting")

    /// Posted on "Snooze 5" action — caller (AppDelegate) re-schedules a
    /// prestart 5 min from now. UserInfo carries `meetingID`.
    static let snoozeMeetingNotification = Notification.Name("OneToOne.MeetingNotificationService.snoozeMeeting")

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            return false
        }
    }

    /// Schedules (or re-schedules) start / endWarning / end notifications
    /// for a Meeting that has `scheduledStart` & `scheduledEnd` set.
    func schedule(for meeting: Meeting, settings: AppSettings) {
        guard let start = meeting.scheduledStart,
              let end = meeting.scheduledEnd,
              end > start else { return }

        let baseID = idPrefix(for: meeting)
        cancel(for: meeting)  // idempotent — drop any previous pending

        var userInfo: [AnyHashable: Any] = [
            "meetingID": meeting.ensuredStableID.uuidString
        ]
        if let teams = meeting.teamsJoinURL, !teams.isEmpty {
            userInfo["teamsURL"] = teams
        }

        // ---- Pré-rappel style Outlook (N min avant le start) ----
        if settings.notifMeetingPreStart {
            let preMinutes = max(1, settings.notifMeetingPreStartMinutes)
            let preFire = start.addingTimeInterval(TimeInterval(-preMinutes * 60))
            if preFire > Date() {
                schedule(id: baseID + ".preStart",
                         title: "Réunion dans \(preMinutes) min — \(meeting.title)",
                         body: prestartBody(for: meeting, start: start),
                         fireAt: preFire,
                         category: Category.preStart,
                         userInfo: userInfo,
                         interruptionLevel: .timeSensitive)
            }
        }

        if settings.notifMeetingStart, start > Date() {
            schedule(id: baseID + ".start",
                     title: "Réunion: \(meeting.title)",
                     body: "Démarre maintenant",
                     fireAt: start,
                     category: Category.start,
                     userInfo: userInfo,
                     interruptionLevel: .timeSensitive)
        }

        let warning = end.addingTimeInterval(-5 * 60)
        if settings.notifMeetingEndWarning, warning > Date() {
            schedule(id: baseID + ".endWarning",
                     title: "Fin dans 5 min",
                     body: "\(meeting.title) se termine à \(formatTime(end))",
                     fireAt: warning,
                     category: nil,
                     userInfo: userInfo)
        }

        if settings.notifMeetingEnd, end > Date() {
            schedule(id: baseID + ".end",
                     title: "Réunion terminée",
                     body: meeting.title,
                     fireAt: end,
                     category: Category.end,
                     userInfo: userInfo)
        }
    }

    /// Annule toutes les notifications en attente d'une réunion (preStart,
    /// start, endWarning, end). Idempotent — sûr à appeler à tout moment.
    func cancel(for meeting: Meeting) {
        let base = idPrefix(for: meeting)
        center.removePendingNotificationRequests(withIdentifiers: [
            base + ".preStart",
            base + ".start",
            base + ".endWarning",
            base + ".end"
        ])
    }

    /// Re-syncs notifications for every future-scheduled Meeting in the store.
    /// Call at app launch for reboot resilience.
    func syncPending(context: ModelContext, settings: AppSettings) {
        let now = Date()
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { meeting in
                meeting.scheduledStart != nil && meeting.scheduledStart! > now
            }
        )
        let upcoming = (try? context.fetch(descriptor)) ?? []
        for meeting in upcoming {
            schedule(for: meeting, settings: settings)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        let teamsActions: Set<String> = [
            TeamsAction.startRecord, TeamsAction.linkToCurrent,
            TeamsAction.snooze5, TeamsAction.dismiss,
            TeamsAction.stopAndFinalize, TeamsAction.continueRecording,
            TeamsAction.generateReport, TeamsAction.skipReport, TeamsAction.retrySTT
        ]
        if teamsActions.contains(actionID) {
            let teamsMeetingID = (userInfo["meetingID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            DispatchQueue.main.async {
                var info: [AnyHashable: Any] = ["actionID": actionID]
                if let teamsMeetingID { info["meetingID"] = teamsMeetingID }
                NotificationCenter.default.post(name: Self.teamsActionNotification,
                                                object: nil, userInfo: info)
            }
            completionHandler()
            return
        }
        guard let meetingID = userInfo["meetingID"] as? String, !meetingID.isEmpty else {
            completionHandler()
            return
        }
        let teamsURL = userInfo["teamsURL"] as? String

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            switch actionID {
            case Action.teams:
                // Lance Teams si URL présente, sinon fallback open meeting.
                if let s = teamsURL, let url = URL(string: s) {
                    NSWorkspace.shared.open(url)
                }
                NotificationCenter.default.post(name: Self.openMeetingNotification,
                                                object: nil,
                                                userInfo: ["meetingID": meetingID])
            case Action.snooze5:
                NotificationCenter.default.post(name: Self.snoozeMeetingNotification,
                                                object: nil,
                                                userInfo: ["meetingID": meetingID])
            default:
                // Default tap or "Ouvrir" action.
                NotificationCenter.default.post(name: Self.openMeetingNotification,
                                                object: nil,
                                                userInfo: ["meetingID": meetingID])
            }
        }
        completionHandler()
    }

    /// Reschedule un prestart "5 min" sur la réunion donnée.
    func snoozePreStart(meeting: Meeting) {
        let baseID = idPrefix(for: meeting)
        let id = baseID + ".preStart.snooze"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        var userInfo: [AnyHashable: Any] = [
            "meetingID": meeting.ensuredStableID.uuidString
        ]
        if let teams = meeting.teamsJoinURL, !teams.isEmpty {
            userInfo["teamsURL"] = teams
        }
        let fireAt = Date().addingTimeInterval(5 * 60)
        schedule(id: id,
                 title: "Rappel — \(meeting.title)",
                 body: meeting.scheduledStart.map { "Début à \(formatTime($0))" } ?? "Réunion à venir",
                 fireAt: fireAt,
                 category: Category.preStart,
                 userInfo: userInfo,
                 interruptionLevel: .timeSensitive)
    }

    /// Bannière immédiate "Enregistrement en cours". Auto-dismiss, sans action.
    func notifyRecordingStarted(meetingTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Enregistrement en cours"
        content.body = meetingTitle.isEmpty ? "Réunion en capture" : meetingTitle
        content.sound = .default
        content.categoryIdentifier = Category.recording
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let id = "recording.start.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("[MeetingNotificationService] recording: \(error)") }
        }
    }

    /// Popup « appel Teams détecté ». `meetingStableID` peut être vide tant
    /// que la réunion n'existe pas : le coordinateur la crée à l'acceptation.
    func notifyTeamsCallDetected(eventTitle: String, meetingStableID: String) {
        postTeams(category: TeamsCategory.detected,
                  title: "Appel Teams détecté : \(eventTitle)",
                  body: "Démarrer l'enregistrement dans OneToOne ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.detected")
    }

    func notifyTeamsCallEnded(meetingStableID: String) {
        postTeams(category: TeamsCategory.ended,
                  title: "Appel Teams terminé",
                  body: "Arrêter l'enregistrement et finaliser la transcription ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.ended")
    }

    func notifyTeamsTranscriptReady(segmentCount: Int, meetingStableID: String) {
        postTeams(category: TeamsCategory.transcriptReady,
                  title: "Transcription prête (\(segmentCount) segments)",
                  body: "Générer le rapport avec le provider IA ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.transcript")
    }

    /// Émission commune. Le `requestIdentifier` est dérivé du `stableID` de la
    /// réunion — **pas** de `persistentModelID`, que le modèle documente comme
    /// inutilisable en identifiant externe. Réémettre la même catégorie pour la
    /// même réunion écrase la précédente, ce qui évite les popups en double.
    private func postTeams(category: String, title: String, body: String,
                           meetingStableID: String, suffix: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["meetingID": meetingStableID]
        let id = meetingStableID.isEmpty ? "teams.\(suffix)" : "\(meetingStableID).\(suffix)"
        let request = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        center.add(request) { error in
            if let error { print("[MeetingNotificationService] teams: \(error)") }
        }
    }

    // MARK: - Internals

    private func registerCategories() {
        center.setNotificationCategories(Set(Self.makeCategories()))
    }

    /// Catalogue **unique** des catégories de l'application.
    ///
    /// `setNotificationCategories` remplace l'ensemble enregistré : tout ajout
    /// doit passer par ici, jamais par un second appel depuis un autre service.
    nonisolated static func makeCategories() -> [UNNotificationCategory] {
        let openAction = UNNotificationAction(identifier: Action.open,
                                              title: "Ouvrir", options: [.foreground])
        let teamsAction = UNNotificationAction(identifier: Action.teams,
                                               title: "Rejoindre Teams", options: [.foreground])
        let snoozeAction = UNNotificationAction(identifier: Action.snooze5,
                                                title: "Rappeler dans 5 min", options: [])

        let startRecord = UNNotificationAction(identifier: TeamsAction.startRecord,
                                               title: "Démarrer", options: [.foreground])
        let linkToCurrent = UNNotificationAction(identifier: TeamsAction.linkToCurrent,
                                                 title: "Lier à la réunion en cours",
                                                 options: [.foreground])
        let snoozeTeams = UNNotificationAction(identifier: TeamsAction.snooze5,
                                               title: "Dans 5 min", options: [])
        let dismissTeams = UNNotificationAction(identifier: TeamsAction.dismiss,
                                                title: "Ignorer", options: [.destructive])
        let stopAndFinalize = UNNotificationAction(identifier: TeamsAction.stopAndFinalize,
                                                   title: "Arrêter et finaliser", options: [.foreground])
        let continueRecording = UNNotificationAction(identifier: TeamsAction.continueRecording,
                                                     title: "Continuer l'enregistrement", options: [])
        let generateReport = UNNotificationAction(identifier: TeamsAction.generateReport,
                                                  title: "Générer le rapport", options: [.foreground])
        let skipReport = UNNotificationAction(identifier: TeamsAction.skipReport,
                                              title: "Plus tard", options: [])
        let retrySTT = UNNotificationAction(identifier: TeamsAction.retrySTT,
                                            title: "Retenter le STT", options: [.foreground])

        return [
            UNNotificationCategory(identifier: Category.preStart,
                                   actions: [teamsAction, openAction, snoozeAction],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.start,
                                   actions: [teamsAction, openAction], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.end,
                                   actions: [openAction], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.recording,
                                   actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.detected,
                                   actions: [startRecord, snoozeTeams, dismissTeams],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.link,
                                   actions: [linkToCurrent, dismissTeams],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.ended,
                                   actions: [stopAndFinalize, continueRecording],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.transcriptReady,
                                   actions: [generateReport, skipReport], intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.error,
                                   actions: [retrySTT, openAction], intentIdentifiers: [])
        ]
    }

    private func schedule(id: String, title: String, body: String,
                          fireAt: Date, category: String?,
                          userInfo: [AnyHashable: Any],
                          interruptionLevel: UNNotificationInterruptionLevel = .active) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        content.interruptionLevel = interruptionLevel
        if let category { content.categoryIdentifier = category }

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("[MeetingNotificationService] schedule \(id): \(error)") }
        }
    }

    /// Construit le corps du pré-rappel : heure début + Teams + participants.
    private func prestartBody(for meeting: Meeting, start: Date) -> String {
        var parts: [String] = []
        parts.append("Début à \(formatTime(start))")
        if let teams = meeting.teamsJoinURL, !teams.isEmpty {
            parts.append("Teams disponible")
        }
        let participants = meeting.participants.filter { !$0.isArchived }
        if !participants.isEmpty {
            let names = participants.prefix(3).map { $0.name }.joined(separator: ", ")
            let suffix = participants.count > 3 ? " +\(participants.count - 3)" : ""
            parts.append("Avec \(names)\(suffix)")
        }
        return parts.joined(separator: " · ")
    }

    private func idPrefix(for meeting: Meeting) -> String {
        "meeting.\(meeting.ensuredStableID.uuidString)"
    }

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
