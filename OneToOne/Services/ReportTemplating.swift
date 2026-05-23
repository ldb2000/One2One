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
        case "contexte_general":  return Self.contexteGeneral(for: meeting, in: context, now: now)
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

    /// Contexte injecté dans le rapport. Scopé au projet de la réunion si
    /// présent (évite la pollution cross-projet) ; sinon bloc minimal indiquant
    /// l'absence de contexte exploitable. Le prompt instruit l'IA de ne pas
    /// recopier ce bloc en l'état (cf. d1_global et d_workshop).
    @MainActor
    private static func contexteGeneral(for meeting: Meeting, in context: ModelContext, now: Date) -> String {
        guard let project = meeting.project else {
            return "(aucun projet attaché à la réunion — n'inventer aucun contexte)"
        }
        let projectID = project.persistentModelID

        // Actions ouvertes du projet seulement.
        let actionDescriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { task in
                !task.isCompleted && task.project?.persistentModelID == projectID
            },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        let projActions = (try? context.fetch(actionDescriptor)) ?? []
        let actions = projActions.isEmpty
            ? "(aucune action ouverte sur le projet)"
            : Self.renderActions(Array(projActions.prefix(8)))

        // Alertes Élevé/Critique sur le projet.
        let alertDescriptor = FetchDescriptor<ProjectAlert>(
            predicate: #Predicate { $0.project?.persistentModelID == projectID }
        )
        let projAlerts = (try? context.fetch(alertDescriptor)) ?? []
        let alerts = projAlerts.filter { $0.severity == "Élevé" || $0.severity == "Critique" }.prefix(5)
        let alertsText = alerts.isEmpty
            ? "(aucune)"
            : alerts.map { "- [\($0.severity)] \(Self.firstLine($0.title))" }.joined(separator: "\n")

        // Dernières réunions du projet (titre + date) pour mettre la séance
        // courante en perspective.
        let recentDescriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.project?.persistentModelID == projectID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let recent = (try? context.fetch(recentDescriptor)) ?? []
        let recentOthers = recent.filter { $0.persistentModelID != meeting.persistentModelID }.prefix(3)
        let recentText = recentOthers.isEmpty
            ? "(aucune)"
            : recentOthers.map { "- \(Self.formatDate($0.date)) — \($0.title)" }.joined(separator: "\n")

        return """
        Projet: \(project.name) (\(project.code))

        Actions ouvertes du projet:
        \(actions)

        Alertes actives du projet:
        \(alertsText)

        Réunions récentes du projet:
        \(recentText)
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

/// Produces the bloc injected into `{{historique_n}}` according to the
/// template's history mode (none/lastN/rag/hybrid).
enum HistoryContextBuilder {

    @MainActor
    static func build(for meeting: Meeting,
                      template: ReportTemplate,
                      in context: ModelContext) -> String {
        switch template.historyMode {
        case .none:
            return ""
        case .lastN:
            return buildLastN(for: meeting, n: template.historyN, in: context)
        case .rag:
            // Embeddings infra not generalised yet — fallback to lastN(1).
            return buildLastN(for: meeting, n: max(template.historyN, 1), in: context)
        case .hybrid:
            // Same fallback — RAG portion is no-op until embeddings infra is generalised.
            return buildLastN(for: meeting, n: max(template.historyN, 1), in: context)
        }
    }

    // MARK: - lastN

    @MainActor
    private static func buildLastN(for meeting: Meeting, n: Int, in context: ModelContext) -> String {
        guard n > 0 else { return "" }
        let scope = peerMeetings(for: meeting, in: context)
            .filter { $0.persistentModelID != meeting.persistentModelID }
            .filter { !$0.summary.isEmpty }
        let top = Array(scope.prefix(n))
        guard !top.isEmpty else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"
        return top.map { m in
            let truncated = m.summary.count > 2000
                ? String(m.summary.prefix(1999)) + "…"
                : m.summary
            return "--- \(fmt.string(from: m.date)) · \(m.title) ---\n\(truncated)"
        }.joined(separator: "\n\n")
    }

    /// Returns Meetings in the scope of `meeting.kind`, sorted desc by date.
    ///
    /// Stratégie auto :
    /// - `.project` avec projet rattaché → mêmes projets
    /// - `.oneToOne` avec partenaire → même partenaire
    /// - `.manager` → toutes les réunions manager
    /// - sinon (workshop, copil sans projet, comité hebdo récurrent…) →
    ///   réunions au même titre (normalisation diacritique-insensible).
    ///   Couvre le cas du « Comité hebdomadaire de tri » qui revient chaque
    ///   semaine sans projet attaché.
    @MainActor
    private static func peerMeetings(for meeting: Meeting, in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        switch meeting.kind {
        case .project:
            if let pid = meeting.project?.persistentModelID {
                return all.filter { $0.project?.persistentModelID == pid }
            }
            // Projet absent → fallback titre (rare mais possible si meeting
            // marqué .project sans rattachement).
            return sameTitleMeetings(as: meeting, among: all)
        case .oneToOne:
            guard let partner = meeting.participants.first else { return [] }
            let cid = partner.persistentModelID
            return all.filter { m in
                m.kind == .oneToOne
                    && m.participants.contains(where: { $0.persistentModelID == cid })
            }
        case .manager:
            return all.filter { $0.kind == .manager }
        case .global, .work:
            return sameTitleMeetings(as: meeting, among: all)
        }
    }

    /// Filtre `pool` aux réunions dont le titre est identique à celui de
    /// `meeting` après normalisation (lowercased + diacriticInsensitive + trim).
    private static func sameTitleMeetings(as meeting: Meeting,
                                          among pool: [Meeting]) -> [Meeting] {
        let target = normalizeTitle(meeting.title)
        guard !target.isEmpty else { return [] }
        return pool.filter { normalizeTitle($0.title) == target }
    }

    private static func normalizeTitle(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Projects context (sub-projet 2b)

/// Construit le bloc de contexte projets pour une réunion 1:1. Pour chaque
/// projet où le partenaire est architecte technique ou chef de projet :
/// statut + top-3 résumés de réunions sur ce projet + actions ouvertes.
///
/// Tronqué à ~15 000 caractères au global, max 5 projets, top 3 résumés par
/// projet (1500 chars chacun), max 10 actions ouvertes par projet.
@MainActor
enum ProjectsContextBuilder {

    private static let maxProjects: Int = 5
    private static let summariesPerProject: Int = 3
    private static let summaryMaxChars: Int = 1500
    private static let actionsPerProject: Int = 10
    private static let totalBudgetChars: Int = 15_000

    static func build(for meeting: Meeting, in context: ModelContext) -> String {
        guard meeting.kind == .oneToOne,
              let partner = meeting.participants.first else {
            return ""
        }

        var seen = Set<PersistentIdentifier>()
        var projects: [Project] = []
        for p in partner.projectsAsArchitect + partner.projectsAsManager {
            guard !p.isArchived else { continue }
            if seen.insert(p.persistentModelID).inserted {
                projects.append(p)
            }
        }
        guard !projects.isEmpty else { return "" }

        let sorted = ProjectStatusPalette.sortedByStatus(projects)
        let topProjects = Array(sorted.prefix(maxProjects))

        var pieces: [String] = []
        for p in topProjects {
            pieces.append(renderProject(p, partner: partner, in: context))
        }
        let full = pieces.joined(separator: "\n\n")
        if full.count <= totalBudgetChars { return full }
        let truncated = String(full.prefix(totalBudgetChars))
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[..<lastNewline])
        }
        return truncated
    }

    private static func renderProject(_ p: Project,
                                       partner: Collaborator,
                                       in context: ModelContext) -> String {
        let role = projectRole(p, partner: partner)
        var out = "## \(p.code) · \(p.name) (statut: \(p.status))\n"
        out += "Rôle de \(partner.name) : \(role)\n\n"

        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allMeetings = (try? context.fetch(descriptor)) ?? []
        let projectMeetings = allMeetings.filter {
            $0.project?.persistentModelID == p.persistentModelID
                && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let topSummaries = Array(projectMeetings.prefix(summariesPerProject))
        out += "### \(summariesPerProject) derniers points discutés sur ce projet\n"
        if topSummaries.isEmpty {
            out += "(aucun historique disponible)\n"
        } else {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "d MMM yyyy"
            for m in topSummaries {
                out += "--- \(fmt.string(from: m.date)) · \(m.title) ---\n"
                let truncated = truncateAtBoundary(m.summary, max: summaryMaxChars)
                out += truncated + "\n\n"
            }
        }

        let openActions = p.tasks
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(actionsPerProject)
        out += "### Actions ouvertes sur ce projet (\(openActions.count))\n"
        if openActions.isEmpty {
            out += "(aucune action ouverte)\n"
        } else {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "d MMM yyyy"
            for t in openActions {
                let who = t.collaborator?.name ?? t.unresolvedAssigneeName ?? "—"
                let when = t.dueDate.map { fmt.string(from: $0) } ?? "—"
                out += "- \(t.title) — \(who), \(when)\n"
            }
        }
        return out
    }

    private static func projectRole(_ p: Project, partner: Collaborator) -> String {
        let isArchi = p.technicalArchitect?.persistentModelID == partner.persistentModelID
        let isPM = p.projectManager?.persistentModelID == partner.persistentModelID
        switch (isArchi, isPM) {
        case (true, true):  return "Architecte technique et chef de projet"
        case (true, false): return "Architecte technique"
        case (false, true): return "Chef de projet"
        default:            return "—"
        }
    }

    private static func truncateAtBoundary(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        let cut = String(s.prefix(max))
        if let dot = cut.lastIndex(of: ".") {
            return String(cut[...dot]) + "…"
        }
        if let nl = cut.lastIndex(of: "\n") {
            return String(cut[..<nl]) + "…"
        }
        return cut + "…"
    }
}
