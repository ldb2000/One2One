import SwiftUI

enum HeatmapMetric: String, CaseIterable, Identifiable {
    case count = "Nombre"
    case minutes = "Minutes"
    var id: String { rawValue }
}

/// GitHub-style contribution heatmap for Meeting activity.
/// Renders a 52-week × 7-day grid ending today, color intensity scaled
/// per the chosen metric (count of meetings or total minutes).
struct MeetingHeatmapView: View {

    let meetings: [Meeting]
    var title: String = ""
    @State private var metric: HeatmapMetric = .minutes

    private let weeks: Int = 52
    private let cellSize: CGFloat = 11
    private let cellGap: CGFloat = 2

    private let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2  // Monday
        return c
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !title.isEmpty {
                    Text(title).font(.headline)
                }
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(HeatmapMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            heatmapGrid

            HStack(spacing: 8) {
                Text(totalLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Moins").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(forLevel: level))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("Plus").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Grid

    private var heatmapGrid: some View {
        let days = generateDays()
        let buckets = buildBuckets(days: days)
        let maxValue = max(buckets.values.max() ?? 0, 1)
        let monthLabels = monthLabelsForColumns(days: days)
        let weekColumnWidth = cellSize + cellGap

        return HStack(alignment: .top, spacing: 4) {
            // Day-of-week labels — leave room at top to align with cells (month row offset)
            VStack(alignment: .leading, spacing: cellGap) {
                Text(" ").font(.system(size: 9)).frame(height: cellSize)  // align with month row
                ForEach(0..<7, id: \.self) { idx in
                    Text(dayLabel(idx))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(height: cellSize)
                }
            }

            VStack(alignment: .leading, spacing: cellGap) {
                // Month labels row
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(height: cellSize)
                    ForEach(monthLabels, id: \.column) { label in
                        Text(label.text)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .offset(x: CGFloat(label.column) * weekColumnWidth)
                    }
                }

                // Cells grid
                HStack(alignment: .top, spacing: cellGap) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: cellGap) {
                            ForEach(0..<7, id: \.self) { dow in
                                cellView(day: days[week * 7 + dow], value: buckets[days[week * 7 + dow]] ?? 0, max: maxValue)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Computes which week column should host a month label. Returns one
    /// entry per month transition (and the first visible month).
    private func monthLabelsForColumns(days: [Date]) -> [(column: Int, text: String)] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMM"

        var labels: [(Int, String)] = []
        var lastMonth: Int? = nil
        for week in 0..<weeks {
            let firstDayOfWeek = days[week * 7]
            let month = calendar.component(.month, from: firstDayOfWeek)
            if month != lastMonth {
                let raw = fmt.string(from: firstDayOfWeek)
                // Trim trailing dot some locales add ("janv." → "janv")
                let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                labels.append((week, text.capitalized))
                lastMonth = month
            }
        }
        return labels
    }

    private func cellView(day: Date, value: Double, max: Double) -> some View {
        let level = max > 0 ? min(4, Int((value / max) * 4.0 + (value > 0 ? 0.5 : 0))) : 0
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(forLevel: level))
            .frame(width: cellSize, height: cellSize)
            .help(tooltipText(day: day, value: value))
    }

    private func color(forLevel level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color.green.opacity(0.30)
        case 2: return Color.green.opacity(0.55)
        case 3: return Color.green.opacity(0.75)
        default: return Color.green
        }
    }

    // MARK: - Data

    /// Returns 52 weeks × 7 days, aligned so the last column ends today,
    /// rows are Mon→Sun, weeks oldest→newest.
    private func generateDays() -> [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let endWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        guard let firstDay = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: endWeekStart) else { return [] }

        var days: [Date] = []
        for w in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: w, to: firstDay) else { continue }
            for d in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: d, to: weekStart) {
                    days.append(calendar.startOfDay(for: day))
                }
            }
        }
        return days
    }

    private func buildBuckets(days: [Date]) -> [Date: Double] {
        guard let first = days.first, let last = days.last else { return [:] }
        let cutoffStart = first
        let cutoffEnd = calendar.date(byAdding: .day, value: 1, to: last) ?? Date()

        var buckets: [Date: Double] = [:]
        for meeting in meetings {
            let dayStart = calendar.startOfDay(for: meeting.date)
            guard dayStart >= cutoffStart && dayStart < cutoffEnd else { continue }
            let value: Double
            switch metric {
            case .count: value = 1
            case .minutes: value = meeting.effectiveDuration / 60.0
            }
            buckets[dayStart, default: 0] += value
        }
        return buckets
    }

    private func dayLabel(_ dow: Int) -> String {
        // Mon=0 → "L", ... ISO week, only show every other to save space
        let labels = ["L", "", "M", "", "V", "", "D"]
        return labels[dow]
    }

    private func tooltipText(day: Date, value: Double) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE d MMM yyyy"
        let dateStr = fmt.string(from: day)
        switch metric {
        case .count:
            return "\(dateStr) — \(Int(value)) réunion(s)"
        case .minutes:
            let m = Int(value)
            return "\(dateStr) — \(m) min"
        }
    }

    private var totalLabel: String {
        let buckets = buildBuckets(days: generateDays())
        let total = buckets.values.reduce(0, +)
        switch metric {
        case .count:
            return "\(Int(total)) réunion(s) sur 52 semaines"
        case .minutes:
            let hours = total / 60.0
            return String(format: "%.1f h sur 52 semaines", hours)
        }
    }
}
