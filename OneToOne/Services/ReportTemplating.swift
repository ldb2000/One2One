import Foundation
import SwiftData

/// Resolves `{{variable}}` placeholders against a Meeting + ModelContext.
///
/// Unknown variables are left literal (e.g. `{{foo}}` stays as `{{foo}}`)
/// and logged once per resolve call. Each resolver is responsible for its
/// own truncation cap (see spec §4 table).
enum TemplateVariableResolver {

    private static let pattern: NSRegularExpression = {
        // Allow lowercase letters, digits, underscores, dots inside `{{}}`.
        try! NSRegularExpression(pattern: #"\{\{([a-z0-9_.]+)\}\}"#)
    }()

    @MainActor
    static func resolve(prompt: String,
                        for meeting: Meeting,
                        in context: ModelContext,
                        now: Date = Date()) -> String {
        var unresolved: Set<String> = []
        let range = NSRange(prompt.startIndex..., in: prompt)
        let matches = pattern.matches(in: prompt, range: range)

        // Iterate in reverse so substitutions don't shift earlier indices.
        var output = prompt
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let nameRange = Range(match.range(at: 1), in: output),
                  let fullRange = Range(match.range(at: 0), in: output) else { continue }
            let name = String(output[nameRange])
            if let value = resolveOne(name: name, meeting: meeting, context: context, now: now) {
                output.replaceSubrange(fullRange, with: value)
            } else {
                unresolved.insert(name)
            }
        }

        if !unresolved.isEmpty {
            print("[TemplateVariableResolver] unresolved vars: \(unresolved.sorted())")
        }
        return output
    }

    // MARK: - Per-variable resolution

    @MainActor
    private static func resolveOne(name: String,
                                   meeting: Meeting,
                                   context: ModelContext,
                                   now: Date) -> String? {
        switch name {

        // --- Meeting basics
        case "title":          return meeting.title
        case "date":           return Self.formatDate(meeting.date)
        case "duration":       return Self.formatDuration(meeting.effectiveDuration)
        case "kind":           return meeting.kind.label
        case "participants":   return meeting.participantsDescription
        case "transcript":     return meeting.mergedTranscript
        case "notes":          return meeting.notes
        case "custom_prompt":  return meeting.customPrompt

        // --- Project
        case "project.name":    return meeting.project?.name ?? ""
        case "project.code":    return meeting.project?.code ?? ""
        case "project.entity":  return meeting.project?.entity?.name ?? ""
        case "project.phase":   return meeting.project?.phase ?? ""
        case "project.status":  return meeting.project?.status ?? ""
        case "project.planning": return meeting.project?.planningText ?? ""
        case "project.actions_ouvertes": return Self.actionsList(for: meeting.project, in: context)
        case "project.dernier_rapport":  return Self.dernierRapport(for: meeting.project, excluding: meeting, in: context)
        case "project.historique_n":     return ""  // populated externally by HistoryContextBuilder

        // --- Collab (only for .oneToOne)
        case "collab.name":  return Self.partnerCollaborator(of: meeting)?.name ?? ""
        case "collab.role":  return Self.partnerCollaborator(of: meeting)?.role ?? ""
        case "collab.email": return Self.partnerCollaborator(of: meeting)?.email ?? ""
        case "collab.actions_ouvertes": return Self.actionsList(for: Self.partnerCollaborator(of: meeting), in: context)
        case "collab.dernier_1to1":     return Self.dernier1to1(for: Self.partnerCollaborator(of: meeting), excluding: meeting, in: context)
        case "collab.notes":            return Self.collabNotes(for: Self.partnerCollaborator(of: meeting), in: context)

        // --- Manager
        case "manager.items_actuels": return Self.managerItemsActuels(in: context)
        case "manager.dernier_cr":    return Self.managerDernierCR(in: context)

        // --- Global
        case "actions_overdue":   return Self.actionsOverdue(in: context, now: now)
        case "actions_du_jour":   return Self.actionsDuJour(in: context, now: now)
        case "historique_n":      return ""  // populated externally
        case "contexte_general":  return Self.contexteGeneral(in: context, now: now)
        case "date_now":          return Self.formatDate(now)
        case "semaine":           return Self.formatWeek(now)
        case "mois":              return Self.formatMonth(now)

        default:                  return nil
        }
    }

    // MARK: - Sub-resolvers

    @MainActor
    private static func partnerCollaborator(of meeting: Meeting) -> Collaborator? {
        guard meeting.kind == .oneToOne || meeting.kind == .manager else { return nil }
        return meeting.participants.first
    }

    @MainActor
    private static func actionsList(for project: Project?, in context: ModelContext) -> String {
        guard let project else { return "" }
        let pid = project.persistentModelID
        let descriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { !$0.isCompleted && $0.project?.persistentModelID == pid }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return Self.renderActions(Array(tasks.prefix(30)))
    }

    @MainActor
    private static func actionsList(for collab: Collaborator?, in context: ModelContext) -> String {
        guard let collab else { return "" }
        let cid = collab.persistentModelID
        let descriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { !$0.isCompleted && $0.collaborator?.persistentModelID == cid }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return Self.renderActions(Array(tasks.prefix(30)))
    }

    @MainActor
    private static func renderActions(_ tasks: [ActionTask]) -> String {
        guard !tasks.isEmpty else { return "(aucune)" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return tasks.map { t in
            let due = t.dueDate.map { " (échéance \(fmt.string(from: $0)))" } ?? ""
            return "- \(t.title)\(due)"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func dernierRapport(for project: Project?, excluding currentMeeting: Meeting, in context: ModelContext) -> String {
        guard let project else { return "" }
        let pid = project.persistentModelID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.project?.persistentModelID == pid },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        guard let last = all.first(where: { $0.persistentModelID != currentMeeting.persistentModelID && !$0.summary.isEmpty }) else { return "" }
        return Self.truncate(last.summary, to: 2500)
    }

    @MainActor
    private static func dernier1to1(for collab: Collaborator?, excluding currentMeeting: Meeting, in context: ModelContext) -> String {
        guard let collab else { return "" }
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        guard let last = all.first(where: { m in
            m.persistentModelID != currentMeeting.persistentModelID
                && m.kind == .oneToOne
                && m.participants.contains(where: { $0.persistentModelID == collab.persistentModelID })
                && !m.summary.isEmpty
        }) else { return "" }
        return Self.truncate(last.summary, to: 2000)
    }

    @MainActor
    private static func collabNotes(for collab: Collaborator?, in context: ModelContext) -> String {
        guard let collab else { return "" }
        let cid = collab.persistentModelID
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.collaborator?.persistentModelID == cid },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let notes = (try? context.fetch(descriptor)) ?? []
        return notes.prefix(5).map { "- \(Self.truncate($0.body, to: 200))" }.joined(separator: "\n")
    }

    @MainActor
    private static func managerItemsActuels(in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.archivedAt == nil && !$0.isCompleted },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.prefix(20).map { "- [\($0.category)] \(Self.firstLine($0.elaboratedText.isEmpty ? $0.rawSnippet : $0.elaboratedText))" }
            .joined(separator: "\n")
    }

    @MainActor
    private static func managerDernierCR(in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<ManagerMeetingReport>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        let reports = (try? context.fetch(descriptor)) ?? []
        guard let last = reports.first else { return "" }
        return Self.truncate(last.generatedSummary, to: 2500)
    }

    @MainActor
    private static func actionsOverdue(in context: ModelContext, now: Date) -> String {
        let urgent = UrgentActionsSelector.qualifying(in: context, now: now)
        let overdue = urgent.filter { ($0.dueDate ?? .distantFuture) < Calendar.current.startOfDay(for: now) }
        return Self.renderActions(Array(overdue.prefix(10)))
    }

    @MainActor
    private static func actionsDuJour(in context: ModelContext, now: Date) -> String {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let descriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { task in
                !task.isCompleted && task.dueDate != nil
                    && task.dueDate! >= startOfToday
                    && task.dueDate! < endOfToday
            }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return Self.renderActions(Array(tasks.prefix(10)))
    }

    @MainActor
    private static func contexteGeneral(in context: ModelContext, now: Date) -> String {
        let urgent = UrgentActionsSelector.qualifying(in: context, now: now)
        let actions = Self.renderActions(Array(urgent.prefix(5)))

        let alertDescriptor = FetchDescriptor<ProjectAlert>()
        let allAlerts = (try? context.fetch(alertDescriptor)) ?? []
        let alerts = allAlerts
            .filter { $0.severity == "Élevé" || $0.severity == "Critique" }
            .prefix(3)
        let alertsText = alerts.isEmpty
            ? "(aucune)"
            : alerts.map { "- [\($0.severity)] \(Self.firstLine($0.title))" }.joined(separator: "\n")

        let cal = Calendar.current
        let fortnightAgo = cal.date(byAdding: .day, value: -14, to: now) ?? now
        let meetingDescriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.date >= fortnightAgo && $0.project != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let recentMeetings = (try? context.fetch(meetingDescriptor)) ?? []
        var seenProjectIDs: Set<PersistentIdentifier> = []
        var topProjects: [Project] = []
        for m in recentMeetings {
            guard let p = m.project else { continue }
            if seenProjectIDs.insert(p.persistentModelID).inserted {
                topProjects.append(p)
                if topProjects.count == 3 { break }
            }
        }
        let projectsText = topProjects.isEmpty
            ? "(aucun)"
            : topProjects.map { "- \($0.name) (\($0.code))" }.joined(separator: "\n")

        return """
        Actions urgentes:
        \(actions)

        Alertes actives:
        \(alertsText)

        Activité récente:
        \(projectsText)
        """
    }

    // MARK: - Formatting

    private static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m) min"
    }

    private static func formatWeek(_ d: Date) -> String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: d)
        return "S\(week)"
    }

    private static func formatMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }

    private static func truncate(_ s: String, to max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    private static func firstLine(_ s: String) -> String {
        s.components(separatedBy: .newlines).first ?? s
    }
}
