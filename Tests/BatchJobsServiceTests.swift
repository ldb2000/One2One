import XCTest
import SwiftData
@testable import OneToOne

final class BatchJobsServiceTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_meetingsWithoutReport_excludesEmptyTranscripts() throws {
        let ctx = try makeContext()
        let m1 = Meeting(title: "transcribed-no-report", date: Date())
        m1.rawTranscript = "some transcription"
        m1.summary = ""
        ctx.insert(m1)
        let m2 = Meeting(title: "no-transcript", date: Date())
        m2.rawTranscript = ""
        m2.summary = ""
        ctx.insert(m2)
        let m3 = Meeting(title: "has-report", date: Date())
        m3.rawTranscript = "x"
        m3.summary = "résumé"
        ctx.insert(m3)
        try ctx.save()

        let candidates = BatchJobsService.meetingsWithoutReport(in: ctx)
        XCTAssertEqual(candidates.map(\.title), ["transcribed-no-report"])
    }

    @MainActor
    func test_meetingsWithoutTranscript_requiresPlayableAudio() throws {
        let ctx = try makeContext()
        let m1 = Meeting(title: "no-transcript-no-audio", date: Date())
        ctx.insert(m1)
        let m2 = Meeting(title: "no-transcript-with-audio", date: Date())
        m2.wavFilePath = Bundle.main.executablePath ?? "/bin/sh"
        ctx.insert(m2)
        try ctx.save()

        let candidates = BatchJobsService.meetingsWithoutTranscript(in: ctx)
        XCTAssertEqual(candidates.map(\.title), ["no-transcript-with-audio"])
    }
}
