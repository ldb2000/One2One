import Foundation
import SwiftData
import os

private let mailScanLog = Logger(subsystem: "com.onetoone.app", category: "mail-scan")

// MARK: - Accesseur réglage boîtes (côté Services : AppSettings ne connaît pas MailboxRef)

extension AppSettings {
    /// Boîtes scannées par le scan automatique (round-trip JSON).
    var mailAutoIndexMailboxes: [MailboxRef] {
        get {
            (try? JSONDecoder().decode([MailboxRef].self,
                                       from: Data(mailAutoIndexMailboxesJSON.utf8))) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                mailAutoIndexMailboxesJSON = json
            }
        }
    }
}

// MARK: - MailAutoIndexService

/// Orchestrateur du scan automatique de mails : boucle périodique (pattern
/// ContactPhotoService), pipeline scan → matching (heuristiques puis Gemma 4)
/// → décision (rattacher / suggérer / ignorer) exécuté dans un job `.mailScan`.
@MainActor
final class MailAutoIndexService {

    static let shared = MailAutoIndexService()
    private init() {}

    private var scanTask: Task<Void, Never>?
    private var activeScanJobID: UUID?

    enum Outcome: Equatable {
        case attach, suggest, ignore
    }

    /// Décision par seuils — pur, testé.
    static func outcome(confidence: Double, autoThreshold: Double, suggestThreshold: Double) -> Outcome {
        if confidence >= autoThreshold { return .attach }
        if confidence >= suggestThreshold { return .suggest }
        return .ignore
    }

    /// Carte threadTopic (lowercased) → code projet des fils déjà rattachés.
    static func threadProjectCodes(in context: ModelContext) -> [String: String] {
        let mails = (try? context.fetch(FetchDescriptor<ProjectMail>())) ?? []
        var map: [String: String] = [:]
        for mail in mails {
            guard let code = mail.project?.code else { continue }
            let topic = mail.threadTopic.lowercased()
            guard !topic.isEmpty, map[topic] == nil else { continue }
            map[topic] = code
        }
        return map
    }

    /// Annule et ré-arme la boucle périodique selon les réglages.
    /// Désactivé → arrêt. Lance aussi une passe immédiate si la dernière
    /// remonte à plus d'un intervalle (ou n'a jamais eu lieu).
    func reschedule(context: ModelContext, settings: AppSettings) {
        scanTask?.cancel()
        scanTask = nil
        guard settings.mailAutoIndexEnabled else { return }

        let interval = max(5, settings.mailAutoIndexIntervalMinutes)
        let due = settings.mailAutoIndexLastScanAt
            .map { Date().timeIntervalSince($0) > Double(interval) * 60 } ?? true
        if due { scanNow(context: context, settings: settings) }

        let nanos = UInt64(interval) * 60 * 1_000_000_000
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                await MainActor.run { self?.scanNow(context: context, settings: settings) }
            }
        }
    }

    /// Enfile une passe de scan dans la JobQueue. No-op si une passe est déjà
    /// active ou si aucune boîte n'est sélectionnée.
    func scanNow(context: ModelContext, settings: AppSettings) {
        let queue = JobQueue.shared
        if let id = activeScanJobID,
           queue.jobs.contains(where: { $0.id == id && !$0.status.isTerminal }) {
            return
        }
        let mailboxes = settings.mailAutoIndexMailboxes
        guard settings.mailAutoIndexEnabled, !mailboxes.isEmpty else { return }

        let jobID = queue.start(kind: .mailScan, meetingTitle: "Scan des mails") { jobID in
            try await MailAutoIndexService.shared.runScan(
                jobID: jobID, mailboxes: mailboxes,
                context: context, settings: settings
            )
        }
        activeScanJobID = jobID
    }

    /// Corps du job de scan. Erreurs par mail non fatales (comptées, le mail
    /// reste sans record → re-tenté à la prochaine passe) ; le job échoue en
    /// fin de passe si des erreurs ont eu lieu, avec un statut explicite.
    private func runScan(
        jobID: UUID,
        mailboxes: [MailboxRef],
        context: ModelContext,
        settings: AppSettings
    ) async throws {
        let queue = JobQueue.shared
        let autoThreshold = settings.mailAutoIndexAutoThreshold
        let suggestThreshold = settings.mailAutoIndexSuggestThreshold
        let lookback = settings.mailAutoIndexLookbackDays

        MailScanStore.deleteOrphanSuggestions(in: context)

        // Entrées de matching préparées une fois par passe.
        // ⚠️ Project.code n'a pas de contrainte d'unicité : uniquingKeysWith
        // obligatoire (uniqueKeysWithValues crasherait sur un doublon), et on
        // exclut les archivés (cohérent avec projectEntries).
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let entries = MailProjectMatcher.projectEntries(from: projects)
        let projectByCode = Dictionary(
            projects.filter { !$0.isArchived }.map { ($0.code, $0) },
            uniquingKeysWith: { first, _ in first })
        let candidates = entries.map {
            MailLLMClassifier.Candidate(code: $0.code, name: $0.name,
                                        collaborators: $0.collaboratorEmails)
        }
        var threadCodes = Self.threadProjectCodes(in: context)
        // `var` + insertions au fil de la passe : un même messageId présent
        // dans deux boîtes sélectionnées n'est évalué qu'une fois.
        var known = MailScanStore.knownMessageIds(in: context)

        var attached = 0, suggested = 0, ignored = 0, errors = 0
        var truncatedMailboxes: [String] = []

        for (boxIndex, mailbox) in mailboxes.enumerated() {
            try Task.checkCancellation()
            queue.updateProgress(jobID, fraction: Double(boxIndex) / Double(mailboxes.count),
                                 status: "Lecture de \(mailbox.displayName)…")

            let scanLimit = 2000
            let snippets: [MailSnippet]
            do {
                snippets = try await MailService.listRecentRead(
                    limit: scanLimit, lookbackDays: lookback, mailbox: mailbox)
            } catch {
                // Permission Automation refusée / Mail indisponible → échec franc.
                throw error
            }
            if snippets.count >= scanLimit {
                // Garde-fou atteint : les mails les plus anciens de la fenêtre
                // n'ont pas été vus — signalé, jamais silencieux.
                truncatedMailboxes.append(mailbox.displayName)
                mailScanLog.warning("scan \(mailbox.displayName, privacy: .public): garde-fou 2000 mails atteint, fenêtre tronquée")
            }
            let fresh = snippets.filter { !known.contains($0.messageId) }
            mailScanLog.info("scan \(mailbox.displayName, privacy: .public): \(snippets.count) lus, \(fresh.count) nouveaux")

            for (i, snippet) in fresh.enumerated() {
                try Task.checkCancellation()
                queue.updateProgress(
                    jobID,
                    fraction: (Double(boxIndex) + Double(i) / Double(max(1, fresh.count)))
                        / Double(mailboxes.count),
                    status: "\(mailbox.displayName) — \(i + 1)/\(fresh.count)")

                // Étage 1 : heuristiques.
                var verdict = MailProjectMatcher.match(
                    subject: snippet.subject, sender: snippet.sender,
                    projects: entries, threadProjectCodes: threadCodes)
                var forceIgnore = false

                // Étage 2 : Gemma 4, seulement sous le seuil auto. Sémantique
                // spec §4 : le verdict LLM REMPLACE l'heuristique (il peut
                // rétrograder un match douteux) ; réponse inexploitable →
                // ignoré ; LLM indisponible → repli heuristique.
                if verdict.confidence < autoThreshold, !candidates.isEmpty {
                    switch await MailLLMClassifier.classify(
                        subject: snippet.subject, sender: snippet.sender,
                        preview: snippet.preview, candidates: candidates,
                        settings: settings) {
                    case .verdict(let llm): verdict = llm
                    case .unparseable:      forceIgnore = true
                    case .unavailable:      break // verdict heuristique conservé
                    }
                }

                let project = verdict.projectCode.flatMap { projectByCode[$0] }
                let decision: Outcome = (forceIgnore || project == nil)
                    ? .ignore
                    : Self.outcome(confidence: verdict.confidence,
                                   autoThreshold: autoThreshold,
                                   suggestThreshold: suggestThreshold)

                switch decision {
                case .attach:
                    do {
                        let body = try await MailService.fetchBody(
                            messageId: snippet.messageId,
                            accountName: snippet.accountName,
                            mailbox: snippet.mailbox)
                        let attachments = (try? await MailService.saveAttachments(
                            messageId: snippet.messageId,
                            accountName: snippet.accountName,
                            mailbox: snippet.mailbox)) ?? []
                        _ = try await ProjectMailStore.save(
                            snippet: snippet, body: body,
                            attachments: attachments,
                            to: project!, context: context)
                        MailScanStore.record(snippet.messageId, verdict: .attached, in: context)
                        known.insert(snippet.messageId)
                        // Le fil devient un signal de continuité pour la suite de la passe.
                        let topic = ProjectMailStore.normalizedThreadTopic(for: snippet.subject).lowercased()
                        if !topic.isEmpty, threadCodes[topic] == nil {
                            threadCodes[topic] = project!.code
                        }
                        attached += 1
                    } catch {
                        // Embedding indisponible, AppleScript en échec… :
                        // PAS de record → re-tenté à la prochaine passe.
                        // ⚠️ ProjectMailStore.save persiste le ProjectMail AVANT
                        // l'embedding (reindex) : si l'embedding a échoué, un
                        // ProjectMail sans chunks a pu être sauvé — il rendrait
                        // le messageId « connu » à jamais sans jamais être
                        // indexé. On l'annule explicitement.
                        if let halfSaved = ((try? context.fetch(FetchDescriptor<ProjectMail>())) ?? [])
                            .first(where: { $0.messageId == snippet.messageId && $0.chunks.isEmpty }) {
                            context.delete(halfSaved)
                            try? context.save()
                        }
                        errors += 1
                        mailScanLog.error("rattachement échoué \(snippet.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                case .suggest:
                    let suggestion = MailIndexSuggestion(
                        messageId: snippet.messageId,
                        accountName: snippet.accountName,
                        mailbox: snippet.mailbox,
                        subject: snippet.subject,
                        sender: snippet.sender,
                        dateReceived: snippet.dateReceived,
                        preview: snippet.preview,
                        confidence: verdict.confidence)
                    suggestion.suggestedProject = project
                    context.insert(suggestion)
                    MailScanStore.record(snippet.messageId, verdict: .suggested, in: context)
                    known.insert(snippet.messageId)
                    suggested += 1
                case .ignore:
                    MailScanStore.record(snippet.messageId, verdict: .ignored, in: context)
                    known.insert(snippet.messageId)
                    ignored += 1
                }
                try? context.save()
            }
        }

        MailScanStore.purgeRecords(olderThanDays: lookback + 30, in: context)
        let status = "\(attached) rattaché(s), \(suggested) suggéré(s), \(ignored) ignoré(s)"
            + (errors > 0 ? ", \(errors) erreur(s)" : "")
            + (truncatedMailboxes.isEmpty ? "" : " — fenêtre tronquée : \(truncatedMailboxes.joined(separator: ", "))")
        settings.mailAutoIndexLastScanAt = Date()
        settings.mailAutoIndexLastScanStatus = status
        try? context.save()
        mailScanLog.info("scan terminé: \(status, privacy: .public)")

        if errors > 0 {
            struct ScanError: LocalizedError {
                let message: String
                var errorDescription: String? { message }
            }
            throw ScanError(message: "\(errors) mail(s) en erreur — re-tentés à la prochaine passe (\(status))")
        }
        queue.updateProgress(jobID, fraction: 1.0, status: status)
    }
}
