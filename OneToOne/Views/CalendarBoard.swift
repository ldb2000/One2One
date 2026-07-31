import SwiftUI

/// Vue calendrier mensuel réutilisable : les actions sont placées sur leur jour
/// d'échéance. Navigation mois ‹ › + « Aujourd'hui ». Clic sur une puce = bascule
/// la complétion. `fillsAvailableSpace` agrandit les cellules (écran plein).
struct CalendarBoard: View {
    let tasks: [ActionTask]
    var onToggle: (ActionTask) -> Void
    var fillsAvailableSpace: Bool = false

    @State private var monthAnchor: Date = Date()

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.firstWeekday = 2 // lundi
        return c
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, date in
                    dayCell(date)
                }
            }
            let undated = tasks.filter { !$0.isCompleted && $0.dueDate == nil }.count
            if undated > 0 {
                Text("\(undated) action(s) sans échéance")
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(Self.monthFormatter.string(from: monthAnchor).capitalized)
                .font(.subheadline.weight(.semibold))
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
            Spacer()
            Button("Aujourd'hui") { monthAnchor = Date() }
                .buttonStyle(.link).font(.caption)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"], id: \.self) { d in
                Text(d).font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: monthAnchor) { monthAnchor = d }
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
    }

    /// Cellules de la grille : blancs de tête, jours du mois, blancs de fin.
    private var gridDays: [Date?] {
        let start = monthStart
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekdayOfFirst = calendar.component(.weekday, from: start)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: d, to: start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var tasksByDay: [Date: [ActionTask]] {
        var dict: [Date: [ActionTask]] = [:]
        for t in tasks where !t.isCompleted {
            guard let due = t.dueDate else { continue }
            dict[calendar.startOfDay(for: due), default: []].append(t)
        }
        return dict
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        let minH: CGFloat = fillsAvailableSpace ? 84 : 46
        if let date {
            let items = (tasksByDay[calendar.startOfDay(for: date)] ?? [])
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let isToday = calendar.isDateInToday(date)
            let maxShown = fillsAvailableSpace ? 6 : 2
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption2)
                    .foregroundColor(isToday ? .white : .secondary)
                    .frame(width: 17, height: 17)
                    .background(isToday ? Circle().fill(MeetingTheme.accentOrange) : nil)
                ForEach(items.prefix(maxShown)) { t in chip(t) }
                if items.count > maxShown {
                    Text("+\(items.count - maxShown)")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: minH, alignment: .topLeading)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
        } else {
            Color.clear.frame(minHeight: minH)
        }
    }

    private func chip(_ task: ActionTask) -> some View {
        let color = (task.isUrgent || task.isImportant)
            ? EisenhowerBoard.quadrantColor(urgent: task.isUrgent, important: task.isImportant)
            : Color.secondary
        return Button { onToggle(task) } label: {
            Text(task.title)
                .font(.system(size: 9)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .help(task.title)
    }
}
