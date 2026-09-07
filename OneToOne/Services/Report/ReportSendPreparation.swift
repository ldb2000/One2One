import Foundation
import os
import PDFKit
import AppKit

private let sendLog = Logger(subsystem: "com.onetoone.app", category: "report-send")

/// Ce que produisent les trois cases du pied `À L'ENVOI DU RAPPORT`.
struct ReportSendPlan: Equatable {
    var attachmentPaths: [String]
    var recipients: [String]
    var projectCopies: [URL]
}

/// Les trois cases du pied du tiroir Ressources (spec §4.1), exécutées **au
/// moment de l'envoi** — jamais à la génération.
///
/// La distinction n'est pas cosmétique : générer un rapport est un geste qu'on
/// répète, souvent plusieurs fois de suite pour ajuster un gabarit. Verser des
/// pièces dans les documents du projet à chaque essai remplirait la fiche de
/// doublons, et recalculer des destinataires à chaque essai n'aurait aucun
/// sens. Le lot 6 ne faisait que **persister** les trois cases ; c'est ici
/// qu'elles agissent.
@MainActor
enum ReportSendPreparation {

    // MARK: - Annexes

    /// Les fichiers joints au rapport : les pièces épinglées si la case l'est,
    /// puis un PDF des captures cochées `Joindre au rapport`.
    ///
    /// Une pièce dont le fichier a disparu est ignorée en silence : le rapport
    /// part quand même, ce qui vaut mieux qu'un envoi bloqué par un fichier
    /// rangé ailleurs entre-temps.
    static func annexPaths(for meeting: Meeting,
                           options: AttachmentReportOptions) -> [String] {
        var chemins: [String] = []
        if options.attachPinned {
            chemins += meeting.pinnedAttachments
                .map(\.filePath)
                .filter { FileManager.default.fileExists(atPath: $0) }
        }
        if let pdf = capturesPDF(for: meeting) { chemins.append(pdf.path) }
        return chemins
    }

    /// Un PDF d'une page par capture cochée, dans l'ordre du bloc de rapport.
    ///
    /// Même chemin que le PDF de slides d'`ExportService`, mais restreint aux
    /// captures que l'utilisateur a cochées : joindre les autres irait
    /// directement contre la case.
    static func capturesPDF(for meeting: Meeting) -> URL? {
        let entrees = ReportOptionalBlocks.captures(of: meeting)
        guard !entrees.isEmpty else { return nil }
        let doc = PDFDocument()
        var page = 0
        for entree in entrees {
            guard FileManager.default.fileExists(atPath: entree.imagePath),
                  let image = NSImage(contentsOfFile: entree.imagePath),
                  let p = PDFPage(image: image) else { continue }
            doc.insert(p, at: page)
            page += 1
        }
        guard page > 0 else { return nil }
        let nom = (meeting.title.isEmpty ? "reunion" : meeting.title)
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nom)-captures-\(UUID().uuidString.prefix(6)).pdf")
        return doc.write(to: url) ? url : nil
    }

    // MARK: - Destinataires

    /// « Donner l'accès aux participants » = les adresses des participants
    /// **présents**.
    ///
    /// Case décochée, la liste est vide : l'utilisateur adresse le message
    /// lui-même, et c'est exactement ce que décocher veut dire. Les absents en
    /// sont écartés — leur envoyer un compte-rendu de séance sans les avoir
    /// prévenus n'est pas ce que la case promet.
    static func recipients(for meeting: Meeting,
                           options: AttachmentReportOptions) -> [String] {
        guard options.grantAccessToParticipants else { return [] }
        return meeting.participants
            .filter { meeting.participantStatus(for: $0) == .present }
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isLikelyEmail)
            .reduce(into: [String]()) { acc, mail in
                if !acc.contains(where: { $0.lowercased() == mail.lowercased() }) {
                    acc.append(mail)
                }
            }
    }

    private static func isLikelyEmail(_ s: String) -> Bool {
        guard !s.isEmpty, let at = s.firstIndex(of: "@") else { return false }
        return s[at...].firstIndex(of: ".") != nil && s.firstIndex(of: " ") == nil
    }

    // MARK: - Versement dans les documents du projet

    /// Copie les pièces épinglées dans `Bucket.project(code:)` et crée les
    /// `ProjectAttachment` correspondants — l'exécution effective de la
    /// troisième case du lot 6, qui n'était jusqu'ici que persistée.
    ///
    /// Idempotent par nom de fichier : verser deux fois la même pièce n'ajoute
    /// qu'une entrée à la fiche. Une erreur de copie est journalisée et
    /// n'arrête pas les suivantes — un disque plein sur une pièce ne doit pas
    /// faire perdre les autres.
    ///
    /// - Parameter base: racine du stockage. Paramétrée pour que les tests
    ///   écrivent dans un dossier temporaire : « copie, jamais référence » (D5)
    ///   n'est vérifiable qu'en observant le disque.
    @discardableResult
    static func pushToProject(_ meeting: Meeting,
                              options: AttachmentReportOptions,
                              base: URL = AttachmentImporter.baseDirectory()) -> [URL] {
        guard options.pushToProject, let projet = meeting.project else { return [] }
        var copies: [URL] = []
        for piece in meeting.pinnedAttachments {
            guard FileManager.default.fileExists(atPath: piece.filePath) else { continue }
            guard !projet.attachments.contains(where: { $0.fileName == piece.fileName })
            else { continue }
            do {
                let copie = try AttachmentImporter.copyIntoAppSupport(
                    source: URL(fileURLWithPath: piece.filePath),
                    bucket: .project(code: projet.code),
                    base: base)
                let versee = ProjectAttachment(url: copie,
                                               category: "Réunion",
                                               comment: "Versé depuis « \(meeting.title) »")
                // Nom d'affichage = celui de la pièce, sans l'horodatage que
                // la copie ajoute : la fiche projet montre un document, pas un
                // nom de fichier technique.
                versee.fileName = piece.fileName
                versee.project = projet
                meeting.modelContext?.insert(versee)
                copies.append(copie)
            } catch {
                sendLog.error("versement projet impossible : \(String(describing: error), privacy: .public)")
            }
        }
        if !copies.isEmpty { try? meeting.modelContext?.save() }
        return copies
    }

    // MARK: - Tout, dans l'ordre

    /// Les trois cases, appliquées d'un coup au moment de l'envoi.
    @discardableResult
    static func prepare(_ meeting: Meeting,
                        base: URL = AttachmentImporter.baseDirectory()) -> ReportSendPlan {
        let options = meeting.reportAttachmentOptions
        return ReportSendPlan(
            attachmentPaths: annexPaths(for: meeting, options: options),
            recipients: recipients(for: meeting, options: options),
            projectCopies: pushToProject(meeting, options: options, base: base))
    }
}
