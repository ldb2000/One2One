import AppKit
import SwiftUI
import SwiftData

/// Délégué applicatif AppKit. Orchestre le cycle de vie au lancement
/// (`applicationDidFinishLaunching`) : icône du Dock, permission notifs,
/// installation de la barre de menu, ré-armement des rappels, services
/// agenda/photos, et routage des taps de notifs/agenda vers l'ouverture du
/// meeting cible. Nettoie ses observers à la terminaison.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let menuBar = MenuBarController()
    private var notifObservers: [NSObjectProtocol] = []

    /// Point d'entrée appelé une fois au lancement : initialise icône,
    /// services et observers de notifications. Retourne tôt si le conteneur
    /// SwiftData partagé n'est pas disponible.
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
        Task {
            let granted = await ContactPhotoService.shared.requestAccess()
            await MainActor.run {
                let ctx = container.mainContext
                guard let settings = (try? ctx.fetch(FetchDescriptor<AppSettings>()))?.first,
                      settings.contactPhotoSyncEnabled, granted else { return }
                _ = ContactPhotoService.shared.syncMissingPhotos(context: ctx)
                ContactPhotoService.shared.reschedulePeriodicSync(context: ctx, settings: settings)
            }
        }

        // Scan automatique des mails (si activé dans les Réglages)
        Task { @MainActor in
            let ctx = container.mainContext
            if let settings = (try? ctx.fetch(FetchDescriptor<AppSettings>()))?.canonicalSettings {
                MailAutoIndexService.shared.reschedule(context: ctx, settings: settings)
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
        // "Rappeler dans 5 min" → snooze le pré-rappel.
        notifObservers.append(
            nc.addObserver(forName: MeetingNotificationService.snoozeMeetingNotification,
                           object: nil, queue: .main) { [weak self] note in
                self?.handleSnoozeMeeting(userInfo: note.userInfo)
            }
        )
    }

    /// Action « Rappeler dans 5 min » d'une notification : résout le meeting
    /// par son `stableID` (clé `meetingID` du `userInfo`) et reprogramme son
    /// pré-rappel. Ne fait rien si l'identifiant ou le meeting est introuvable.
    @MainActor
    private func handleSnoozeMeeting(userInfo: [AnyHashable: Any]?) {
        guard let idStr = userInfo?["meetingID"] as? String,
              let uuid = UUID(uuidString: idStr),
              let container = OneToOneApp.sharedContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        guard let meeting = all.first(where: { $0.ensuredStableID == uuid }) else { return }
        MeetingNotificationService.shared.snoozePreStart(meeting: meeting)
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

    /// Routage d'un tap de notification ou d'agenda : extrait le `stableID`
    /// (clé `meetingID` du `userInfo`), active l'app et dépose un
    /// `OneToOneLaunchToken` dans `QuickLaunchRouter` pour ouvrir le meeting
    /// cible (sans démarrer l'enregistrement).
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
