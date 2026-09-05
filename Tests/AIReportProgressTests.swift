import Foundation
import Testing
@testable import OneToOne

@Suite("Progression et publication anticipée des rapports")
struct AIReportProgressTests {
    @Test("Le raisonnement signale une activité sans polluer le rapport", arguments: ["reasoning", "reasoning_content"])
    func reasoning(field: String) throws {
        var parser = AICompletionStream()
        let stream = "data: {\"choices\":[{\"delta\":{\"\(field)\":\"privé\"}}]}\n\n"
        for byte in stream.utf8 { _ = try parser.consume(byte: byte) }
        #expect(parser.activity == .reasoning(5))
        #expect(parser.text.isEmpty)
        let final = "data: {\"choices\":[{\"delta\":{\"content\":\"Rapport\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        for byte in final.utf8 { _ = try parser.consume(byte: byte) }
        #expect(parser.activity == .writing(7))
        #expect(try parser.result() == "Rapport")
    }

    @Test("Alerte après deux minutes, distingue silence et activité")
    func prolongedWait() {
        let start = Date(timeIntervalSince1970: 1000)
        var progress = AIReportProgress()
        progress.start(.waiting, at: start)
        #expect(progress.warning(at: start.addingTimeInterval(119)) == nil)
        #expect(progress.warning(at: start.addingTimeInterval(120))?.contains("Aucune nouvelle activité") == true)
        progress.receive(.reasoning(10), at: start.addingTimeInterval(120))
        #expect(progress.warning(at: start.addingTimeInterval(121)) == nil)
        progress.receive(.reasoning(500), at: start.addingTimeInterval(245))
        #expect(progress.warning(at: start.addingTimeInterval(246))?.contains("toujours actif") == true)
        #expect(progress.label.contains("500"))
        progress.start(.extracting, at: start)
        progress.receive(.writing(20), at: start.addingTimeInterval(125))
        #expect(progress.phase == .extracting)
        #expect(progress.warning(at: start.addingTimeInterval(126))?.contains("sauvegardé") == true)
    }

    @MainActor
    @Test("Le markdown est publié avant de commencer l’extraction")
    func publishBeforeExtraction() async throws {
        var saved = ""
        let result = try await AIReportService.completeReport(markdown: "# Rapport", onMarkdownReady: { saved = $0 }) {
            #expect(saved == "# Rapport")
            return .empty
        }
        #expect(result.summary == saved)
    }

    @MainActor
    @Test("L’annulation de l’extraction conserve le markdown publié")
    func cancellationPreservesDraft() async {
        var saved = ""
        await #expect(throws: CancellationError.self) {
            try await AIReportService.completeReport(markdown: "Rapport terminé", onMarkdownReady: { saved = $0 }) {
                throw CancellationError()
            }
        }
        #expect(saved == "Rapport terminé")
    }

    @MainActor
    @Test("Une sauvegarde échouée ne lance pas la seconde passe")
    func failedPublication() async {
        enum SaveError: Error { case failed }
        var extracted = false
        await #expect(throws: SaveError.self) {
            try await AIReportService.completeReport(markdown: "Rapport", onMarkdownReady: { _ in throw SaveError.failed }) {
                extracted = true
                return .empty
            }
        }
        #expect(!extracted)
    }
}
