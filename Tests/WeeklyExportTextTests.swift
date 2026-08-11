import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le texte que l'export hebdomadaire soumet à l'IA était bâti sur `Interview`
/// — sept coquilles vides dans le store réel, donc sept en-têtes sans corps.
/// Il est repointé sur les réunions, qui portent la matière. La construction
/// sort de l'appel réseau pour devenir une fonction pure, vérifiable.
@Suite("WeeklyExportText — la matière de l'export hebdomadaire")
struct WeeklyExportTextTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    @Test("Une réunion apporte sa date, ses participants, son type et son corps")
    func meetingContributesItsSubstance() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice Martin")
        context.insert(alice)
        let meeting = Meeting(title: "Point budget", date: Date(), notes: "Charge et mobilité")
        meeting.kind = .oneToOne
        meeting.participants = [alice]
        context.insert(meeting)

        let text = WeeklyExportText.build(meetings: [meeting])

        #expect(text.contains("Alice Martin"))
        #expect(text.contains("Charge et mobilité"))
        #expect(text.contains(meeting.kind.label))
    }

    @Test("Les actions de la réunion sont listées, cochées selon leur état")
    func tasksAreListedWithTheirState() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.kind = .oneToOne
        context.insert(meeting)
        let done = ActionTask(title: "Relancer la DSI")
        done.isCompleted = true
        done.meeting = meeting
        let open = ActionTask(title: "Cadrer le budget")
        open.meeting = meeting
        context.insert(done); context.insert(open)

        let text = WeeklyExportText.build(meetings: [meeting])

        #expect(text.contains("[x] Relancer la DSI"))
        #expect(text.contains("[ ] Cadrer le budget"))
    }

    /// Une note est une réunion avec soi-même : elle ne représente aucun temps
    /// passé et n'a pas sa place dans un export d'activité hebdomadaire.
    @Test("Les notes sont écartées de l'export")
    func notesAreLeftOut() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Pense-bête du mardi", title: "Pense-bête")
        context.insert(note)

        let text = WeeklyExportText.build(meetings: [note])

        #expect(!text.contains("Pense-bête"))
    }

    @Test("Les réunions sortent dans l'ordre chronologique")
    func meetingsComeOutInOrder() throws {
        let context = try makeContext()
        let old = Meeting(title: "La plus ancienne", date: Date(timeIntervalSince1970: 1_000_000))
        old.kind = .oneToOne
        let recent = Meeting(title: "La plus récente", date: Date(timeIntervalSince1970: 2_000_000))
        recent.kind = .oneToOne
        context.insert(old); context.insert(recent)

        let text = WeeklyExportText.build(meetings: [recent, old])

        let posOld = text.range(of: "La plus ancienne")?.lowerBound
        let posRecent = text.range(of: "La plus récente")?.lowerBound
        #expect(posOld != nil && posRecent != nil)
        #expect(posOld! < posRecent!)
    }
}
