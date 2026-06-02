import Foundation
import SwiftData

// MARK: - Urgent actions selector

enum UrgentActionsSelector {

    /// Returns ActionTasks that should appear in the menubar urgent
    /// section, sorted (overdue → today → old-no-date). See spec §5.
    @MainActor
    static func qualifying(in context: ModelContext, now: Date = Date()) -> [ActionTask] {
        let descriptor = FetchDescriptor<ActionTask>()
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        let filtered = all.filter { task in
            guard !task.isCompleted else { return false }
            if let due = task.dueDate {
                return due < endOfToday
            }
            // no due date: only stale (>= 30d) tasks qualify
            if let createdAt = task.createdAt {
                return createdAt <= thirtyDaysAgo
            }
            return false
        }

        return filtered.sorted { lhs, rhs in
            let lb = bucket(for: lhs, startOfToday: startOfToday, endOfToday: endOfToday)
            let rb = bucket(for: rhs, startOfToday: startOfToday, endOfToday: endOfToday)
            if lb != rb { return lb < rb }
            return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
    }

    /// Bucket order: 0 = overdue, 1 = today, 2 = stale-no-date.
    private static func bucket(for task: ActionTask, startOfToday: Date, endOfToday: Date) -> Int {
        if let due = task.dueDate {
            if due < startOfToday { return 0 }
            return 1
        }
        return 2
    }
}

// MARK: - Today stats

struct TodayStats: Equatable {
    let tempsPasseSeconds: TimeInterval
    let sansProjet: Int
}

enum TodayStatsCalculator {

    /// Agrège les stats du jour pour la barre de menus.
    /// "Aujourd'hui" = intervalle [début de `now`, début du lendemain) ; un meeting
    /// y est rattaché via `scheduledStart` (à défaut `date`). `tempsPasseSeconds`
    /// ne cumule que les meetings déjà terminés (`scheduledEnd`/`date` < `now`),
    /// `sansProjet` compte ceux du jour sans projet associé.
    @MainActor
    static func compute(in context: ModelContext, now: Date = Date()) -> TodayStats {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        var passed: TimeInterval = 0
        var withoutProject = 0

        for meeting in all {
            // "Within today": prefer scheduledStart, fall back to .date.
            let anchor = meeting.scheduledStart ?? meeting.date
            guard anchor >= startOfToday && anchor < endOfToday else { continue }

            if meeting.project == nil { withoutProject += 1 }

            let endRef = meeting.scheduledEnd ?? meeting.date
            if endRef < now {
                passed += meeting.effectiveDuration
            }
        }

        return TodayStats(tempsPasseSeconds: passed, sansProjet: withoutProject)
    }
}

// MARK: - Badge text

enum MenubarBadgeText {

    /// Returns the title suffix to append to the status item, or "" if none.
    /// `hasOverdue == true` swaps the round bullet for a warning glyph so the
    /// user immediately spots that at least one urgent task is past due.
    static func suffix(urgentCount: Int, hasOverdue: Bool) -> String {
        guard urgentCount > 0 else { return "" }
        let glyph = hasOverdue ? "⚠" : "●"
        return " \(glyph)\(urgentCount)"
    }
}
