import Foundation
import EventKit
import os

private let recapLog = Logger(subsystem: "com.onetoone.app", category: "oneonone")

/// Les trois sorties de la clôture d'un entretien (spec §3.3 `CLÔTURER`,
/// §6.2 `EN SORTANT`) : envoyer le récap, planifier le prochain, verser dans
/// mon dossier annuel.
///
/// Séparées de `OneOnOneRecapBuilder`, qui reste pur : le texte du récap est
/// testable sans Mail, sans calendrier et sans disque, et ces trois-là ne
/// contiennent plus **aucune** décision de contenu.
///
/// Aucune ne pose de dialogue bloquant : un refus d'autorisation calendrier ou
/// une adresse manquante rendent `false`, à l'écran de le dire.
@MainActor
enum OneOnOneRecapActions {

    // MARK: - Envoyer le récap

    /// Ouvre une composition de mail avec le récap filtré.
    ///
    /// - Returns: `false` si la composition n'a pas pu s'ouvrir.
    @discardableResult
    static func sendRecap(for meeting: Meeting,
                          thread: OneOnOneThread,
                          audience: Audience,
                          now: Date = Date(),
                          export: ExportService? = nil) -> Bool {
        // Instancié ici et non en valeur par défaut : `ExportService` est
        // `@MainActor`, et une valeur par défaut s'évalue dans un contexte
        // non isolé.
        let export = export ?? ExportService()
        let markdown = OneOnOneRecapBuilder.markdown(for: meeting, thread: thread,
                                                      audience: audience, now: now)
        let sujet = OneOnOneRecapBuilder.subject(for: meeting, thread: thread)
        let destinataires = OneOnOneRecapBuilder.recipients(for: thread)
        let envoye = export.composeMail(subject: sujet,
                                        html: htmlBody(markdown),
                                        recipients: destinataires)
        recapLog.info("récap: audience=\(audience.rawValue, privacy: .public) ouvert=\(envoye)")
        return envoye
    }

    /// Le markdown enveloppé dans un HTML minimal — Apple Mail attend de
    /// l'HTML, et un markdown brut y arriverait avec ses dièses.
    ///
    /// Volontairement sans mise en forme riche : ce récap est lu dans un client
    /// de messagerie, pas dans le rapport. `ReportHTMLBuilder` reste réservé au
    /// rapport (lot 15).
    static func htmlBody(_ markdown: String) -> String {
        let corps = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <html><body style="font-family:-apple-system,Helvetica,sans-serif;font-size:13px">
        <pre style="font-family:inherit;white-space:pre-wrap">\(corps)</pre>
        </body></html>
        """
    }

    // MARK: - Planifier le prochain

    /// Crée l'événement du prochain entretien : `dernier + cadence`, 30 min,
    /// titre `1:1 — <Prénom>`.
    ///
    /// - Returns: `false` sans cadence convenue, sans séance tenue, sans
    ///   autorisation calendrier ou sans calendrier par défaut. **Jamais de
    ///   dialogue bloquant** : la clôture ne doit pas s'arrêter là.
    @discardableResult
    static func planNext(for thread: OneOnOneThread,
                         now: Date = Date(),
                         store: EKEventStore = EKEventStore()) async -> Bool {
        guard let date = OneOnOneThreadStore.nextPlannedDate(of: thread, now: now) else {
            recapLog.info("planifier: aucune cadence ou aucune séance tenue")
            return false
        }
        guard await requestCalendarAccess(store) else {
            recapLog.info("planifier: accès calendrier refusé")
            return false
        }
        guard let calendrier = store.defaultCalendarForNewEvents else {
            recapLog.info("planifier: aucun calendrier par défaut")
            return false
        }

        let evenement = EKEvent(eventStore: store)
        evenement.title = OneOnOneRecapBuilder.nextMeetingTitle(for: thread)
        evenement.startDate = date
        evenement.endDate = date.addingTimeInterval(30 * 60)
        evenement.calendar = calendrier

        do {
            try store.save(evenement, span: .thisEvent)
            recapLog.info("planifier: événement créé")
            return true
        } catch {
            recapLog.error("planifier: échec \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func requestCalendarAccess(_ store: EKEventStore) async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
        return (try? await store.requestAccess(to: .event)) ?? false
    }

    // MARK: - Verser dans mon dossier annuel

    /// Écrit le récap **d'audience `.me`** dans
    /// `recordings/annual/<année>/<collaborateur>/<yyyy-MM-dd>.md`.
    ///
    /// Audience `.me` et non `.collaborator` : c'est *mon* dossier, celui que
    /// je relirai avant l'entretien annuel. Y verser une version tronquée
    /// serait s'auto-censurer ses propres notes.
    ///
    /// Écrasement volontaire : deux clôtures du même entretien produisent **un**
    /// fichier, pas deux. Le nom porte le jour de l'entretien, qui est son
    /// identité.
    @discardableResult
    static func archiveToAnnualFolder(for meeting: Meeting,
                                      thread: OneOnOneThread,
                                      now: Date = Date(),
                                      root: URL? = nil) throws -> URL {
        let dossier = OneOnOneRecapBuilder.annualFolderURL(for: thread,
                                                            date: meeting.date,
                                                            root: root)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let fichier = dossier.appendingPathComponent(
            OneOnOneRecapBuilder.annualFileName(for: meeting.date))
        let markdown = OneOnOneRecapBuilder.markdown(for: meeting, thread: thread,
                                                      audience: .me, now: now)
        try markdown.write(to: fichier, atomically: true, encoding: .utf8)
        recapLog.info("dossier annuel: \(fichier.lastPathComponent, privacy: .public)")
        return fichier
    }
}
