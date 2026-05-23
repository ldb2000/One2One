import Foundation
import SwiftData

/// Assemble un HTML complet (head + style + body) pour un rapport de réunion.
/// Utilisé par :
/// - `MeetingReportPreview` (WKWebView preview)
/// - `ExportService.exportMeetingPDF` (createPDF)
/// - `ExportService.buildMeetingHTML` (mail / Outlook via AppleScript)
@MainActor
enum ReportHTMLBuilder {

    enum RenderMode { case preview, outlook }

    static func build(meeting: Meeting,
                      template: ReportTemplate?,
                      includeTranscript: Bool,
                      managerName: String = "",
                      managerRole: String = "",
                      mode: RenderMode = .preview) -> String {
        let eyebrow = makeEyebrow(meeting: meeting, template: template)
        let title = escape(meeting.title.isEmpty ? "Réunion" : meeting.title)
        let subtitle = makeSubtitle(meeting: meeting, template: template)
        let meta = makeMetaTable(meeting: meeting,
                                  managerName: managerName,
                                  managerRole: managerRole)

        let bodyHTML = MarkdownToHTMLRenderer.render(meeting.summary)

        var assembled = dedupeAndInject(
            bodyHTML: bodyHTML,
            decisions: meeting.decisions,
            tasks: meeting.tasks,
            alerts: meeting.meetingAlerts,
            meeting: meeting
        )

        if includeTranscript {
            let tx = meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tx.isEmpty {
                assembled += "<h2>Transcription complète</h2>\n"
                assembled += "<div class=\"transcript\">\(escape(tx).replacingOccurrences(of: "\n", with: "<br/>\n"))</div>\n"
            }
        }

        let rawHTML = """
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

        switch mode {
        case .preview:
            return rawHTML
        case .outlook:
            return inlineForOutlook(rawHTML)
        }
    }

    // MARK: - Outlook inlining

    private static func inlineForOutlook(_ html: String) -> String {
        var out = html

        // 1. Remplacer les <h2>...</h2> par une table 2-cellules (badge + titre).
        // Outlook (Word renderer) ne supporte pas display:inline-block correctement,
        // donc le badge dans un <span> tombe en block. Table = layout fiable.
        out = replaceH2WithBadgeTable(out)

        // 2. Supprimer le bloc <style>…</style>.
        out = stripStyleBlock(out)

        // 3. Body.
        out = out.replacingOccurrences(of: "<body>",
            with: "<body style=\"font-family:-apple-system,'Segoe UI',Helvetica,sans-serif;color:#2d2d2d;line-height:1.55;font-size:13px;\">")

        // 4. Éléments d'en-tête.
        out = out.replacingOccurrences(of: "<div class=\"header-rule\">",
            with: "<div style=\"height:4px;background:#1a2a44;margin-bottom:18px;\">")
        out = out.replacingOccurrences(of: "<div class=\"eyebrow\">",
            with: "<div style=\"font-size:11px;letter-spacing:0.18em;color:#1a2a44;font-weight:600;margin-bottom:6px;\">")
        out = out.replacingOccurrences(of: "<h1>",
            with: "<h1 style=\"font-size:28px;color:#0d1f3a;line-height:1.2;margin:6px 0 4px;font-weight:700;\">")
        out = out.replacingOccurrences(of: "<p class=\"subtitle\">",
            with: "<p style=\"color:#7a7a7a;font-size:14px;font-weight:600;margin:0 0 18px;\">")

        // 5. Table meta.
        out = out.replacingOccurrences(of: "<table class=\"meta\">",
            with: "<table cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"width:100%;border-collapse:collapse;margin-bottom:28px;\">")
        out = inlineMeatCells(out)

        // 6. Tables de contenu (sans classe).
        out = out.replacingOccurrences(of: "<table>",
            with: "<table cellspacing=\"0\" cellpadding=\"8\" border=\"0\" style=\"width:100%;border-collapse:collapse;margin:8px 0 18px;\">")
        out = out.replacingOccurrences(of: "<th>",
            with: "<th style=\"background:#1a2a44;color:#ffffff;text-align:left;padding:8px 10px;font-size:11px;letter-spacing:0.06em;font-weight:700;\">")
        out = out.replacingOccurrences(of: "<td>",
            with: "<td style=\"padding:8px 10px;border-bottom:1px solid #e8d9b8;vertical-align:top;\">")

        // 7. Alternance de lignes dans les tbody.
        out = alternateRows(out)

        // 9. Blockquote.
        out = out.replacingOccurrences(of: "<blockquote>",
            with: "<blockquote style=\"background:#fbf4e3;border-radius:3px;padding:12px 14px;margin:12px 0;font-size:13px;border-left:3px solid #e8d9b8;\">")

        // 10. Callouts : préfixe label inline (remplace le ::before CSS).
        out = out.replacingOccurrences(of: "<div class=\"callout vigilance\">",
            with: "<div style=\"background:#fbf4e3;border-radius:3px;padding:12px 14px;margin:12px 0;font-size:13px;\"><strong style=\"color:#b07020;\">● Point de vigilance.</strong> ")
        out = out.replacingOccurrences(of: "<div class=\"callout reserve\">",
            with: "<div style=\"background:#fbf4e3;border-radius:3px;padding:12px 14px;margin:12px 0;font-size:13px;\"><strong style=\"color:#7a7a7a;\">● Réserve exprimée.</strong> ")

        // 11. Strong / em.
        out = out.replacingOccurrences(of: "<strong>",
            with: "<strong style=\"color:#0d1f3a;font-weight:700;\">")
        out = out.replacingOccurrences(of: "<em>",
            with: "<em style=\"color:#7a7a7a;font-style:italic;\">")

        return out
    }

    /// Supprime le bloc <style>…</style> (y compris multi-lignes).
    private static func stripStyleBlock(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<style>.*?</style>",
                                                   options: [.dotMatchesLineSeparators]) else { return html }
        let range = NSRange(location: 0, length: (html as NSString).length)
        return regex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
    }

    /// Remplace chaque `<h2>Titre</h2>` par une table à 2 cellules (badge
    /// numéroté + titre) pour Outlook. Word ne respecte pas `display:inline-block`,
    /// donc un `<span>` badge tombe en block et casse l'alignement. Une table
    /// à 1 ligne 2 cellules est rendue fiablement par tous les clients mail.
    private static func replaceH2WithBadgeTable(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<h2>(.*?)</h2>",
                                                   options: [.dotMatchesLineSeparators]) else { return html }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
        var modified = html
        for (idx, match) in matches.enumerated().reversed() {
            let content = (modified as NSString).substring(with: match.range(at: 1))
            let n = idx + 1
            let table = """
            <table cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;margin:22px 0 10px;width:100%;border-bottom:1.5px solid #1a2a44;">
            <tr>
            <td style="background:#1a2a44;color:#ffffff;font-size:12px;font-weight:700;padding:2px 8px;width:28px;text-align:center;vertical-align:middle;">\(n)</td>
            <td style="font-size:16px;color:#0d1f3a;font-weight:700;padding:0 0 6px 10px;vertical-align:middle;">\(content)</td>
            </tr>
            </table>
            """
            modified = (modified as NSString).replacingCharacters(in: match.range, with: table)
        }
        return modified
    }

    /// Injecte les styles inline sur les th/td de la table meta.
    /// La table meta est délimitée par `<table cellspacing="0" cellpadding="0" border="0" style="...margin-bottom:28px;">…</table>`.
    private static func inlineMeatCells(_ html: String) -> String {
        // Pattern : trouve le bloc de la table meta (déjà remplacée par son style) et
        // remplace les <th>/<td> à l'intérieur par des versions stylées.
        let metaStyle = "width:100%;border-collapse:collapse;margin-bottom:28px;"
        guard let startRange = html.range(of: "style=\"\(metaStyle)\"") else { return html }

        // Trouver le </table> correspondant après ce point.
        let afterMeta = html[startRange.lowerBound...]
        guard let tableEnd = afterMeta.range(of: "</table>") else { return html }

        let metaBlock = String(html[startRange.lowerBound..<tableEnd.upperBound])
        var styledMeta = metaBlock
        styledMeta = styledMeta.replacingOccurrences(of: "<th>",
            with: "<th style=\"background:#f5f3ee;text-align:left;width:160px;padding:10px 12px;font-size:11px;letter-spacing:0.06em;color:#1a2a44;font-weight:700;vertical-align:top;\">")
        styledMeta = styledMeta.replacingOccurrences(of: "<td>",
            with: "<td style=\"padding:10px 12px;background:#f5f3ee;vertical-align:top;\">")

        return html.replacingOccurrences(of: metaBlock, with: styledMeta)
    }

    /// Alterne la couleur de fond des lignes dans chaque <tbody>.
    private static func alternateRows(_ html: String) -> String {
        guard let tbodyRegex = try? NSRegularExpression(pattern: "<tbody>(.*?)</tbody>",
                                                        options: [.dotMatchesLineSeparators]) else { return html }
        let nsHTML = html as NSString
        let matches = tbodyRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
        var modified = html
        for match in matches.reversed() {
            let tbodyContent = (modified as NSString).substring(with: match.range(at: 1))
            guard let rowRegex = try? NSRegularExpression(pattern: "<tr>(.*?)</tr>",
                                                          options: [.dotMatchesLineSeparators]) else { continue }
            let tbodyNS = tbodyContent as NSString
            let rowMatches = rowRegex.matches(in: tbodyContent, options: [],
                                              range: NSRange(location: 0, length: tbodyNS.length))
            var newContent = ""
            var lastEnd = 0
            for (rowIdx, rowMatch) in rowMatches.enumerated() {
                if rowMatch.range.location > lastEnd {
                    newContent += tbodyNS.substring(with: NSRange(location: lastEnd,
                                                                  length: rowMatch.range.location - lastEnd))
                }
                let row = tbodyNS.substring(with: rowMatch.range)
                if rowIdx % 2 == 1 {
                    let striped = row.replacingOccurrences(
                        of: "<td style=\"padding:8px 10px;border-bottom:1px solid #e8d9b8;vertical-align:top;\">",
                        with: "<td style=\"padding:8px 10px;border-bottom:1px solid #e8d9b8;vertical-align:top;background:#f5f3ee;\">")
                    newContent += striped
                } else {
                    newContent += row
                }
                lastEnd = rowMatch.range.location + rowMatch.range.length
            }
            if lastEnd < tbodyNS.length {
                newContent += tbodyNS.substring(with: NSRange(location: lastEnd,
                                                              length: tbodyNS.length - lastEnd))
            }
            let fullTbody = "<tbody>\(newContent)</tbody>"
            modified = (modified as NSString).replacingCharacters(in: match.range, with: fullTbody)
        }
        return modified
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

    private static func makeMetaTable(meeting: Meeting,
                                       managerName: String,
                                       managerRole: String) -> String {
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

        // Participants : "Nom — Rôle (rédacteur si match managerName)".
        // Sortie multi-lignes <br/> pour reproduire le format du PDF référence.
        let participantsCell = makeParticipantsCell(meeting: meeting,
                                                     managerName: managerName,
                                                     managerRole: managerRole)

        let objet = makeObjet(meeting: meeting)

        var rows = """
        <tr><th>OBJET</th><td>\(objet)</td></tr>
        <tr><th>DATE</th><td>\(escape(dateCell))</td></tr>
        <tr><th>PARTICIPANTS</th><td>\(participantsCell)</td></tr>
        """

        // Référencés (non présents) — uniquement si champ rempli.
        let ref = meeting.referencedAbsent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ref.isEmpty {
            rows += "\n<tr><th>RÉFÉRENCÉS<br/>(NON PRÉSENTS)</th><td>\(escape(ref))</td></tr>"
        }

        // Prochaine échéance — uniquement si champ rempli.
        let next = meeting.nextDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !next.isEmpty {
            rows += "\n<tr><th>PROCHAINE<br/>ÉCHÉANCE</th><td>\(escape(next))</td></tr>"
        }

        return """
        <table class="meta">
        \(rows)
        </table>
        """
    }

    private static func makeParticipantsCell(meeting: Meeting,
                                              managerName: String,
                                              managerRole: String) -> String {
        guard !meeting.participants.isEmpty else { return "—" }
        let normalizedManager = normalizeName(managerName)
        let lines = meeting.participants
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { c -> String in
                var line = escape(c.name)
                let isManager = !normalizedManager.isEmpty
                    && normalizeName(c.name) == normalizedManager
                // Rôle : si match manager → préférer AppSettings.managerRole.
                let displayRole: String = {
                    if isManager && !managerRole.isEmpty { return managerRole }
                    return c.role
                }()
                if !displayRole.isEmpty {
                    line += " — \(escape(displayRole))"
                }
                if isManager {
                    line += " <em style=\"color:#7a7a7a;font-style:italic;\">(rédacteur)</em>"
                }
                return line
            }
        return lines.joined(separator: "<br/>")
    }

    private static func normalizeName(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static let alertsTitleAliases: Set<String> = [
        "alertes",
        "risques",
        "points de vigilance",
        "vigilance"
    ]

    private static func dedupeAndInject(bodyHTML: String,
                                        decisions: [String],
                                        tasks: [ActionTask],
                                        alerts: [ProjectAlert] = [],
                                        meeting: Meeting) -> String {
        var html = bodyHTML
        let decisionsBlock = decisions.isEmpty ? nil : renderDecisionsBlock(decisions)
        let actionsBlock = tasks.isEmpty ? nil : renderActionsBlock(tasks, meeting: meeting)
        let alertsBlock = alerts.isEmpty ? nil : renderAlertsBlock(alerts)

        if let block = decisionsBlock {
            html = replaceOrAppend(html, titleAliases: decisionsTitleAliases, block: block)
        }
        if let block = actionsBlock {
            html = replaceOrAppend(html, titleAliases: actionsTitleAliases, block: block)
        }
        if let block = alertsBlock {
            html = replaceOrAppend(html, titleAliases: alertsTitleAliases, block: block)
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

    private static func renderActionsBlock(_ tasks: [ActionTask], meeting: Meeting) -> String {
        let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"

        // Colonne Projet : uniquement en 1:1 avec actions sur ≥2 projets distincts.
        let distinctProjects = Set(sorted.compactMap { $0.project?.persistentModelID })
        let includeProjectColumn = meeting.kind == .oneToOne && distinctProjects.count >= 2

        var rows = ""
        for (idx, t) in sorted.enumerated() {
            let porteur = t.collaborator?.name ?? t.unresolvedAssigneeName ?? "—"
            let dueRaw = t.dueDate.map(fmt.string(from:)) ?? "—"
            if includeProjectColumn {
                let proj = t.project?.code ?? "—"
                rows += "<tr><td>A\(idx + 1)</td><td>\(escape(t.title))</td><td>\(escape(proj))</td><td>\(escape(porteur))</td><td>\(escape(dueRaw))</td></tr>\n"
            } else {
                rows += "<tr><td>A\(idx + 1)</td><td>\(escape(t.title))</td><td>\(escape(porteur))</td><td>\(escape(dueRaw))</td></tr>\n"
            }
        }
        let header = includeProjectColumn
            ? "<thead><tr><th>#</th><th>Action</th><th>Projet</th><th>Porteur</th><th>Échéance</th></tr></thead>"
            : "<thead><tr><th>#</th><th>Action</th><th>Porteur</th><th>Échéance</th></tr></thead>"
        return """
        <h2>Plan d'actions</h2>
        <table>
        \(header)
        <tbody>
        \(rows)</tbody>
        </table>
        """
    }

    /// Rend les alertes en série de callouts cream (style "Point de vigilance")
    /// précédés d'un H2 "Alertes". Chaque alerte = un `<div class="callout vigilance">`
    /// avec titre en gras + détail. Sévérité affichée en suffix coloré.
    private static func renderAlertsBlock(_ alerts: [ProjectAlert]) -> String {
        var blocks = ""
        for a in alerts {
            let severityColor: String = {
                switch a.severity.lowercased() {
                case "critique": return "#b71c1c"
                case "élevé", "eleve": return "#e89a3c"
                case "modéré", "modere": return "#7a7a7a"
                case "faible": return "#9aa0a6"
                default: return "#7a7a7a"
                }
            }()
            blocks += """
            <div class="callout vigilance">
            <strong>\(escape(a.title))</strong> <span style="color:\(severityColor);font-weight:700;">(\(escape(a.severity)))</span>
            \(a.detail.isEmpty ? "" : "<br/>\(escape(a.detail))")
            </div>

            """
        }
        return """
        <h2>Alertes</h2>
        \(blocks)
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
            // Prefix-match : matche "actions pour Nicolas", "décisions clés", etc.
            // L'aliase étant déjà normalisé (lowercased + diacritic-insensitive),
            // un prefix match capture les variantes courantes.
            if titleAliases.contains(where: { normalized.hasPrefix($0) }) {
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
