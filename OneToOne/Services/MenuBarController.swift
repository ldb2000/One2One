import AppKit
import SwiftUI
import Combine
import SwiftData

extension Notification.Name {
    static let openPrepWindow = Notification.Name("OneToOne.openPrepWindow")
    static let openCalendarMeetingPicker = Notification.Name("OneToOne.openCalendarMeetingPicker")
}

@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private weak var container: ModelContainer?

    // MARK: - Popover ivars

    private lazy var quickActionPopover = makePopover()
    private lazy var quickNotePopover = makePopover()
    private lazy var urgentActionPopover = makePopover()
    private lazy var searchPopover = makePopover()
    private var urgentTaskForPopover: ActionTask?
    private var dbChangeObserver: NSObjectProtocol?
    /// Ephemeral map rebuilt on every `buildMenu` call; keys are per-session UUIDs.
    private var urgentTaskByKey: [String: ActionTask] = [:]

    private func makePopover() -> NSPopover {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        return p
    }

    private func show(_ popover: NSPopover, content: NSViewController) {
        popover.contentViewController = content
        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func hostingController<V: View>(_ view: V) -> NSViewController {
        guard let container = container else {
            return NSHostingController(rootView: AnyView(Text("Container unavailable")))
        }
        let host = NSHostingController(rootView:
            AnyView(view
                .environment(\.modelContext, container.mainContext)
            )
        )
        host.view.frame.size = NSSize(width: 360, height: 220)
        return host
    }

    // MARK: - Lifecycle

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

        dbChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    func uninstall() {
        if let obs = dbChangeObserver { NotificationCenter.default.removeObserver(obs) }
        dbChangeObserver = nil
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
        let base = statusTitle(for: upcoming, settings: settings)
        item.button?.title = base + badgeSuffix()
        item.menu = buildMenu(settings: settings)
    }

    private func badgeSuffix() -> String {
        guard let container = container else { return "" }
        let urgent = UrgentActionsSelector.qualifying(in: container.mainContext)
        let hasOverdue = urgent.contains { task in
            guard let due = task.dueDate else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }
        return MenubarBadgeText.suffix(urgentCount: urgent.count, hasOverdue: hasOverdue)
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

    // MARK: - Menu building

    private func buildMenu(settings: AppSettings?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // --- Header
        let header = NSMenuItem(title: dayHeader(Date()), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // --- Quick actions
        appendQuickActions(to: menu, settings: settings)
        menu.addItem(.separator())

        // --- Today section
        appendTodaySection(to: menu)
        menu.addItem(.separator())

        // --- Urgent actions
        appendUrgentSection(to: menu)

        // --- Search
        let searchItem = NSMenuItem(title: "🔍 Rechercher…",
                                    action: #selector(showSearch),
                                    keyEquivalent: "f")
        searchItem.target = self
        menu.addItem(searchItem)

        // --- Stats footer
        appendStatsFooter(to: menu)

        // --- Préparer submenu
        let prepItem = NSMenuItem(title: "Préparer…", action: nil, keyEquivalent: "")
        prepItem.submenu = buildPrepSubmenu()
        menu.addItem(prepItem)

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

    private func appendQuickActions(to menu: NSMenu, settings: AppSettings?) {
        let newMeeting = NSMenuItem(title: "+  Nouvelle réunion",
                                    action: #selector(startAdHoc),
                                    keyEquivalent: "")
        newMeeting.target = self
        menu.addItem(newMeeting)

        // 1:1 submenu
        let one2one = NSMenuItem(title: "+  Démarrer 1:1", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let favorites = favoriteCollaborators()
        if favorites.isEmpty {
            let none = NSMenuItem(title: "(aucun favori — épinglez depuis Collaborateurs)",
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            for c in favorites {
                let item = NSMenuItem(title: c.name,
                                      action: #selector(startOneToOneFromMenubar(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = c.ensuredStableID.uuidString
                sub.addItem(item)
            }
        }
        one2one.submenu = sub
        menu.addItem(one2one)

        // Manager
        let mgr = NSMenuItem(title: "+  1:1 Manager",
                             action: #selector(startManager),
                             keyEquivalent: "")
        mgr.target = self
        mgr.isEnabled = managerCollaborator(settings: settings) != nil
        if !mgr.isEnabled { mgr.toolTip = "Manager non configuré dans Préférences" }
        menu.addItem(mgr)

        // Action + Note (popovers)
        let action = NSMenuItem(title: "+  Nouvelle action",
                                action: #selector(showQuickAction),
                                keyEquivalent: "")
        action.target = self
        menu.addItem(action)

        let note = NSMenuItem(title: "+  Note rapide",
                              action: #selector(showQuickNote),
                              keyEquivalent: "")
        note.target = self
        menu.addItem(note)
    }

    private func appendTodaySection(to menu: NSMenu) {
        let events = CalendarAgendaService.shared.eventsToday
        let remaining = events.filter { $0.endDate > Date() && !$0.isCancelled }.count
        let header = NSMenuItem(
            title: "Aujourd'hui — \(remaining) restante(s)",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if events.isEmpty {
            let none = NSMenuItem(title: "(aucune réunion)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for event in events {
                menu.addItem(makeEventItem(event))
            }
        }
    }

    private func appendUrgentSection(to menu: NSMenu) {
        guard let container = container else { return }
        let urgent = UrgentActionsSelector.qualifying(in: container.mainContext)
        guard !urgent.isEmpty else { return }

        let header = NSMenuItem(title: "⚠  Actions urgentes (\(urgent.count))",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        urgentTaskByKey.removeAll()
        for task in urgent.prefix(3) {
            let key = UUID().uuidString
            urgentTaskByKey[key] = task
            let item = NSMenuItem(title: urgentLabel(for: task),
                                  action: #selector(showUrgent(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = key
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private func urgentLabel(for task: ActionTask) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let truncate = max(10, (currentSettings()?.menubarMaxTitleChars ?? 25))
        let truncated = task.title.count > truncate
            ? String(task.title.prefix(truncate - 1)) + "…"
            : task.title

        let suffix: String
        if let due = task.dueDate {
            if due < startOfToday { suffix = "(échéance \(fmt.string(from: due)))" }
            else { suffix = "(aujourd'hui)" }
        } else {
            suffix = "(sans date)"
        }
        return "●  \(truncated) \(suffix)"
    }

    private func appendStatsFooter(to menu: NSMenu) {
        guard let container = container else { return }
        let stats = TodayStatsCalculator.compute(in: container.mainContext)
        let hasTime = stats.tempsPasseSeconds > 0
        let hasNoProj = stats.sansProjet > 0
        guard hasTime || hasNoProj else { return }

        menu.addItem(.separator())
        let line: String
        let h = Int(stats.tempsPasseSeconds) / 3600
        let m = (Int(stats.tempsPasseSeconds) % 3600) / 60
        let timeStr = h > 0 ? "\(h)h\(String(format: "%02d", m)) passées" : "\(m) min passées"
        if hasTime && hasNoProj {
            line = "\(timeStr) · \(stats.sansProjet) sans projet"
        } else if hasTime {
            line = timeStr
        } else {
            line = "Pas encore de réunion terminée · \(stats.sansProjet) sans projet"
        }
        let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Event items (kept from original)

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

        // Clic direct = ouvrir dans OneToOne (+ Teams si lien dispo).
        // Pas de submenu — évite un clic supplémentaire.
        item.action = #selector(activateEvent(_:))
        item.target = self
        item.representedObject = event.id
        return item
    }

    /// Action unifiée pour un événement de l'agenda : lance Teams si l'event
    /// a un `teamsJoinURL`, puis ouvre/importe la réunion dans OneToOne.
    @objc private func activateEvent(_ sender: NSMenuItem) {
        guard let eventID = sender.representedObject as? String,
              let context = container?.mainContext,
              let event = CalendarAgendaService.shared.eventsToday.first(where: { $0.id == eventID })
        else { return }

        // 1. Teams si dispo.
        if let url = event.teamsJoinURL {
            TeamsLauncher.open(url)
        }

        // 2. Import idempotent + activation + post notification.
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
            userInfo: ["meetingID": meeting.ensuredStableID.uuidString]
        )
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

    @objc private func startAdHoc() {
        guard let container = container else { return }
        QuickLaunchRouter.shared.startAdHocMeeting(in: container.mainContext)
    }

    @objc private func startOneToOneFromMenubar(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let uuid = UUID(uuidString: raw),
              let container = container else { return }
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        if let collab = (try? container.mainContext.fetch(descriptor))?.first {
            QuickLaunchRouter.shared.startOneToOne(
                collaborator: collab,
                autoStartRecording: true,
                in: container.mainContext
            )
        }
    }

    @objc private func startManager() {
        guard let container = container,
              let collab = managerCollaborator(settings: currentSettings()) else { return }
        QuickLaunchRouter.shared.startManagerMeeting(collaborator: collab, in: container.mainContext)
    }

    @objc private func showQuickAction() {
        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(QuickActionPopover { [weak self] in
            self?.quickActionPopover.performClose(nil)
        })
        show(quickActionPopover, content: host)
    }

    @objc private func showQuickNote() {
        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(QuickNotePopover { [weak self] in
            self?.quickNotePopover.performClose(nil)
        })
        show(quickNotePopover, content: host)
    }

    @objc private func showSearch() {
        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(SearchPopover(
            onSelectMeeting: { [weak self] meeting in self?.openMeeting(meeting) },
            onSelectCollaborator: { _ in /* future: deep-link to CollaboratorDetail */ },
            onSelectProject: { _ in /* future: deep-link to ProjectDetail */ },
            onDismiss: { [weak self] in self?.searchPopover.performClose(nil) }
        ))
        show(searchPopover, content: host)
    }

    @objc private func showUrgent(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let task = urgentTaskByKey[key] else { return }
        urgentTaskForPopover = task

        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(UrgentActionPopover(
            task: task,
            onComplete: { [weak self] in
                task.isCompleted = true
                task.completedAt = Date()
                try? self?.container?.mainContext.save()
            },
            onOpenMeeting: { [weak self] meeting in self?.openMeeting(meeting) },
            onDismiss: { [weak self] in self?.urgentActionPopover.performClose(nil) }
        ))
        show(urgentActionPopover, content: host)
    }

    private func openMeeting(_ meeting: Meeting) {
        NSApp.activate(ignoringOtherApps: true)
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: false
        )
    }

    private func favoriteCollaborators() -> [Collaborator] {
        guard let container = container else { return [] }
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { !$0.isArchived && $0.pinLevel >= 1 }
        )
        let all = (try? container.mainContext.fetch(descriptor)) ?? []
        return all.sorted { lhs, rhs in
            if lhs.pinLevel != rhs.pinLevel { return lhs.pinLevel > rhs.pinLevel }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func managerCollaborator(settings: AppSettings?) -> Collaborator? {
        guard let email = settings?.managerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty,
              let container = container else { return nil }
        let needle = email.lowercased()
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? container.mainContext.fetch(descriptor)) ?? []
        return all.first { $0.email.lowercased() == needle }
    }

    // MARK: - Prep submenu

    private func buildPrepSubmenu() -> NSMenu {
        let submenu = NSMenu()
        guard let container = OneToOneApp.sharedContainer else {
            let empty = NSMenuItem(title: "Indisponible", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }
        let ctx = container.mainContext

        // 1:1 — pinned collabs alpha
        let collabDesc = FetchDescriptor<Collaborator>(
            predicate: #Predicate { !$0.isArchived && $0.pinLevel > 0 },
            sortBy: [SortDescriptor(\.name)]
        )
        let collabs = Array(((try? ctx.fetch(collabDesc)) ?? []).prefix(10))
        if !collabs.isEmpty {
            let header = NSMenuItem(title: "1:1", action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
            for c in collabs {
                let mi = NSMenuItem(title: c.name,
                                    action: #selector(openCollabPrep(_:)),
                                    keyEquivalent: "")
                mi.target = self
                mi.representedObject = c.ensuredStableID.uuidString
                submenu.addItem(mi)
            }
        }

        // Projets — first 5 non-archived, sorted by name
        let projDesc = FetchDescriptor<Project>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        let projects = Array(((try? ctx.fetch(projDesc)) ?? []).prefix(5))
        if !projects.isEmpty {
            submenu.addItem(.separator())
            let header = NSMenuItem(title: "Projets", action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
            for p in projects {
                let mi = NSMenuItem(title: p.name,
                                    action: #selector(openProjectPrep(_:)),
                                    keyEquivalent: "")
                mi.target = self
                mi.representedObject = (p.stableID ?? UUID()).uuidString
                submenu.addItem(mi)
            }
        }

        submenu.addItem(.separator())
        let pickerItem = NSMenuItem(title: "Choisir réunion calendrier…",
                                    action: #selector(openCalendarMeetingPickerAction),
                                    keyEquivalent: "")
        pickerItem.target = self
        submenu.addItem(pickerItem)

        return submenu
    }

    @objc private func openCollabPrep(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        let token = PrepWindowToken(collabID: id, projectID: nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openPrepWindow,
                                        object: nil,
                                        userInfo: ["token": token])
    }

    @objc private func openProjectPrep(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        let token = PrepWindowToken(collabID: nil, projectID: id)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openPrepWindow,
                                        object: nil,
                                        userInfo: ["token": token])
    }

    @objc private func openCalendarMeetingPickerAction() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openCalendarMeetingPicker, object: nil)
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title.isEmpty == false {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
