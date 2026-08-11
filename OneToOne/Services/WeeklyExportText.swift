import Foundation

/// Construit la matière que l'export hebdomadaire soumet à l'IA.
///
/// Bâtie autrefois sur `Interview`, supprimé le 2026-08-11 : ses sept lignes
/// étaient vides, donc l'export produisait sept en-têtes sans corps. La
/// matière vit dans les réunions.
enum WeeklyExportText {

    /// Une section par réunion tenue, dans l'ordre chronologique : date,
    /// participants, type, corps, puis les actions cochées selon leur état.
    ///
    /// Les notes sont écartées (`MeetingStatsScope.held`) : une réunion avec
    /// soi-même ne représente aucun temps passé.
    static func build(meetings: [Meeting]) -> String {
        var text = ""
        for meeting in MeetingStatsScope.held(meetings).sorted(by: { $0.date < $1.date }) {
            let date = meeting.date.formatted(date: .long, time: .omitted)
            let people = meeting.participants.map(\.name).joined(separator: ", ")
            let who = people.isEmpty ? (meeting.title.isEmpty ? "Sans titre" : meeting.title) : people
            text += "### \(date) — \(who) (\(meeting.kind.label))\n"
            if !meeting.title.isEmpty && !people.isEmpty {
                text += "\(meeting.title)\n"
            }

            // Le corps d'une réunion peut vivre dans trois champs selon
            // l'écran qui l'a rempli ; on les donne tous, sans doublon.
            for body in [meeting.summary, meeting.notes, meeting.liveNotes]
            where !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text += body + "\n"
            }
            text += "\n"

            if !meeting.tasks.isEmpty {
                text += "Actions:\n"
                for task in meeting.tasks {
                    let check = task.isCompleted ? "[x]" : "[ ]"
                    text += "- \(check) \(task.title)"
                    if let project = task.project { text += " (Projet: \(project.name))" }
                    text += "\n"
                }
                text += "\n"
            }
        }
        return text
    }
}
