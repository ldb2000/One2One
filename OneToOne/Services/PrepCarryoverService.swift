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
    static func drainStandingIntoMeeting(_ meeting: Meeting, in context: ModelContext) {
        guard !meeting.prepDrainDone else { return }

        switch meeting.kind {
        case .oneToOne, .manager:
            if let collab = meeting.participants.first, !collab.standingPrepNotes.isEmpty {
                meeting.prepNotes = mergePrep(
                    standing: collab.standingPrepNotes,
                    existing: meeting.prepNotes
                )
                collab.standingPrepNotes = ""
                collab.standingPrepUpdatedAt = Date()
            }
        case .project:
            if let project = meeting.project, !project.standingPrepNotes.isEmpty {
                meeting.prepNotes = mergePrep(
                    standing: project.standingPrepNotes,
                    existing: meeting.prepNotes
                )
                project.standingPrepNotes = ""
                project.standingPrepUpdatedAt = Date()
            }
        case .global, .work:
            break
        }

        meeting.prepDrainDone = true
        try? context.save()
        prepLog.info("drain done kind=\(meeting.kind.rawValue, privacy: .public) bytes=\(meeting.prepNotes.count)")
    }

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
        case .global, .work:
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
