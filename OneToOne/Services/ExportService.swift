import Foundation
import AppKit

class ExportService {
    func exportToMarkdown(interview: Interview) -> String {
        if interview.type == .job {
            return exportJobToMarkdown(interview: interview)
        }

        let dateString = interview.date.formatted(date: .long, time: .omitted)
        var md = "# Entretien - \(interview.collaborator?.name ?? "Inconnu")\n"
        md += "Date: \(dateString)\n\n"
        if let project = interview.selectedProject {
            md += "Projet: \(project.name)\n"
        }
        if interview.shareWithEveryone {
            md += "Retour à partager: Oui\n"
        }
        if !interview.contextComment.isEmpty {
            md += "Commentaire contexte: \(interview.contextComment)\n\n"
        }
        md += "## Notes\n\(interview.notes)\n"

        let activeTasks = interview.tasks.filter { !$0.isCompleted }
        if !activeTasks.isEmpty {
            md += "\n## Actions\n"
            for task in activeTasks {
                let projectSuffix = task.project.map { " (\($0.name))" } ?? ""
                md += "- \(task.title)\(projectSuffix)\n"
            }
        }

        let activeAlerts = interview.alerts.filter { !$0.isResolved }
        if !activeAlerts.isEmpty {
            md += "\n## Alertes\n"
            for alert in activeAlerts {
                let projectSuffix = alert.project.map { " (\($0.name))" } ?? ""
                md += "- [\(alert.severity)] \(alert.title)\(projectSuffix)\n"
                if !alert.detail.isEmpty {
                    md += "  - \(alert.detail)\n"
                }
            }
        }

        let attachments = interview.attachments.sorted(by: { $0.importedAt < $1.importedAt })
        if !attachments.isEmpty {
            md += "\n## Pièces jointes\n"
            for attachment in attachments {
                md += "- \(attachment.fileName)\n"
                if !attachment.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    md += "  - Commentaire: \(attachment.comment)\n"
                }
            }
        }

        return md
    }

    func exportInterviewEmail(interview: Interview) {
        let subject = "Compte-rendu entretien 1:1 - \(interview.collaborator?.name ?? "Collaborateur") - \(interview.date.formatted(date: .abbreviated, time: .omitted))"
        var body = "Bonjour,\n\n"
        body += "Voici le compte-rendu de l'entretien.\n\n"
        if let project = interview.selectedProject {
            body += "Projet concerné: \(project.name)\n"
        }
        if interview.shareWithEveryone {
            body += "Retour à partager avec l'ensemble de l'équipe: Oui\n"
        }
        if !interview.contextComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += "Contexte: \(interview.contextComment)\n"
        }
        body += "\nPoints abordés:\n\(interview.notes)\n\n"

        let pendingTasks = interview.tasks.filter { !$0.isCompleted }
        if !pendingTasks.isEmpty {
            body += "Actions:\n"
            for task in pendingTasks {
                let project = task.project?.name ?? interview.selectedProject?.name
                let suffix = project.map { " (\($0))" } ?? ""
                body += "- \(task.title)\(suffix)\n"
            }
            body += "\n"
        }

        let pendingAlerts = interview.alerts.filter { !$0.isResolved }
        if !pendingAlerts.isEmpty {
            body += "Alertes:\n"
            for alert in pendingAlerts {
                body += "- [\(alert.severity)] \(alert.title)\n"
            }
            body += "\n"
        }

        body += "Cordialement,\nLaurent DE BERTI"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }

    func exportToPDF(interview: Interview, fileName: String) {
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.topMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.bottomMargin = 36

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        textView.isEditable = false
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(makePDFContent(interview: interview))

        let printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
        printOperation.jobTitle = fileName
        printOperation.showsPrintPanel = true
        printOperation.run()
    }

    // MARK: - Meeting exports (stub reconstructions)

    struct MarkdownOptions: OptionSet {
        let rawValue: Int
        static let shareable = MarkdownOptions(rawValue: 1 << 0)
    }

    func exportMeetingMarkdown(meeting: Meeting, options: MarkdownOptions = []) -> String {
        var md = "# \(meeting.title.isEmpty ? "Réunion" : meeting.title)\n"
        md += "Date: \(meeting.date.formatted(date: .long, time: .shortened))\n"
        if let project = meeting.project {
            md += "Projet: \(project.name)\n"
        }
        md += "Type: \(meeting.kind.label)\n"
        if !options.contains(.shareable) {
            md += "Participants: \(meeting.participantsDescription)\n"
        }
        md += "\n"

        if !meeting.summary.isEmpty {
            md += "## Résumé\n\n\(meeting.summary)\n\n"
        }
        if !meeting.keyPoints.isEmpty {
            md += "## Points clés\n"
            for p in meeting.keyPoints { md += "- \(p)\n" }
            md += "\n"
        }
        if !meeting.decisions.isEmpty {
            md += "## Décisions\n"
            for d in meeting.decisions { md += "- \(d)\n" }
            md += "\n"
        }
        if !meeting.openQuestions.isEmpty {
            md += "## Questions ouvertes\n"
            for q in meeting.openQuestions { md += "- \(q)\n" }
            md += "\n"
        }
        let openTasks = meeting.tasks.filter { !$0.isCompleted }
        if !openTasks.isEmpty {
            md += "## Actions\n"
            for t in openTasks {
                let who = t.collaborator?.name ?? "Non assigné"
                let due = t.dueDate.map { " (échéance \($0.formatted(date: .numeric, time: .omitted)))" } ?? ""
                md += "- [\(who)] \(t.title)\(due)\n"
            }
            md += "\n"
        }
        if !meeting.liveNotes.isEmpty {
            md += "## Notes live\n\n\(meeting.liveNotes)\n"
        }
        return md
    }

    func exportMeetingPDF(meeting: Meeting, fileName: String) {
        let markdown = exportMeetingMarkdown(meeting: meeting)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.string = markdown
        textView.font = .systemFont(ofSize: 11)
        let printInfo = NSPrintInfo.shared
        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.jobTitle = fileName
        op.showsPrintPanel = true
        op.run()
    }

    func exportMeetingMail(meeting: Meeting) {
        let subject = meeting.title.isEmpty ? "Réunion" : meeting.title
        let body = exportMeetingMarkdown(meeting: meeting, options: .shareable)
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }

    func exportMeetingOutlookEML(meeting: Meeting) {
        let subject = meeting.title.isEmpty ? "Réunion" : meeting.title
        let body = exportMeetingMarkdown(meeting: meeting, options: .shareable)
        let eml = """
        Subject: \(subject)
        Content-Type: text/plain; charset=utf-8

        \(body)
        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(subject).eml")
        try? eml.write(to: tmp, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tmp)
    }

    func exportToAppleNotes(title: String, markdownContent: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = markdownContent.replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        tell application "Notes"
            activate
            make new note at folder "Notes" with properties {name: "\(escapedTitle)", body: "\(escapedBody)"}
        end tell
        """

        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript Error: \(err)")
            }
        }
    }

    func exportProjectsOverview(projects: [Project], entities: [Entity]) -> String {
        var md = "# Synthèse Projets\n\n"
        md += "Export généré le \(Date().formatted(date: .long, time: .shortened))\n\n"

        for entity in entities.sorted(by: { $0.name < $1.name }) {
            let entityProjects = entity.projects.sorted(by: { $0.name < $1.name })
            guard !entityProjects.isEmpty else { continue }

            md += "## \(entity.name)\n\n"
            for project in entityProjects {
                md += projectOverviewLine(project)
            }
            md += "\n"
        }

        let orphanProjects = projects.filter { $0.entity == nil }.sorted(by: { $0.name < $1.name })
        if !orphanProjects.isEmpty {
            md += "## Sans entité\n\n"
            for project in orphanProjects {
                md += projectOverviewLine(project)
            }
        }

        return md
    }

    private func makePDFContent(interview: Interview) -> NSAttributedString {
        let html = buildHTML(interview: interview)
        let data = Data(html.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributed = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed
        }

        return NSAttributedString(string: exportToMarkdown(interview: interview))
    }

    private func buildHTML(interview: Interview) -> String {
        if interview.type == .job {
            return buildJobHTML(interview: interview)
        }

        let dateString = interview.date.formatted(date: .long, time: .omitted)
        let collaborator = interview.collaborator?.name ?? "Collaborateur non renseigné"
        let notesHTML = htmlParagraphs(from: interview.notes)
        let actionsHTML = htmlList(
            interview.tasks
                .filter { !$0.isCompleted }
                .map { task in
                    let project = task.project.map { " <span class=\"muted\">(\($0.name))</span>" } ?? ""
                    return "<strong>\(escapeHTML(task.title))</strong>\(project)"
                }
        )
        let alertsHTML = htmlList(
            interview.alerts
                .filter { !$0.isResolved }
                .map { alert in
                    let detail = alert.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "<div class=\"muted\">\(escapeHTML(alert.detail))</div>"
                    let project = alert.project.map { " <span class=\"muted\">(\($0.name))</span>" } ?? ""
                    return "<strong>[\(escapeHTML(alert.severity))]</strong> \(escapeHTML(alert.title))\(project)\(detail)"
                }
        )
        let attachmentsHTML = htmlList(
            interview.attachments
                .sorted(by: { $0.importedAt < $1.importedAt })
                .map { attachment in
                    let comment = attachment.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "<div class=\"muted\">\(escapeHTML(attachment.comment))</div>"
                    return "<strong>\(escapeHTML(attachment.fileName))</strong>\(comment)"
                }
        )

        return """
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; color: #1f2937; font-size: 12px; line-height: 1.5; margin: 0; }
        .header { width: 100%; border-bottom: 2px solid #d71920; padding-bottom: 18px; margin-bottom: 22px; }
        .header td { vertical-align: top; }
        .logo { font-size: 28px; font-weight: 800; color: #d71920; letter-spacing: 1px; }
        .meta { text-align: right; }
        .meta .date { font-size: 14px; font-weight: 700; color: #111827; }
        .meta .person { font-size: 13px; margin-top: 4px; }
        .title { font-size: 22px; font-weight: 750; color: #111827; margin: 0 0 8px 0; }
        .subtitle { color: #6b7280; margin-bottom: 20px; }
        h2 { font-size: 14px; color: #111827; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; margin-top: 22px; margin-bottom: 10px; }
        p { margin: 0 0 8px 0; }
        ul { margin: 0; padding-left: 18px; }
        li { margin-bottom: 8px; }
        .muted { color: #6b7280; }
        .empty { color: #9ca3af; font-style: italic; }
        </style>
        </head>
        <body>
            <table class="header" cellspacing="0" cellpadding="0">
                <tr>
                    <td>
                        \(logoHTML())
                    </td>
                    <td class="meta">
                        <div class="date">\(escapeHTML(dateString))</div>
                        <div class="person">\(escapeHTML(collaborator))</div>
                        <div class="person">Laurent DE BERTI</div>
                    </td>
                </tr>
            </table>

            <div class="title">Compte-rendu d'entretien OneToOne</div>
            <div class="subtitle">Entretien individuel avec synthèse, actions, alertes et pièces jointes.</div>

            <h2>Entretien</h2>
            \(notesHTML)

            <h2>Actions</h2>
            \(actionsHTML)

            <h2>Alertes</h2>
            \(alertsHTML)

            <h2>Pièces jointes</h2>
            \(attachmentsHTML)
        </body>
        </html>
        """
    }

    private func exportJobToMarkdown(interview: Interview) -> String {
        var md = "# Entretien job - \(interview.collaborator?.name ?? "Candidat")\n"
        md += "Date: \(interview.date.formatted(date: .long, time: .omitted))\n\n"
        md += "## Synthèse\n\(interview.generalAssessment)\n\n"
        md += "## Expérience\n\(interview.cvExperienceNotes)\n\n"
        md += "## Compétences\n\(interview.cvSkillsNotes)\n\n"
        md += "## Motivation\n\(interview.cvMotivationNotes)\n\n"
        md += "## Points positifs\n\(interview.positivePoints)\n\n"
        md += "## Points négatifs\n\(interview.negativePoints)\n\n"
        md += "## Formation\n\(interview.trainingAssessment)\n\n"
        if !interview.candidateLinkedInURL.isEmpty || !interview.candidateLinkedInNotes.isEmpty {
            md += "## LinkedIn\nURL: \(interview.candidateLinkedInURL)\n\(interview.candidateLinkedInNotes)\n\n"
        }
        md += "## Notes libres\n\(interview.notes)\n"
        return md
    }

    private func buildJobHTML(interview: Interview) -> String {
        let dateString = interview.date.formatted(date: .long, time: .omitted)
        let candidate = interview.collaborator?.name ?? "Candidat"
        return """
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; color: #1f2937; font-size: 12px; line-height: 1.5; margin: 0; }
        .header { width: 100%; border-bottom: 2px solid #d71920; padding-bottom: 18px; margin-bottom: 22px; }
        .header td { vertical-align: top; }
        .logo { font-size: 28px; font-weight: 800; color: #d71920; letter-spacing: 1px; }
        .meta { text-align: right; }
        .meta .date { font-size: 14px; font-weight: 700; color: #111827; }
        .meta .person { font-size: 13px; margin-top: 4px; }
        .title { font-size: 22px; font-weight: 750; color: #111827; margin: 0 0 8px 0; }
        h2 { font-size: 14px; color: #111827; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; margin-top: 22px; margin-bottom: 10px; }
        p { margin: 0 0 8px 0; }
        </style>
        </head>
        <body>
            <table class="header" cellspacing="0" cellpadding="0">
                <tr>
                    <td>\(logoHTML())</td>
                    <td class="meta">
                        <div class="date">\(escapeHTML(dateString))</div>
                        <div class="person">\(escapeHTML(candidate))</div>
                        <div class="person">Laurent DE BERTI</div>
                    </td>
                </tr>
            </table>
            <div class="title">Compte-rendu d'entretien job</div>
            <h2>Synthèse</h2>\(htmlParagraphs(from: interview.generalAssessment))
            <h2>Expérience</h2>\(htmlParagraphs(from: interview.cvExperienceNotes))
            <h2>Compétences</h2>\(htmlParagraphs(from: interview.cvSkillsNotes))
            <h2>Motivation</h2>\(htmlParagraphs(from: interview.cvMotivationNotes))
            <h2>Points positifs</h2>\(htmlParagraphs(from: interview.positivePoints))
            <h2>Points négatifs</h2>\(htmlParagraphs(from: interview.negativePoints))
            <h2>Formation</h2>\(htmlParagraphs(from: interview.trainingAssessment))
            <h2>LinkedIn</h2>\(htmlParagraphs(from: [interview.candidateLinkedInURL, interview.candidateLinkedInNotes].filter { !$0.isEmpty }.joined(separator: "\n")))
            <h2>Notes libres</h2>\(htmlParagraphs(from: interview.notes))
        </body>
        </html>
        """
    }

    private func logoHTML() -> String {
        guard
            let image = NSImage(named: "APRILLogo"),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return "<div class=\"logo\">APRIL</div>"
        }

        let base64 = png.base64EncodedString()
        return "<img src=\"data:image/png;base64,\(base64)\" style=\"max-width: 140px; max-height: 44px;\" />"
    }

    private func htmlParagraphs(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "<p class=\"empty\">Aucune note saisie.</p>"
        }

        return trimmed
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined()
    }

    private func projectOverviewLine(_ project: Project) -> String {
        let sponsor = project.sponsor.isEmpty ? "Non renseigné" : project.sponsor
        let days = project.plannedDays?.formatted() ?? "n/a"
        let designDeadline = project.designEndDeadline?.formatted(date: .abbreviated, time: .omitted) ?? "n/a"
        return "- **\(project.code)** \(project.name) | Type: \(project.projectType) | Sponsor: \(sponsor) | Statut: \(project.status) | Phase: \(project.phase) | Jours: \(days) | Deadline design: \(designDeadline)\n"
    }

    private func htmlList(_ items: [String]) -> String {
        guard !items.isEmpty else {
            return "<p class=\"empty\">Aucun élément.</p>"
        }

        let listItems = items.map { "<li>\($0)</li>" }.joined()
        return "<ul>\(listItems)</ul>"
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
