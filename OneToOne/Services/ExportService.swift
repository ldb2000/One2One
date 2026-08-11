import Foundation
import AppKit
import PDFKit
import SwiftData
import WebKit

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

/// Service d'export des réunions (`Meeting`) vers
/// Markdown, PDF, mail (Apple Mail / Outlook) et Apple Notes.
/// `@MainActor` : manipule AppKit (NSPrintOperation, NSSavePanel, WKWebView,
/// NSWorkspace) et accède au `ModelContext` des modèles, donc tous les appels
/// doivent se faire depuis le thread principal.
@MainActor
class ExportService {



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
        let html = buildMeetingHTML(meeting: meeting, includeTranscript: false)

        // NSSavePanel pour cible.
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName.hasSuffix(".pdf") ? fileName : fileName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // WKWebView headless : charger HTML, attendre fin nav, createPDF.
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        let delegate = PDFExportDelegate(targetURL: url)
        webView.navigationDelegate = delegate
        // Ancre forte sur le delegate via objc_setAssociatedObject pour éviter
        // qu'il soit dealloc avant didFinish.
        objc_setAssociatedObject(webView, &PDFExportDelegate.assocKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // Garde aussi une référence forte sur la webView elle-même (sinon
        // après que cette fonction retourne, ARC libère webView et l'export
        // n'a jamais lieu).
        delegate.ownedWebView = webView
        webView.loadHTMLString(html, baseURL: nil)
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

    // MARK: - Mail compose (Apple Mail / Outlook)

    /// Construit le rapport HTML + pièces jointes éventuelles, calcule la liste
    /// des destinataires et ouvre une fenêtre de composition dans le client choisi.
    /// Destinataires = tous les participants (présents et absents) ayant une
    /// adresse valide (`isLikelyEmail`), dédupliqués sans tenir compte de la
    /// casse. En mode `.outlook`, retombe sur Apple Mail si la composition
    /// Outlook échoue (app absente).
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

    /// Sérialise un brouillon `.eml` MIME `multipart/mixed` qu'Apple Mail ouvre
    /// comme message éditable (en-tête `X-Unsent: 1`). Une frontière unique est
    /// générée par UUID. Le sujet est encodé en `=?UTF-8?B?…?=` ; le corps est
    /// une partie `text/html; charset=UTF-8` en `8bit` ; chaque pièce jointe est
    /// encodée en base64 (lignes wrappées à 76 caractères) avec son type MIME
    /// déduit de l'extension. Les fichiers illisibles sont ignorés.
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
        // Délégué au builder thémé (rapport styling 2026-05-22).
        // Le template courant du meeting est utilisé pour eyebrow + subtitle ;
        // si nil, fallback à template kind par défaut depuis meeting.kind.
        // Mode .outlook : styles inlinés + numérotation H2 + alternance lignes
        // pour contourner le renderer Word d'Outlook (Mac) qui ignore les CSS.
        let (name, role) = fetchOwnerIdentity(for: meeting)
        return ReportHTMLBuilder.build(
            meeting: meeting,
            template: meeting.reportTemplate,
            includeTranscript: includeTranscript,
            managerName: name,
            managerRole: role,
            mode: .outlook
        )
    }

    /// Récupère `AppSettings.ownerName` + `ownerRole` (rédacteur du rapport)
    /// depuis le ModelContext du meeting, fallback "" si non configuré.
    private func fetchOwnerIdentity(for meeting: Meeting) -> (name: String, role: String) {
        guard let context = meeting.modelContext else { return ("", "") }
        let descriptor = FetchDescriptor<AppSettings>()
        let all = (try? context.fetch(descriptor)) ?? []
        let s = all.canonicalSettings
        return (s?.ownerName ?? "", s?.ownerRole ?? "")
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

/// Délégué qui attend la fin du chargement HTML d'une WKWebView puis
/// produit un PDF à l'URL cible. Référence forte sur sa propre webView
/// (`ownedWebView`) pour rester en vie jusqu'à la fin de l'export.
/// Cycle de vie : créé par `exportMeetingPDF`, rattaché à la webView via
/// `objc_setAssociatedObject` (ancre forte côté webView) ; sans cette ancre,
/// ARC libérerait le délégué avant `didFinish` et l'export n'aurait jamais
/// lieu. Une fois le PDF écrit, `ownedWebView = nil` rompt les deux références
/// et laisse le tout se désallouer.
@MainActor
private final class PDFExportDelegate: NSObject, WKNavigationDelegate {
    nonisolated(unsafe) static var assocKey: UInt8 = 0
    let targetURL: URL
    var ownedWebView: WKWebView?

    init(targetURL: URL) {
        self.targetURL = targetURL
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Petit délai pour laisser le rendering finir (fonts, layouts).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let config = WKPDFConfiguration()
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: self.targetURL)
                        print("[Export] PDF écrit : \(self.targetURL.path) (\(data.count) octets)")
                    } catch {
                        print("[Export] échec écriture PDF : \(error)")
                    }
                case .failure(let error):
                    print("[Export] createPDF échec : \(error)")
                }
                // Relâcher la webView et donc le delegate.
                self.ownedWebView = nil
            }
        }
    }
}
