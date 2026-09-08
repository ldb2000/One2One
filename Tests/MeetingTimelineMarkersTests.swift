import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les repères de la frise audio (spec §2.4) : « marqueurs ronds (note),
/// carrés (capture, chantier 4), losanges (décision) ».
///
/// Construits hors de la vue : une capture non horodatée (faite hors
/// enregistrement, `SlideCapture.t == nil`) doit être **ignorée** et non
/// dessinée à zéro — un repère à `00:00` désigne un instant où rien ne s'est
/// passé.
@Suite("Marqueurs de la frise audio")
@MainActor
struct MeetingTimelineMarkersTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func meeting(in context: ModelContext) -> Meeting {
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        context.insert(reunion)
        return reunion
    }

    private func addNote(_ t: Double, _ kind: MeetingNoteKind,
                         to reunion: Meeting, in context: ModelContext) {
        let note = MeetingNote(t: t, text: "ligne", kind: kind)
        context.insert(note)
        note.meeting = reunion
    }

    @Test("Chaque nature de note a sa forme")
    func naturesDeNotes() throws {
        let context = try makeContext()
        let reunion = meeting(in: context)
        addNote(252, .note, to: reunion, in: context)
        addNote(663, .decision, to: reunion, in: context)
        addNote(920, .risk, to: reunion, in: context)

        let repères = MeetingTimelineMarkers.markers(for: reunion)
        #expect(repères.count == 3)
        #expect(repères.map(\.t) == [252, 663, 920])
        #expect(repères.map(\.kind) == [.note, .decision, .risk])
    }

    @Test("Les repères sont triés par timecode, quel que soit l'ordre de la relation")
    func tri() throws {
        let context = try makeContext()
        let reunion = meeting(in: context)
        addNote(920, .note, to: reunion, in: context)
        addNote(252, .note, to: reunion, in: context)
        addNote(663, .decision, to: reunion, in: context)

        #expect(MeetingTimelineMarkers.markers(for: reunion).map(\.t) == [252, 663, 920])
    }

    @Test("Une capture horodatée devient un carré ; sans timecode, elle est ignorée")
    func captures() throws {
        let context = try makeContext()
        let reunion = meeting(in: context)
        let pièce = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"), kind: "slides")
        context.insert(pièce)
        pièce.meeting = reunion

        let horodatee = SlideCapture(index: 0, capturedAt: Date(), imagePath: "/tmp/1.png")
        horodatee.t = 480
        context.insert(horodatee)
        horodatee.attachment = pièce

        let sansT = SlideCapture(index: 1, capturedAt: Date(), imagePath: "/tmp/2.png")
        context.insert(sansT)
        sansT.attachment = pièce

        let repères = MeetingTimelineMarkers.markers(for: reunion)
        #expect(repères.count == 1)
        #expect(repères.first?.kind == .capture)
        #expect(repères.first?.t == 480)
    }

    @Test("Les feedbacks, promesses et preuves comptent comme des notes")
    func naturesDu1a1() {
        #expect(MeetingTimelineMarkers.kind(for: .feedback) == .note)
        #expect(MeetingTimelineMarkers.kind(for: .promise) == .note)
        #expect(MeetingTimelineMarkers.kind(for: .request) == .note)
        #expect(MeetingTimelineMarkers.kind(for: .proof) == .note)
        #expect(MeetingTimelineMarkers.kind(for: .decision) == .decision)
        #expect(MeetingTimelineMarkers.kind(for: .risk) == .risk)
        #expect(MeetingTimelineMarkers.kind(for: .note) == .note)
    }

    @Test("Une réunion sans note ni capture n'a aucun repère")
    func aucunRepere() throws {
        let context = try makeContext()
        #expect(MeetingTimelineMarkers.markers(for: meeting(in: context)).isEmpty)
    }

    @Test("Le libellé du repère porte le début du texte de la note")
    func libelle() throws {
        let context = try makeContext()
        let reunion = meeting(in: context)
        let note = MeetingNote(t: 663, text: "le partenaire finalise la migration",
                               kind: .decision)
        context.insert(note)
        note.meeting = reunion

        // Le libellé sert l'infobulle de la frise et les étiquettes du poste de
        // pilotage (spec §2.7) : il ne doit pas être vide.
        #expect(MeetingTimelineMarkers.markers(for: reunion).first?.label
                == "le partenaire finalise la migration")
    }
}
