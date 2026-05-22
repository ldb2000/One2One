import Foundation
import SwiftData

/// Énumère les meetings éligibles aux batch jobs.
@MainActor
enum BatchJobsService {

    static func meetingsWithoutReport(in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            !$0.rawTranscript.isEmpty && $0.summary.isEmpty
        }
    }

    static func meetingsWithoutTranscript(in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            $0.rawTranscript.isEmpty && $0.hasPlayableAudio
        }
    }

    static func meetingsWithoutDiarisation(in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { m in
            !m.transcriptSegments.isEmpty
                && m.hasPlayableAudio
                && (m.speakerAssignmentsJSON.isEmpty || m.speakerAssignmentsJSON == "{}")
        }
    }
}
