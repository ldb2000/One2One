import AppKit
import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar.uninstall()
    }
}
