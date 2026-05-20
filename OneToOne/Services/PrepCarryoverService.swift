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
/// Both operations are idempotent via `meeting.prepCarryoverDone`.
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
    /// `meeting.prepCarryoverDone`.
    /// - For `.global` / `.work`: no pool exists; sets the flag and returns.
    @MainActor
    static func drainStandingIntoMeeting(_ meeting: Meeting, in context: ModelContext) {
        guard !meeting.prepCarryoverDone else { return }

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

        meeting.prepCarryoverDone = true
        try? context.save()
        prepLog.info("drain done kind=\(meeting.kind.rawValue, privacy: .public) bytes=\(meeting.prepNotes.count)")
    }

    private static func mergePrep(standing: String, existing: String) -> String {
        if existing.isEmpty { return standing }
        return standing + "\n\n" + existing
    }
}
