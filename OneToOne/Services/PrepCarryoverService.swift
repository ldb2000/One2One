import Foundation
import SwiftData
import os

private let prepLog = Logger(subsystem: "com.onetoone.app", category: "prep-carryover")

/// Bidirectional flow between meeting-attached `prepNotes` and the standing
/// pool (`Collaborator.standingPrepNotes` or `Project.standingPrepNotes`).
///
/// - `drainStandingIntoMeeting(_:in:)` — at meeting creation / 1st prep tab open:
///   moves the pool content into `meeting.prepNotes` and clears the pool.
/// - `carryoverUncheckedFromMeeting(_:settings:in:)` — at transcription end:
///   pushes unchecked `[ ]` items from `meeting.prepNotes` back to the pool.
///
/// Idempotence: drain via `meeting.prepDrainDone`, carryover via
/// `meeting.prepCarryoverDone` — flags séparés pour que le drain d'ouverture
/// ne bloque pas le carryover de fin.
enum PrepCarryoverService {

    /// Extracts lines matching `- [ ] ...` (with optional leading whitespace).
    /// Used by carryover. Preserves indentation and original text.
    static func extractUncheckedItems(from md: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\s*)- \[ \] (.+)$"#,
            options: [.anchorsMatchLines]
        ) else { return [] }
        let ns = md as NSString
        let matches = regex.matches(in: md, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range) }
    }
}

extension PrepCarryoverService {

    /// Drains the standing pool of the relevant collab/project into the
    /// meeting's `prepNotes` and clears the pool. Idempotent via
    /// `meeting.prepDrainDone`.
    /// - For `.global` / `.work`: no pool exists; sets the flag and returns.
    @MainActor
    /// Verse dans la réunion la préparation « en attente » de ce qu'elle
    /// concerne — le collaborateur qu'on va voir, ou le projet.
    ///
    /// **Le drapeau ne se pose que si quelque chose a été versé.** Il
    /// enregistrait « on a essayé » : une réunion ouverte avant que la prep
    /// soit écrite brûlait sa seule chance, et la prep écrite ensuite
    /// n'entrait plus jamais. Constaté le 2026-08-14 sur la réunion du 13/08
    /// avec BARBA Jean Marc : drain fait, prep de zéro caractère, et 32
    /// caractères en attente sur la fiche.
    ///
    /// **Tous les participants sont lus, pas seulement le premier.** Sur un
    /// 1:1 à deux, `participants.first` peut être soi-même : la préparation de
    /// l'autre n'aurait jamais été vue.
    /// Rouvre la chance des réunions dont le drapeau a été posé sans que rien
    /// n'ait été versé — le défaut corrigé le 2026-08-14. Une réunion marquée
    /// « drainée » avec une préparation vide n'a rien reçu : rien ne justifie
    /// de lui fermer la porte.
    ///
    /// Renvoie le nombre de réunions rouvertes. Idempotente : une fois qu'une
    /// prep y est versée, elles ne remplissent plus la condition.
    @discardableResult
    static func reopenBurnedDrains(in context: ModelContext) -> Int {
        guard let reunions = try? context.fetch(FetchDescriptor<Meeting>()) else { return 0 }
        var rouvertes = 0
        for reunion in reunions
        where reunion.prepDrainDone
            && reunion.prepNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reunion.prepDrainDone = false
            rouvertes += 1
        }
        if rouvertes > 0 { try? context.save() }
        return rouvertes
    }

    static func drainStandingIntoMeeting(_ meeting: Meeting, in context: ModelContext) {
        guard !meeting.prepDrainDone else { return }
        var verse = false

        switch meeting.kind {
        case .oneToOne, .manager:
            for collab in meeting.participants where !collab.standingPrepNotes.isEmpty {
                meeting.prepNotes = mergePrep(standing: collab.standingPrepNotes,
                                              existing: meeting.prepNotes)
                collab.standingPrepNotes = ""
                collab.standingPrepUpdatedAt = Date()
                verse = true
            }
        case .project:
            if let project = meeting.project, !project.standingPrepNotes.isEmpty {
                meeting.prepNotes = mergePrep(standing: project.standingPrepNotes,
                                              existing: meeting.prepNotes)
                project.standingPrepNotes = ""
                project.standingPrepUpdatedAt = Date()
                verse = true
            }
        case .global, .work, .note:
            // Ces types n'ont aucune préparation à recevoir, jamais : fermer
            // la porte ne leur coûte rien et évite de re-vérifier.
            meeting.prepDrainDone = true
        }

        // Ailleurs : rien versé, rien à protéger. La chance reste ouverte pour
        // une prep écrite plus tard — c'est tout l'objet du correctif.
        if verse { meeting.prepDrainDone = true }
        try? context.save()
        prepLog.info("drain kind=\(meeting.kind.rawValue, privacy: .public) verse=\(verse, privacy: .public) bytes=\(meeting.prepNotes.count)")
    }

    /// Concatène le contenu du pool permanent en tête des notes existantes
    /// (séparés par une ligne vide). Retourne `standing` tel quel si la
    /// réunion n'a pas encore de notes.
    private static func mergePrep(standing: String, existing: String) -> String {
        if existing.isEmpty { return standing }
        return standing + "\n\n" + existing
    }
}

extension PrepCarryoverService {

    /// At meeting end (transcription finished or manual close): extract unchecked
    /// `[ ]` items from `meeting.prepNotes` and prepend them to the relevant
    /// standing pool (`collab` for .oneToOne/.manager, `project` for .project).
    /// Idempotent via `meeting.prepCarryoverDone`.
    @MainActor
    static func carryoverUncheckedFromMeeting(
        _ meeting: Meeting,
        settings: AppSettings,
        in context: ModelContext
    ) {
        guard settings.prepAutoCarryover else { return }
        guard !meeting.prepCarryoverDone else { return }

        let unchecked = extractUncheckedItems(from: meeting.prepNotes)
        guard !unchecked.isEmpty else {
            meeting.prepCarryoverDone = true
            try? context.save()
            return
        }

        let block = "<!-- reporté de la réunion \(formatCarryDate(meeting.date)) -->\n"
            + unchecked.joined(separator: "\n")
            + "\n\n"

        switch meeting.kind {
        case .oneToOne, .manager:
            if let collab = meeting.participants.first {
                collab.standingPrepNotes = block + collab.standingPrepNotes
                collab.standingPrepUpdatedAt = Date()
            }
        case .project:
            if let project = meeting.project {
                project.standingPrepNotes = block + project.standingPrepNotes
                project.standingPrepUpdatedAt = Date()
            }
        case .global, .work, .note:
            break  // pool absent — items perdus (cf. spec, intentionnel)
        }

        meeting.prepCarryoverDone = true
        try? context.save()
        prepLog.info("carryover done count=\(unchecked.count) kind=\(meeting.kind.rawValue, privacy: .public)")
    }

    private static func formatCarryDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}
