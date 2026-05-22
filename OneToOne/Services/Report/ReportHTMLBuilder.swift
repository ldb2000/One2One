import Foundation
import SwiftData

/// Assemble un HTML complet (head + style + body) pour un rapport de réunion.
/// Utilisé par :
/// - `MeetingReportPreview` (WKWebView preview)
/// - `ExportService.exportMeetingPDF` (createPDF)
/// - `ExportService.buildMeetingHTML` (mail / Outlook via AppleScript)
@MainActor
enum ReportHTMLBuilder {

    static func build(meeting: Meeting,
                      template: ReportTemplate?,
                      includeTranscript: Bool) -> String {
        let eyebrow = makeEyebrow(meeting: meeting, template: template)
        let title = escape(meeting.title.isEmpty ? "Réunion" : meeting.title)
        let subtitle = makeSubtitle(meeting: meeting, template: template)
        let meta = makeMetaTable(meeting: meeting)

        let bodyHTML = MarkdownToHTMLRenderer.render(meeting.summary)

        var assembled = dedupeAndInject(
            bodyHTML: bodyHTML,
            decisions: meeting.decisions,
            tasks: meeting.tasks
        )

        if includeTranscript {
            let tx = meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tx.isEmpty {
                assembled += "<h2>Transcription complète</h2>\n"
                assembled += "<div class=\"transcript\">\(escape(tx).replacingOccurrences(of: "\n", with: "<br/>\n"))</div>\n"
            }
        }

        return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <style>
        \(ReportThemeCSS.css)
        </style>
        </head>
        <body>
        <div class="header-rule"></div>
        <div class="eyebrow">\(eyebrow)</div>
        <h1>\(title)</h1>
        <p class="subtitle">\(subtitle)</p>
        \(meta)
        \(assembled)
        </body>
        </html>
        """
    }

    // MARK: - Eyebrow / subtitle / meta

    private static func makeEyebrow(meeting: Meeting, template: ReportTemplate?) -> String {
        var parts: [String] = []
        if let t = template {
            parts.append(t.kind.label.uppercased())
        } else {
            parts.append("COMPTE-RENDU")
        }
        if let code = meeting.project?.code, !code.isEmpty {
            parts.append(escape(code))
        }
        parts.append("CONFIDENTIEL — USAGE INTERNE")
        return parts.joined(separator: " · ")
    }

    private static func makeSubtitle(meeting: Meeting, template: ReportTemplate?) -> String {
        let kindLabel = template?.kind.label ?? meeting.kind.label
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMMM yyyy 'à' HH:mm"
        return "\(escape(kindLabel)) — \(fmt.string(from: meeting.date))"
    }

    private static func makeMetaTable(meeting: Meeting) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMMM yyyy 'à' HH:mm"
        var dateCell = fmt.string(from: meeting.date)
        if meeting.durationSeconds > 0 {
            let mins = Int(meeting.durationSeconds / 60)
            let h = mins / 60, m = mins % 60
            let dur = h > 0 ? "(durée \(h)h\(String(format: "%02d", m)))" : "(durée \(m) min)"
            dateCell += " \(dur)"
        }
        let participants = meeting.participants
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { escape($0.name) }
            .joined(separator: ", ")
        let participantsCell = participants.isEmpty ? "—" : participants

        let objet = makeObjet(meeting: meeting)

        return """
        <table class="meta">
        <tr><th>OBJET</th><td>\(objet)</td></tr>
        <tr><th>DATE</th><td>\(escape(dateCell))</td></tr>
        <tr><th>PARTICIPANTS</th><td>\(participantsCell)</td></tr>
        </table>
        """
    }

    private static func makeObjet(meeting: Meeting) -> String {
        let summary = meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return escape(meeting.title.isEmpty ? "—" : meeting.title) }
        let lines = summary.components(separatedBy: "\n")
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("#") || t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix(":::") || t.hasPrefix("@") { continue }
            if let dot = t.firstIndex(of: ".") {
                return escape(String(t[..<dot]) + ".")
            }
            return escape(t)
        }
        return escape(meeting.title.isEmpty ? "—" : meeting.title)
    }

    // MARK: - Dedupe & inject Décisions / Actions

    private static let decisionsTitleAliases: Set<String> = [
        "decisions",
        "releve de decisions",
        "relevé de décisions",
        "decisions actees",
        "accords obtenus"
    ]

    private static let actionsTitleAliases: Set<String> = [
        "actions",
        "plan d'actions",
        "actions a mener",
        "prochaines etapes",
        "prochaines étapes"
    ]

    private static func dedupeAndInject(bodyHTML: String,
                                        decisions: [String],
                                        tasks: [ActionTask]) -> String {
        var html = bodyHTML
        let decisionsBlock = decisions.isEmpty ? nil : renderDecisionsBlock(decisions)
        let actionsBlock = tasks.isEmpty ? nil : renderActionsBlock(tasks)

        if let block = decisionsBlock {
            html = replaceOrAppend(html, titleAliases: decisionsTitleAliases, block: block)
        }
        if let block = actionsBlock {
            html = replaceOrAppend(html, titleAliases: actionsTitleAliases, block: block)
        }
        return html
    }

    private static func renderDecisionsBlock(_ decisions: [String]) -> String {
        var rows = ""
        for (idx, d) in decisions.enumerated() {
            rows += "<tr><td>D\(idx + 1)</td><td>\(escape(d))</td></tr>\n"
        }
        return """
        <h2>Relevé de décisions</h2>
        <table>
        <thead><tr><th>#</th><th>Décision</th></tr></thead>
        <tbody>
        \(rows)</tbody>
        </table>
        """
    }

    private static func renderActionsBlock(_ tasks: [ActionTask]) -> String {
        let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"
        var rows = ""
        for (idx, t) in sorted.enumerated() {
            let porteur = t.collaborator?.name ?? t.unresolvedAssigneeName ?? "—"
            let dueRaw = t.dueDate.map(fmt.string(from:)) ?? "—"
            rows += "<tr><td>A\(idx + 1)</td><td>\(escape(t.title))</td><td>\(escape(porteur))</td><td>\(escape(dueRaw))</td></tr>\n"
        }
        return """
        <h2>Plan d'actions</h2>
        <table>
        <thead><tr><th>#</th><th>Action</th><th>Porteur</th><th>Échéance</th></tr></thead>
        <tbody>
        \(rows)</tbody>
        </table>
        """
    }

    /// Cherche un `<h2>Titre</h2>` dont le texte normalisé matche un alias.
    /// Si trouvé → remplace ce `<h2>` ET le bloc qui suit (jusqu'au prochain
    /// `<h2>` ou la fin) par `block`. Sinon append `block` à la fin.
    private static func replaceOrAppend(_ html: String,
                                        titleAliases: Set<String>,
                                        block: String) -> String {
        let pattern = #"<h2[^>]*>(.*?)</h2>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return html + "\n" + block
        }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        let matches = regex.matches(in: html, options: [], range: range)

        for (i, m) in matches.enumerated() {
            let titleText = nsHTML.substring(with: m.range(at: 1))
            let normalized = normalize(titleText)
            if titleAliases.contains(normalized) {
                let start = m.range.location
                let nextStart: Int
                if i + 1 < matches.count {
                    nextStart = matches[i + 1].range.location
                } else {
                    nextStart = nsHTML.length
                }
                let replaceRange = NSRange(location: start, length: nextStart - start)
                return nsHTML.replacingCharacters(in: replaceRange, with: block + "\n")
            }
        }
        return html + "\n" + block + "\n"
    }

    private static func normalize(_ s: String) -> String {
        var stripped = ""
        var inside = false
        for c in s {
            if c == "<" { inside = true }
            else if c == ">" { inside = false }
            else if !inside { stripped.append(c) }
        }
        return stripped
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML escape

    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}
