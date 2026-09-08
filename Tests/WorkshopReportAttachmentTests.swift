import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// `Joindre au rapport` de l'encart de clôture de 6b (spec §7.3, §8 : le
/// rapport gagne un bloc optionnel « planches d'atelier »).
@Suite("Atelier — Joindre au rapport")
@MainActor
struct WorkshopReportAttachmentTests {

    private func contexte() throws -> ModelContext {
        let conteneur = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(conteneur)
    }

    @Test("Tout est coché, et le second appel ne change rien")
    func attachAllIsIdempotent() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)

        for index in 0..<3 {
            let planche = Board(index: index, title: "P\(index)", mode: .sketch, t: Double(index))
            context.insert(planche)
            planche.meeting = reunion
        }
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: Date(), imagePath: "/tmp/c.png")
        context.insert(capture)
        capture.attachment = lot

        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion) == false)
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 4)
        let toutesCochees = reunion.boards.allSatisfy { $0.includeInReport }
        #expect(toutesCochees)
        #expect(capture.includeInReport)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion))
        // Idempotent : rien de plus à changer.
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 0)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion))
    }

    @Test("Une seule case déjà cochée ne fait pas passer la séance pour jointe")
    func onePreCheckedRowIsNotEnough() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier partiel", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)

        let premiere = Board(index: 0, title: "P0", mode: .sketch, t: 0)
        premiere.includeInReport = true
        context.insert(premiere)
        premiere.meeting = reunion
        let seconde = Board(index: 1, title: "P1", mode: .ink, t: 10)
        context.insert(seconde)
        seconde.meeting = reunion

        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion) == false)
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 1)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion))
    }

    @Test("Un atelier sans rien à joindre n'est pas « joint »")
    func emptyWorkshopIsNotAttached() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Vide", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion) == false)
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 0)
    }

    @Test("Les libellés du bouton disent l'état, jamais l'action déjà faite")
    func labelsSayTheState() {
        #expect(WorkshopReportAttachment.attachLabel == "Joindre au rapport")
        #expect(WorkshopReportAttachment.attachedLabel.contains("Joint au rapport"))
    }
}
