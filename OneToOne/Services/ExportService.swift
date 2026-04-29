import Foundation
import AppKit
import PDFKit

/// Options pour l'export mail d'une réunion.
/// `includeTranscript` ajoute la transcription brute en bas du corps.
/// `includeSlidesPDF` génère un PDF des slides capturées et l'attache.
struct MeetingMailExportOptions: OptionSet {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    static let includeTranscript = MeetingMailExportOptions(rawValue: 1 << 0)
    static let includeSlidesPDF  = MeetingMailExportOptions(rawValue: 1 << 1)
}

enum MeetingMailClient {
    case mail        // Apple Mail
    case outlook     // Microsoft Outlook
}

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

    /// Ouvre une fenêtre de composition dans Apple Mail avec le rapport
    /// formaté en HTML. Compatible avec les options transcript / slides PDF.
    func exportMeetingMail(meeting: Meeting, options: MeetingMailExportOptions = []) {
        composeMeetingMail(meeting: meeting, client: .mail, options: options)
    }

    /// Ouvre une fenêtre de composition dans Microsoft Outlook (Mac) avec
    /// le même rapport HTML. L'app Outlook doit être installée — sinon
    /// fallback sur Mail.
    func exportMeetingOutlook(meeting: Meeting, options: MeetingMailExportOptions = []) {
        composeMeetingMail(meeting: meeting, client: .outlook, options: options)
    }

    /// Conservé pour rétro-compat avec d'anciens callers : redirige vers
    /// Outlook (compose direct, pas .eml fichier).
    func exportMeetingOutlookEML(meeting: Meeting) {
        composeMeetingMail(meeting: meeting, client: .outlook, options: [])
    }

    // MARK: - Mail compose (Apple Mail / Outlook)

    private func composeMeetingMail(
        meeting: Meeting,
        client: MeetingMailClient,
        options: MeetingMailExportOptions
    ) {
        let subject = meetingMailSubject(meeting: meeting)
        let html = buildMeetingHTML(
            meeting: meeting,
            includeTranscript: options.contains(.includeTranscript)
        )
        var attachmentPaths: [String] = []
        if options.contains(.includeSlidesPDF), let pdfURL = makeMeetingSlidesPDF(meeting: meeting) {
            attachmentPaths.append(pdfURL.path)
        }

        // Tous les participants (présents + absents) avec une adresse mail
        // valide. Pas de doublon, comparaison case-insensitive.
        let recipients = meeting.participants
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isLikelyEmail($0) }
            .reduce(into: [String]()) { acc, email in
                if !acc.contains(where: { $0.lowercased() == email.lowercased() }) {
                    acc.append(email)
                }
            }

        switch client {
        case .outlook:
            if !runOutlookCompose(subject: subject, html: html, attachments: attachmentPaths, recipients: recipients) {
                _ = runMailCompose(subject: subject, html: html, attachments: attachmentPaths, recipients: recipients)
            }
        case .mail:
            _ = runMailCompose(subject: subject, html: html, attachments: attachmentPaths, recipients: recipients)
        }
    }

    private func isLikelyEmail(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        guard let at = s.firstIndex(of: "@") else { return false }
        let dot = s[at...].firstIndex(of: ".")
        return dot != nil && s.firstIndex(of: " ") == nil
    }

    private func meetingMailSubject(meeting: Meeting) -> String {
        let dateStr = meeting.date.formatted(date: .abbreviated, time: .shortened)
        let title = meeting.title.isEmpty ? "Réunion" : meeting.title
        if let project = meeting.project {
            return "CR-Auto: [\(project.code)] \(title) — \(dateStr)"
        }
        return "CR-Auto: \(title) — \(dateStr)"
    }

    @discardableResult
    private func runOutlookCompose(subject: String, html: String, attachments: [String], recipients: [String]) -> Bool {
        // AppleScript Outlook for Mac : create + open new message with HTML content.
        let escSubject = appleScriptEscape(subject)
        let escHTML = appleScriptEscape(html)

        var attachmentLines = ""
        for path in attachments {
            let escPath = appleScriptEscape(path)
            attachmentLines += "\n        make new attachment with properties {file:POSIX file \"\(escPath)\"}"
        }

        var recipientLines = ""
        for email in recipients {
            let escEmail = appleScriptEscape(email)
            recipientLines += "\n        make new recipient with properties {email address:{address:\"\(escEmail)\"}}"
        }

        let script = """
        tell application "Microsoft Outlook"
            activate
            set newMsg to make new outgoing message with properties {subject:"\(escSubject)", content:"\(escHTML)"}
            tell newMsg\(recipientLines)\(attachmentLines)
            end tell
            open newMsg
        end tell
        """

        return runAppleScript(source: script)
    }

    @discardableResult
    private func runMailCompose(subject: String, html: String, attachments: [String], recipients: [String]) -> Bool {
        // Apple Mail : AppleScript ne supporte pas l'HTML directement dans
        // `content`. On passe par un fichier .eml multipart avec body
        // text/html UTF-8 + pièces jointes base64. Mail.app ouvre l'EML
        // comme un brouillon éditable.
        let eml = buildMultipartEML(subject: subject, html: html, attachmentPaths: attachments, recipients: recipients)
        let safeName = subject.replacingOccurrences(of: "/", with: "-")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).eml")
        do {
            try eml.write(to: tmp, options: .atomic)
        } catch {
            return false
        }
        // Forcer l'ouverture dans Mail (au cas où l'utilisateur a Outlook
        // configuré comme client par défaut).
        let cfg = NSWorkspace.OpenConfiguration()
        let mailURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail")
        if let mailURL {
            NSWorkspace.shared.open([tmp], withApplicationAt: mailURL, configuration: cfg)
        } else {
            NSWorkspace.shared.open(tmp)
        }
        return true
    }

    private func buildMultipartEML(subject: String, html: String, attachmentPaths: [String], recipients: [String]) -> Data {
        let boundary = "----=_OneToOne_\(UUID().uuidString)"
        var raw = ""
        raw += "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=\r\n"
        if !recipients.isEmpty {
            raw += "To: \(recipients.joined(separator: ", "))\r\n"
        }
        raw += "MIME-Version: 1.0\r\n"
        raw += "X-Unsent: 1\r\n"  // Mail.app reconnaît X-Unsent comme draft.
        raw += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
        raw += "\r\n"

        // Partie HTML
        raw += "--\(boundary)\r\n"
        raw += "Content-Type: text/html; charset=UTF-8\r\n"
        raw += "Content-Transfer-Encoding: 8bit\r\n"
        raw += "\r\n"
        raw += html
        raw += "\r\n"

        var data = Data(raw.utf8)

        // Pièces jointes en base64
        for path in attachmentPaths {
            guard let attachData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            let fileName = (path as NSString).lastPathComponent
            let mime = mimeType(forPathExtension: (fileName as NSString).pathExtension)
            var part = ""
            part += "--\(boundary)\r\n"
            part += "Content-Type: \(mime); name=\"\(fileName)\"\r\n"
            part += "Content-Transfer-Encoding: base64\r\n"
            part += "Content-Disposition: attachment; filename=\"\(fileName)\"\r\n"
            part += "\r\n"
            data.append(contentsOf: part.utf8)
            // base64 wrap à 76 caractères pour conformité MIME.
            let b64 = attachData.base64EncodedString(options: .lineLength76Characters)
            data.append(contentsOf: b64.utf8)
            data.append(contentsOf: "\r\n".utf8)
        }
        data.append(contentsOf: "--\(boundary)--\r\n".utf8)
        return data
    }

    private func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "pdf":  return "application/pdf"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "txt":  return "text/plain; charset=UTF-8"
        case "html", "htm": return "text/html; charset=UTF-8"
        default:     return "application/octet-stream"
        }
    }

    @discardableResult
    private func runAppleScript(source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let err = error {
            print("[ExportService] AppleScript erreur: \(err)")
            return false
        }
        return true
    }

    private func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }

    // MARK: - Slides → PDF

    /// Génère un PDF à partir de toutes les slides capturées de la réunion
    /// (issues des `MeetingAttachment.slides`). Une slide par page.
    /// Retourne nil si aucune slide.
    private func makeMeetingSlidesPDF(meeting: Meeting) -> URL? {
        let slides = meeting.attachments
            .flatMap { $0.slides }
            .sorted { $0.index < $1.index }
        guard !slides.isEmpty else { return nil }

        let pdfDoc = PDFDocument()
        var pageIndex = 0
        for slide in slides {
            guard FileManager.default.fileExists(atPath: slide.imagePath),
                  let image = NSImage(contentsOfFile: slide.imagePath),
                  let page = PDFPage(image: image)
            else { continue }
            pdfDoc.insert(page, at: pageIndex)
            pageIndex += 1
        }
        guard pageIndex > 0 else { return nil }

        let safeTitle = (meeting.title.isEmpty ? "reunion" : meeting.title)
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle)-slides-\(UUID().uuidString.prefix(6)).pdf")
        guard pdfDoc.write(to: url) else { return nil }
        return url
    }

    // MARK: - HTML report builder

    /// Génère un HTML formaté du rapport de réunion : entête (titre, date,
    /// projet, participants) + résumé + points clés + décisions + questions
    /// ouvertes + actions + notes live + (optionnel) transcript intégral.
    private func buildMeetingHTML(meeting: Meeting, includeTranscript: Bool) -> String {
        let dateStr = meeting.date.formatted(date: .long, time: .shortened)
        let title = meeting.title.isEmpty ? "Réunion" : meeting.title
        let projectLine = meeting.project.map { p in
            "<div class=\"meta-line\"><strong>Projet</strong> · \(escapeHTML(p.code)) — \(escapeHTML(p.name))</div>"
        } ?? ""
        let participants = meeting.participants.map(\.name).sorted().joined(separator: ", ")
        let participantsLine = participants.isEmpty ? "" :
            "<div class=\"meta-line\"><strong>Participants</strong> · \(escapeHTML(participants))</div>"

        let summaryHTML = htmlParagraphs(from: meeting.summary)
        let keyPointsHTML = htmlList(meeting.keyPoints.map { escapeHTML($0) })
        let decisionsHTML = htmlList(meeting.decisions.map { escapeHTML($0) })
        let questionsHTML = htmlList(meeting.openQuestions.map { escapeHTML($0) })

        let openTasks = meeting.tasks.filter { !$0.isCompleted }
        let actionsHTML = htmlList(openTasks.map { task in
            let who = task.collaborator?.name ?? "Non assigné"
            let due = task.dueDate.map { " <span class=\"muted\">(échéance \($0.formatted(date: .numeric, time: .omitted)))</span>" } ?? ""
            return "<strong>\(escapeHTML(who))</strong> — \(escapeHTML(task.title))\(due)"
        })

        let liveNotesHTML: String
        if meeting.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liveNotesHTML = ""
        } else {
            liveNotesHTML = """
            <h2>Notes prises en live</h2>
            \(htmlParagraphs(from: meeting.liveNotes))
            """
        }

        let transcriptSection: String
        if includeTranscript, !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcriptSection = """
            <h2>Transcription complète</h2>
            <div class="transcript">\(htmlParagraphs(from: meeting.rawTranscript))</div>
            """
        } else {
            transcriptSection = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; color: #1f2937; font-size: 13px; line-height: 1.55; margin: 0; }
        .header { width: 100%; border-bottom: 2px solid #d71920; padding-bottom: 16px; margin-bottom: 18px; }
        .header td { vertical-align: top; }
        .logo { font-size: 26px; font-weight: 800; color: #d71920; letter-spacing: 1px; }
        .meta { text-align: right; }
        .meta .date { font-size: 14px; font-weight: 700; color: #111827; }
        .title { font-size: 22px; font-weight: 750; color: #111827; margin: 0 0 4px 0; }
        .meta-line { color: #374151; margin: 2px 0; font-size: 12px; }
        h2 { font-size: 14px; color: #111827; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; margin-top: 22px; margin-bottom: 10px; }
        p { margin: 0 0 8px 0; }
        ul { margin: 0; padding-left: 18px; }
        li { margin-bottom: 6px; }
        .muted { color: #6b7280; }
        .empty { color: #9ca3af; font-style: italic; }
        .transcript { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 6px; padding: 12px 14px; font-size: 12px; color: #374151; white-space: normal; }
        </style>
        </head>
        <body>
            <table class="header" cellspacing="0" cellpadding="0" width="100%">
                <tr>
                    <td>\(logoHTML())</td>
                    <td class="meta">
                        <div class="date">\(escapeHTML(dateStr))</div>
                        <div class="muted">Type · \(escapeHTML(meeting.kind.label))</div>
                        <div class="muted">Laurent DE BERTI</div>
                    </td>
                </tr>
            </table>

            <div class="title">\(escapeHTML(title))</div>
            \(projectLine)
            \(participantsLine)

            <h2>Résumé</h2>
            \(summaryHTML)

            <h2>Points clés</h2>
            \(keyPointsHTML)

            <h2>Décisions</h2>
            \(decisionsHTML)

            <h2>Questions ouvertes</h2>
            \(questionsHTML)

            <h2>Actions</h2>
            \(actionsHTML)

            \(liveNotesHTML)

            \(transcriptSection)
        </body>
        </html>
        """
    }

    /// Exporte une réunion vers Apple Notes en HTML formaté avec les mêmes
    /// options que les exports mail : transcript intégral facultatif et
    /// slides intégrées en base64 (Notes rend les `<img data:>` inline).
    func exportMeetingToAppleNotes(meeting: Meeting, options: MeetingMailExportOptions = []) {
        let title = meetingMailSubject(meeting: meeting)
        var html = buildMeetingHTML(
            meeting: meeting,
            includeTranscript: options.contains(.includeTranscript)
        )
        if options.contains(.includeSlidesPDF) {
            let slidesHTML = buildInlineSlidesHTML(meeting: meeting)
            if !slidesHTML.isEmpty {
                // Insère les slides juste avant la fermeture du body
                if let bodyClose = html.range(of: "</body>") {
                    html.replaceSubrange(bodyClose, with: "\(slidesHTML)\n</body>")
                } else {
                    html.append(slidesHTML)
                }
            }
        }

        let escapedTitle = appleScriptEscape(title)
        let escapedBody = appleScriptEscape(html)
        let script = """
        tell application "Notes"
            activate
            make new note at folder "Notes" with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
        end tell
        """
        runAppleScript(source: script)
    }

    /// Conserve l'ancienne API pour quelques callers ; redirige vers la
    /// version riche si on identifie le contenu comme un meeting markdown
    /// (sinon on retombe sur le comportement legacy plain-text).
    func exportToAppleNotes(title: String, markdownContent: String) {
        let escapedTitle = appleScriptEscape(title)
        let escapedBody = appleScriptEscape(markdownContent)
        let script = """
        tell application "Notes"
            activate
            make new note at folder "Notes" with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
        end tell
        """
        runAppleScript(source: script)
    }

    /// Génère un bloc HTML avec toutes les slides capturées en base64
    /// (data URI). Notes rend les `<img>` inline. Une slide par "page".
    private func buildInlineSlidesHTML(meeting: Meeting) -> String {
        let slides = meeting.attachments
            .flatMap { $0.slides }
            .sorted { $0.index < $1.index }
        guard !slides.isEmpty else { return "" }

        var html = "<h2>Slides capturées</h2>\n"
        for slide in slides {
            guard FileManager.default.fileExists(atPath: slide.imagePath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: slide.imagePath))
            else { continue }
            let mime: String
            switch (slide.imagePath as NSString).pathExtension.lowercased() {
            case "png":          mime = "image/png"
            case "jpg", "jpeg":  mime = "image/jpeg"
            case "gif":          mime = "image/gif"
            default:             mime = "image/png"
            }
            let b64 = data.base64EncodedString()
            html += "<div style=\"margin: 12px 0;\"><img src=\"data:\(mime);base64,\(b64)\" style=\"max-width:100%;border:1px solid #e5e7eb;border-radius:6px;\" /></div>\n"
            if !slide.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                html += "<p class=\"muted\">\(escapeHTML(slide.ocrText))</p>\n"
            }
        }
        return html
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
