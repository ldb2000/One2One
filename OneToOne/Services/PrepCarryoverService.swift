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
