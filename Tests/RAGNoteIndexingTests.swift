import XCTest
import SwiftData
@testable import OneToOne

/// `NoteIndexingCoordinator.reindexHandler` remplace le pipeline MLX réel par
/// un double contrôlable : `swift test` n'embarque pas `default.metallib`
/// (cf. CLAUDE.md), donc appeler `RAGIndexer.reindexNote` pour de vrai
/// crasherait au premier accès GPU. Le double laisse tester uniquement le
/// débounce / l'annulation, indépendamment de l'embedding.
@MainActor
final class RAGNoteIndexingTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    private var originalDelay: TimeInterval = 2.0

    override func setUpWithError() throws {
        originalDelay = NoteIndexingCoordinator.shared.debounceDelay
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    override func tearDown() {
        // Le coordinateur est un singleton partagé entre tests : on restaure
        // son état par défaut pour ne pas polluer d'autres suites.
        NoteIndexingCoordinator.shared.debounceDelay = originalDelay
        NoteIndexingCoordinator.shared.reindexHandler = { meeting, context in
            try await RAGIndexer.reindexNote(meeting: meeting, context: context)
        }
        super.tearDown()
    }

    private func makeNote(content: String) -> Meeting {
        let meeting = Meeting(title: "Note de test", date: Date())
        meeting.kind = .note
        meeting.liveNotes = content
        context.insert(meeting)
        try? context.save()
        return meeting
    }

    /// 3 `scheduleReindex` rapprochés pour la même note ne déclenchent qu'UN
    /// seul reindex, une fois le débounce écoulé.
    func test_scheduleReindex_debounceMultipleCallsIntoOne() async throws {
        let note = makeNote(content: String(repeating: "a", count: 2_048))

        let recorder = CallRecorder()
        NoteIndexingCoordinator.shared.debounceDelay = 2.0
        NoteIndexingCoordinator.shared.reindexHandler = { _, _ in
            await recorder.recordCall()
        }

        let coordinator = NoteIndexingCoordinator.shared
        coordinator.scheduleReindex(meeting: note, context: context)
        coordinator.scheduleReindex(meeting: note, context: context)
        coordinator.scheduleReindex(meeting: note, context: context)

        try await Task.sleep(nanoseconds: 2_500_000_000)

        let count = await recorder.callCount
        XCTAssertEqual(count, 1, "les 3 appels rapprochés doivent fusionner en un seul reindex")
    }

    /// Un `scheduleReindex` déclenché pendant qu'un reindex est déjà en vol
    /// pour la même note annule proprement ce reindex en cours, plutôt que
    /// de laisser les deux tourner en parallèle.
    func test_scheduleReindex_cancelsInFlightReindex() async throws {
        let note = makeNote(content: String(repeating: "b", count: 2_048))

        let recorder = CallRecorder()
        NoteIndexingCoordinator.shared.debounceDelay = 0.1
        NoteIndexingCoordinator.shared.reindexHandler = { _, _ in
            let id = await recorder.nextID()
            await recorder.markStarted(id)
            do {
                // `Task.sleep` lève `CancellationError` si la tâche est
                // annulée pendant l'attente — simule un reindex long.
                try await Task.sleep(nanoseconds: 500_000_000)
                await recorder.markCompleted(id)
            } catch {
                await recorder.markCancelled(id)
                throw error
            }
        }

        let coordinator = NoteIndexingCoordinator.shared
        coordinator.scheduleReindex(meeting: note, context: context)
        // Laisse le débounce (0.1 s) s'écouler et le 1er reindex démarrer,
        // puis le laisse s'installer dans son sleep de 0.5 s.
        try await Task.sleep(nanoseconds: 250_000_000)

        // Nouvelle édition pendant que le reindex #1 est en vol : programme
        // un nouveau débounce, qui annulera #1 avant de démarrer #2.
        coordinator.scheduleReindex(meeting: note, context: context)

        try await Task.sleep(nanoseconds: 900_000_000)

        let started = await recorder.startedIDs
        let cancelled = await recorder.cancelledIDs
        let completed = await recorder.completedIDs

        XCTAssertEqual(started.count, 2, "les deux reindex doivent avoir démarré")
        XCTAssertEqual(cancelled, [1], "le premier reindex doit avoir été annulé")
        XCTAssertEqual(completed, [2], "seul le second reindex doit aller à son terme")
    }
}

/// Petit enregistreur d'appels isolé sur le MainActor (comme
/// `NoteIndexingCoordinator`), pour éviter tout état partagé non protégé
/// entre les closures de test et les assertions.
@MainActor
private final class CallRecorder {
    private(set) var callCount = 0
    private var counter = 0
    private(set) var startedIDs: [Int] = []
    private(set) var cancelledIDs: [Int] = []
    private(set) var completedIDs: [Int] = []

    func recordCall() {
        callCount += 1
    }

    func nextID() -> Int {
        counter += 1
        return counter
    }

    func markStarted(_ id: Int) { startedIDs.append(id) }
    func markCancelled(_ id: Int) { cancelledIDs.append(id) }
    func markCompleted(_ id: Int) { completedIDs.append(id) }
}
