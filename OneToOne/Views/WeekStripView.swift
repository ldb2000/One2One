import SwiftUI

/// Horizontal week strip à la Outlook mobile: 7 cells (day number + first
/// letter of weekday), selected day shown as a filled pill. Swipe / arrow
/// buttons shift the visible week by ±7 days.
struct WeekStripView: View {

    @Binding var selectedDate: Date
    var accent: Color = .accentColor

    @State private var weekAnchor: Date = Date()

    /// Shared ISO-8601 calendar (week starts Monday). Hoisted to a static so it
    /// is built once regardless of how many views are instantiated.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2  // Monday
        return c
    }()

    /// Header formatter, e.g. "Lundi · 3 juin '24". Cached to avoid per-access allocation.
    private static let headerFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE · d MMM ''yy"
        return fmt
    }()

    /// Single-letter weekday formatter (e.g. "L"). Cached to avoid per-call allocation.
    private static let dayLetterFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEEE"  // single letter
        return fmt
    }()

    private var calendar: Calendar { Self.calendar }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { shiftWeek(by: -7) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                HStack(spacing: 2) {
                    ForEach(weekDays, id: \.self) { day in
                        dayCell(day)
                    }
                }
                .frame(maxWidth: .infinity)

                Button { shiftWeek(by: 7) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(selectedDateHeader)
                    .font(.headline)
                Spacer()
                if !calendar.isDateInToday(selectedDate) {
                    Button("Aujourd'hui") {
                        let today = Date()
                        selectedDate = today
                        weekAnchor = today
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 8)
        .onAppear { weekAnchor = selectedDate }
    }

    private var weekDays: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)?.start else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedDateHeader: String {
        Self.headerFormatter.string(from: selectedDate).capitalized
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        VStack(spacing: 2) {
            Text(dayLetter(day))
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : (isToday ? accent : .secondary))
            Text("\(calendar.component(.day, from: day))")
                .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(minWidth: 32, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? accent : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = day
            weekAnchor = day
        }
    }

    private func dayLetter(_ day: Date) -> String {
        Self.dayLetterFormatter.string(from: day).uppercased()
    }

    private func shiftWeek(by days: Int) {
        if let newAnchor = calendar.date(byAdding: .day, value: days, to: weekAnchor) {
            weekAnchor = newAnchor
            selectedDate = newAnchor
        }
    }
}

#Preview {
    WeekStripView(selectedDate: .constant(Date()))
        .frame(width: 320)
        .padding()
}
