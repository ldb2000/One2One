import Foundation
import UserNotifications
import SwiftData
import AppKit

@MainActor
final class MeetingNotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = MeetingNotificationService()

    private let center = UNUserNotificationCenter.current()

    private enum Category {
        static let start = "MEETING_START"
        static let end   = "MEETING_END"
    }

    private enum Action {
        static let open  = "OPEN_MEETING"
    }

    /// Posted when the user taps "Open" on a meeting notification. UserInfo
    /// carries `meetingID` (PersistentIdentifier.storeIdentifier as String).
    static let openMeetingNotification = Notification.Name("OneToOne.MeetingNotificationService.openMeeting")

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
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

        let userInfo: [AnyHashable: Any] = [
            "meetingID": meeting.ensuredStableID.uuidString
        ]

        if settings.notifMeetingStart, start > Date() {
            schedule(id: baseID + ".start",
                     title: "Réunion: \(meeting.title)",
                     body: "Démarre maintenant",
                     fireAt: start,
                     category: Category.start,
                     userInfo: userInfo)
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
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: Self.openMeetingNotification,
                                            object: nil,
                                            userInfo: ["meetingID": meetingID])
        }
        completionHandler()
    }

    // MARK: - Internals

    private func registerCategories() {
        let openAction = UNNotificationAction(identifier: Action.open,
                                              title: "Ouvrir",
                                              options: [.foreground])
        let startCat = UNNotificationCategory(identifier: Category.start,
                                              actions: [openAction],
                                              intentIdentifiers: [])
        let endCat = UNNotificationCategory(identifier: Category.end,
                                             actions: [openAction],
                                             intentIdentifiers: [])
        center.setNotificationCategories([startCat, endCat])
    }

    private func schedule(id: String, title: String, body: String,
                          fireAt: Date, category: String?, userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
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

    private func idPrefix(for meeting: Meeting) -> String {
        "meeting.\(meeting.ensuredStableID.uuidString)"
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
