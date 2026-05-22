import XCTest
import SwiftData
@testable import OneToOne

final class OrphanCleanupServiceTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_listsAttachmentsWithMissingFiles() throws {
        let ctx = try makeContext()
        let existing = URL(fileURLWithPath: Bundle.main.executablePath ?? "/bin/sh")
        let a1 = MeetingAttachment(url: existing, kind: "document")
        ctx.insert(a1)
        let missingURL = URL(fileURLWithPath: "/tmp/onetoone-missing-\(UUID().uuidString)")
        let a2 = MeetingAttachment(url: missingURL, kind: "document")
        ctx.insert(a2)
        try ctx.save()

        let orphans = OrphanCleanupService.orphanAttachments(in: ctx)
        XCTAssertEqual(orphans.map(\.filePath), [missingURL.path])
    }
}
