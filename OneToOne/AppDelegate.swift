import AppKit
import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let menuBar = MenuBarController()
    private var notifObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installAppIcon()

        // Notification permission — non-blocking
        Task { _ = await MeetingNotificationService.shared.requestAuthorization() }

        guard let container = OneToOneApp.sharedContainer else { return }

        menuBar.install(container: container)

        // Re-arm pending notifs on launch (reboot resilience)
        let context = container.mainContext
        if let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            MeetingNotificationService.shared.syncPending(context: context, settings: settings)
        }

        // Bootstrap calendar agenda observer
        Task { await CalendarAgendaService.shared.bootstrap() }

        // Contact photo sync — request access + initial scan + schedule
        let containerForPhoto = container
        Task {
            let granted = await ContactPhotoService.shared.requestAccess()
            await MainActor.run {
                let ctx = containerForPhoto.mainContext
                guard let settings = (try? ctx.fetch(FetchDescriptor<AppSettings>()))?.first,
                      settings.contactPhotoSyncEnabled, granted else { return }
                _ = ContactPhotoService.shared.syncMissingPhotos(context: ctx)
                ContactPhotoService.shared.reschedulePeriodicSync(context: ctx, settings: settings)
            }
        }

        // Route notification and agenda taps to open the target Meeting
        let nc = NotificationCenter.default
        notifObservers.append(
            nc.addObserver(forName: MeetingNotificationService.openMeetingNotification,
                           object: nil, queue: .main) { [weak self] note in
                self?.handleOpenMeeting(userInfo: note.userInfo)
            }
        )
        notifObservers.append(
            nc.addObserver(forName: .openMeetingFromAgenda,
                           object: nil, queue: .main) { [weak self] note in
                self?.handleOpenMeeting(userInfo: note.userInfo)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        notifObservers.forEach(NotificationCenter.default.removeObserver)
        notifObservers.removeAll()
        menuBar.uninstall()
    }

    /// SwiftPM exec targets package resources into `OneToOne_OneToOne.bundle/`,
    /// so `CFBundleIconFile` at the top level can't find AppIcon.icns. Load it
    /// at runtime via `Bundle.module` and assign to `NSApp` — covers Dock and
    /// menu-bar app icon while the app runs.
    private func installAppIcon() {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    private func handleOpenMeeting(userInfo: [AnyHashable: Any]?) {
        guard let raw = userInfo?["meetingID"] as? String, !raw.isEmpty,
              let stableID = UUID(uuidString: raw) else { return }
        NSApp.activate(ignoringOtherApps: true)
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: stableID,
            autoStartRecording: false
        )
    }
}
