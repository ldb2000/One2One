import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le semis de démonstration du lot 7 : les trois captures de
/// `4a-capture-selecteur.png`.
@Suite("RefonteDemoSeed — lot 7", .serialized)
@MainActor
struct RefonteDemoSeedLot7Tests {

    private let container: ModelContainer
    private let base: URL

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seed-lot7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private var context: ModelContext { container.mainContext }

    private func captures(of meeting: Meeting) -> [SlideCapture] {
        CaptureStripModel.sorted(meeting.attachments.flatMap(\.slides))
    }

    @Test("trois captures, aux timecodes et aux déclencheurs de la capture 4a")
    func threeCapturesMatchScreenshot() {
        let reunion = RefonteDemoSeed.seedLot7(in: context, base: base)
        let captures = captures(of: reunion)
        #expect(captures.count == 3)
        #expect(captures.map(\.t) == [252, 535, 728])
        #expect(captures.map(\.trigger) == [.shareChange, .shareChange, .manual])
        #expect(captures.allSatisfy { $0.source == .teams })
        #expect(CaptureStripModel.legend(for: captures[0], interval: nil) == "04:12 · auto")
        #expect(CaptureStripModel.legend(for: captures[2], interval: nil) == "12:08 · ⌘⇧S")
    }

    @Test("les PNG existent réellement : la bande a de quoi afficher")
    func pngFilesExist() {
        let reunion = RefonteDemoSeed.seedLot7(in: context, base: base)
        for capture in captures(of: reunion) {
            #expect(FileManager.default.fileExists(atPath: capture.imagePath),
                    "PNG manquant : \(capture.imagePath)")
            #expect(CaptureThumbnailCache.makeThumbnail(path: capture.imagePath) != nil)
        }
    }

    @Test("l'OCR de la capture 4a est présent et cherchable dans le texte du lot")
    func ocrIsSeededAndIndexed() {
        let reunion = RefonteDemoSeed.seedLot7(in: context, base: base)
        let chiffrage = try? #require(captures(of: reunion).last)
        #expect(chiffrage?.ocrText.contains("Reprise AP : 3 j-h · Marine : 21 000 €") == true)

        let lot = try? #require(reunion.attachments.first {
            $0.kind == AttachmentCopyPolicy.slidesKind
        })
        #expect(lot?.extractedText.contains("21 000") == true)
        #expect(TextChunker.chunk(lot?.extractedText ?? "").isEmpty == false)
    }

    @Test("chaque capture semée porte un marqueur sur la frise")
    func seededCapturesAppearOnTheTimeline() {
        let reunion = RefonteDemoSeed.seedLot7(in: context, base: base)
        let carres = MeetingTimelineMarkers.allMarkers(for: reunion).filter { $0.kind == .capture }
        #expect(carres.map(\.t) == [252, 535, 728])
        #expect(MeetingTimelineMarkers.lastCaptureT(carres) == 728)
    }

    @Test("le semis est idempotent : deux clics ne dupliquent rien")
    func seedIsIdempotent() {
        _ = RefonteDemoSeed.seedLot7(in: context, base: base)
        let reunion = RefonteDemoSeed.seedLot7(in: context, base: base)
        #expect(captures(of: reunion).count == 3)
        #expect(reunion.attachments.filter { $0.kind == AttachmentCopyPolicy.slidesKind }.count == 1)
    }
}
