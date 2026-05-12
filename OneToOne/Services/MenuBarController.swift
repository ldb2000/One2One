import AppKit
import SwiftUI
import Combine
import SwiftData

@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private weak var container: ModelContainer?

    func install(container: ModelContainer) {
        self.container = container

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "calendar.badge.clock",
                                            accessibilityDescription: "OneToOne agenda")
        statusItem?.menu = NSMenu()  // populated on refresh

        CalendarAgendaService.shared.$eventsToday
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    func uninstall() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Refresh

    private func refresh() {
        guard let item = statusItem else { return }
        let settings = currentSettings()
        guard settings?.menubarEnabled ?? true else {
            item.button?.title = ""
            item.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)
            item.menu = buildMenu(settings: settings)
            return
        }

        let upcoming = CalendarAgendaService.shared.nextUpcoming
        item.button?.title = statusTitle(for: upcoming, settings: settings)
        item.menu = buildMenu(settings: settings)
    }

    private func statusTitle(for event: CalendarMeetingEvent?,
                             settings: AppSettings?) -> String {
        guard settings?.menubarShowNextTitle ?? true else { return "" }
        guard let event else { return "" }
        let now = Date()
        let maxChars = settings?.menubarMaxTitleChars ?? 25
        let title = truncated(event.title, to: maxChars)

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"

        if event.startDate <= now && event.endDate >= now {
            let mins = Int(event.endDate.timeIntervalSince(now) / 60)
            return "● \(title) (\(mins)m)"
        }
        let minutesUntil = Int(event.startDate.timeIntervalSince(now) / 60)
        if minutesUntil < 30 && minutesUntil >= 0 {
            return "Dans \(minutesUntil) min: \(title)"
        }
        return "\(title) · \(fmt.string(from: event.startDate))"
    }

    private func truncated(_ s: String, to max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    private func buildMenu(settings: AppSettings?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: dayHeader(Date()), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let events = CalendarAgendaService.shared.eventsToday
        if events.isEmpty {
            let none = NSMenuItem(title: "(aucune réunion)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for event in events {
                menu.addItem(makeEventItem(event))
            }
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Ouvrir OneToOne",
                                  action: #selector(openMainWindow),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quitter",
                                  action: #selector(NSApp.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }

    private func makeEventItem(_ event: CalendarMeetingEvent) -> NSMenuItem {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let title = "\(fmt.string(from: event.startDate))  \(event.title)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if event.isCancelled {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: NSColor.secondaryLabelColor]
            )
        }

        let submenu = NSMenu()
        if event.teamsJoinURL != nil {
            let join = NSMenuItem(title: "Rejoindre Teams", action: #selector(joinTeams(_:)), keyEquivalent: "")
            join.target = self
            join.representedObject = event.id
            submenu.addItem(join)
        } else {
            let none = NSMenuItem(title: "(pas de lien Teams)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        let open = NSMenuItem(title: "Ouvrir dans OneToOne", action: #selector(openEvent(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = event.id
        submenu.addItem(open)
        item.submenu = submenu
        return item
    }

    private func dayHeader(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "'Aujourd''hui · 'EEEE d MMMM"
        return fmt.string(from: date).capitalized
    }

    private func currentSettings() -> AppSettings? {
        guard let context = container?.mainContext else { return nil }
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Actions

    @objc private func joinTeams(_ sender: NSMenuItem) {
        guard let eventID = sender.representedObject as? String,
              let event = CalendarAgendaService.shared.eventsToday.first(where: { $0.id == eventID }),
              let url = event.teamsJoinURL,
              let context = container?.mainContext else { return }
        TeamsLauncher.open(url)

        // Ensure the meeting is imported in-app (idempotent).
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        let meeting: Meeting
        if let existing = (try? context.fetch(descriptor))?.first {
            meeting = existing
        } else if let settings = currentSettings() {
            let importer = CalendarMeetingImportService()
            meeting = importer.importEvent(event, context: context, settings: settings)
            try? context.save()
        } else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .openMeetingFromAgenda,
            object: nil,
            userInfo: ["meetingID": meeting.persistentModelID.storeIdentifier ?? ""]
        )
    }

    @objc private func openEvent(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        guard let eventID = sender.representedObject as? String,
              let context = container?.mainContext else { return }
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            NotificationCenter.default.post(
                name: .openMeetingFromAgenda,
                object: nil,
                userInfo: ["meetingID": existing.persistentModelID.storeIdentifier ?? ""]
            )
        } else if let event = CalendarAgendaService.shared.eventsToday.first(where: { $0.id == eventID }) {
            guard let settings = currentSettings() else { return }
            let importer = CalendarMeetingImportService()
            let meeting = importer.importEvent(event, context: context, settings: settings)
            try? context.save()
            NotificationCenter.default.post(
                name: .openMeetingFromAgenda,
                object: nil,
                userInfo: ["meetingID": meeting.persistentModelID.storeIdentifier ?? ""]
            )
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title.isEmpty == false {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
