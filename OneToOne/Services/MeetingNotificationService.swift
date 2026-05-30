import Foundation
import UserNotifications
import SwiftData
import AppKit

@MainActor
final class MeetingNotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = MeetingNotificationService()

    private let center = UNUserNotificationCenter.current()

    private enum Category {
        static let preStart = "MEETING_PRE_START"  // Outlook-style "starts in N min"
        static let start    = "MEETING_START"
        static let end      = "MEETING_END"
        static let recording = "RECORDING_STARTED"
    }

    private enum Action {
        static let open  = "OPEN_MEETING"
        static let teams = "JOIN_TEAMS"
        static let snooze5 = "SNOOZE_5"
    }

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
        guard let meetingID = userInfo["meetingID"] as? String, !meetingID.isEmpty else {
            completionHandler()
            return
        }
        let teamsURL = userInfo["teamsURL"] as? String
        let actionID = response.actionIdentifier

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

    // MARK: - Internals

    private func registerCategories() {
        let openAction = UNNotificationAction(identifier: Action.open,
                                              title: "Ouvrir",
                                              options: [.foreground])
        let teamsAction = UNNotificationAction(identifier: Action.teams,
                                               title: "Rejoindre Teams",
                                               options: [.foreground])
        let snoozeAction = UNNotificationAction(identifier: Action.snooze5,
                                                title: "Rappeler dans 5 min",
                                                options: [])
        let preStartCat = UNNotificationCategory(identifier: Category.preStart,
                                                  actions: [teamsAction, openAction, snoozeAction],
                                                  intentIdentifiers: [])
        let startCat = UNNotificationCategory(identifier: Category.start,
                                              actions: [teamsAction, openAction],
                                              intentIdentifiers: [])
        let endCat = UNNotificationCategory(identifier: Category.end,
                                             actions: [openAction],
                                             intentIdentifiers: [])
        let recordingCat = UNNotificationCategory(identifier: Category.recording,
                                          actions: [],
                                          intentIdentifiers: [])
        center.setNotificationCategories([preStartCat, startCat, endCat, recordingCat])
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

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
