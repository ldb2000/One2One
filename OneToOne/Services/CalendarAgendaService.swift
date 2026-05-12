import Foundation
import EventKit
import Combine
import SwiftUI

@MainActor
final class CalendarAgendaService: ObservableObject {

    static let shared = CalendarAgendaService()

    @Published private(set) var eventsToday: [CalendarMeetingEvent] = []
    @Published private(set) var nextUpcoming: CalendarMeetingEvent?
    @Published private(set) var hasCalendarAccess: Bool = false

    private let importer = CalendarMeetingImportService()
    private var refreshTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    private init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    func bootstrap() async {
        hasCalendarAccess = await importer.requestAccess()
        refresh()
        startPeriodicRefresh()
    }

    /// Returns events for an arbitrary day (used by AgendaInspectorPanel).
    func events(for date: Date) -> [CalendarMeetingEvent] {
        guard hasCalendarAccess else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return importer.fetchEvents(start: start, end: end)
            .filter { !$0.isAllDay }
    }

    // MARK: - Internals

    private func refresh() {
        guard hasCalendarAccess else { return }
        eventsToday = events(for: Date())
        nextUpcoming = computeNextUpcoming()
    }

    private func computeNextUpcoming() -> CalendarMeetingEvent? {
        let now = Date()
        let candidates = events(for: now) + events(for: now.addingTimeInterval(86_400))
        return candidates
            .filter { $0.endDate > now && !$0.isCancelled }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
                await MainActor.run { self?.refresh() }
            }
        }
    }
}
