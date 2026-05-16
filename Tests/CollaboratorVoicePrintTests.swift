import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class CollaboratorVoicePrintTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_defaults() {
        let c = Collaborator(name: "X")
        XCTAssertNil(c.voicePrint)
        XCTAssertEqual(c.voicePrintSamples, 0)
        XCTAssertNil(c.voicePrintUpdatedAt)
    }

    func test_dataRoundtrip() {
        let c = Collaborator(name: "X")
        let bytes: [Float] = Array(repeating: 0.5, count: 256)
        c.voicePrint = bytes.withUnsafeBufferPointer { Data(buffer: $0) }
        c.voicePrintSamples = 3
        c.voicePrintUpdatedAt = Date(timeIntervalSince1970: 1)

        XCTAssertEqual(c.voicePrint?.count, 256 * 4)
        XCTAssertEqual(c.voicePrintSamples, 3)
        XCTAssertEqual(c.voicePrintUpdatedAt, Date(timeIntervalSince1970: 1))
    }
}
