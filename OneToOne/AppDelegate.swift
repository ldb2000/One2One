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

    /// Generates the Dock icon at runtime — squircle background with a
    /// meeting-themed SF Symbol on top. SwiftPM exec targets package
    /// resources into a sub-bundle so a static .icns isn't reachable via
    /// CFBundleIconFile anyway.
    private func installAppIcon() {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)
        image.lockFocus()

        // 1. Squircle background gradient (indigo → orange, macOS Big Sur style).
        let cornerRadius: CGFloat = 230
        let bgRect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
        let gradient = NSGradient(colors: [
            NSColor(red: 0.30, green: 0.38, blue: 0.86, alpha: 1.0),  // indigo
            NSColor(red: 0.93, green: 0.45, blue: 0.27, alpha: 1.0)   // orange
        ])
        path.addClip()
        gradient?.draw(in: bgRect, angle: -45)

        // 2. Inner soft glow ring (white at 12% opacity).
        let ring = NSBezierPath(
            roundedRect: bgRect.insetBy(dx: 70, dy: 70),
            xRadius: cornerRadius - 50, yRadius: cornerRadius - 50
        )
        NSColor.white.withAlphaComponent(0.12).setStroke()
        ring.lineWidth = 12
        ring.stroke()

        // 3. Foreground symbol — three people (meeting), tinted white.
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
        let combined = sizeConfig.applying(paletteConfig)
        if let symbol = NSImage(systemSymbolName: "person.3.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(combined) {
            let symbolRect = NSRect(
                x: (size.width - symbol.size.width) / 2,
                y: (size.height - symbol.size.height) / 2 - 30,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)
        }

        image.unlockFocus()
        NSApp.applicationIconImage = image
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
