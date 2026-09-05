import XCTest
import SwiftData
@testable import OneToOne

/// `RAGIndexingSweep.reindex*Handler` remplacent le pipeline MLX réel par des
/// doubles contrôlables : `swift test` n'embarque pas `default.metallib`
/// (cf. CLAUDE.md), donc appeler `RAGIndexer.reindex`/`MeetingAttachmentService
/// .reindexAttachment`/`ProjectMailStore.reindex` pour de vrai crasherait au
/// premier accès GPU. Les doubles simulent l'effet observable qui compte pour
/// ce sweep : remettre `embeddingData`/`embeddingModel` à jour.
@MainActor
final class RAGIndexingSweepTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)

        // Store UserDefaults dédié et vierge par test, pour ne jamais lire/
        // écrire les préférences réelles ni laisser un test polluer le suivant.
        let suite = UserDefaults(suiteName: "RAGIndexingSweepTests")!
        suite.removePersistentDomain(forName: "RAGIndexingSweepTests")
        RAGIndexingSweep.userDefaults = suite
    }

    override func tearDown() {
        // Le sweep partage des handlers `static var` entre tests : on les
        // restaure pour ne pas polluer d'autres suites (même pattern que
        // `RAGNoteIndexingTests` pour `NoteIndexingCoordinator.reindexHandler`).
        RAGIndexingSweep.reindexMeetingHandler = { meeting, context in
            if meeting.kind == .note {
                try await RAGIndexer.reindexNote(meeting: meeting, context: context)
            } else {
                try await RAGIndexer.reindex(meeting: meeting, context: context)
            }
        }
        RAGIndexingSweep.reindexAttachmentHandler = { attachment, context in
            try await MeetingAttachmentService.reindexAttachment(attachment, context: context)
        }
        RAGIndexingSweep.reindexMailHandler = { mail, context in
            try await ProjectMailStore.reindex(mail: mail, context: context)
        }
        RAGIndexingSweep.userDefaults = .standard
        super.tearDown()
    }

    private func makeMeeting(kind: MeetingKind = .project) -> Meeting {
        let meeting = Meeting(title: "Réunion de test", date: Date())
        meeting.kind = kind
        context.insert(meeting)
        return meeting
    }

    /// Double qui simule un reindex réussi en remettant le chunk du meeting à
    /// jour (modèle courant + vecteur factice), sans jamais appeler MLX.
    private func fakeMeetingReindex(callCount: CallCounter) -> (Meeting, ModelContext) async throws -> Void {
        { meeting, context in
            await callCount.increment()
            for chunk in meeting.transcriptChunks {
                chunk.setEmbedding([0.1, 0.2], model: RAGService.embeddingModel)
            }
            try? context.save()
        }
    }

    // MARK: - Chunk avec embedding valide → no-op

    func test_runIfNeeded_chunkAJour_neFaitRien() async throws {
        let meeting = makeMeeting()
        let chunk = TranscriptChunk(text: "à jour", orderIndex: 0, sourceType: "meeting")
        chunk.meeting = meeting
        chunk.setEmbedding([0.1, 0.2], model: RAGService.embeddingModel)
        context.insert(chunk)
        try context.save()

        let callCount = CallCounter()
        RAGIndexingSweep.reindexMeetingHandler = fakeMeetingReindex(callCount: callCount)

        await RAGIndexingSweep.shared.runIfNeeded(context: context)

        let calls = await callCount.value
        XCTAssertEqual(calls, 0, "un chunk déjà indexé avec le modèle courant ne doit déclencher aucun reindex")
    }

    // MARK: - Chunk sans embedding → ré-indexé

    func test_runIfNeeded_chunkSansEmbedding_estReindexe() async throws {
        let meeting = makeMeeting()
        let chunk = TranscriptChunk(text: "jamais indexé", orderIndex: 0, sourceType: "meeting")
        chunk.meeting = meeting
        context.insert(chunk)
        try context.save()
        XCTAssertNil(chunk.embeddingData)

        let callCount = CallCounter()
        RAGIndexingSweep.reindexMeetingHandler = fakeMeetingReindex(callCount: callCount)

        await RAGIndexingSweep.shared.runIfNeeded(context: context)

        let calls = await callCount.value
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(chunk.embeddingData, "le double doit avoir écrit un embedding")
    }

    // MARK: - Modèle d'embedding différent sur le chunk → ré-indexé

    func test_runIfNeeded_modeleChunkObsolete_estReindexe() async throws {
        let meeting = makeMeeting()
        let chunk = TranscriptChunk(text: "ancien modèle", orderIndex: 0, sourceType: "meeting")
        chunk.meeting = meeting
        chunk.setEmbedding([0.3, 0.4], model: "un-autre-modele")
        context.insert(chunk)
        try context.save()

        let callCount = CallCounter()
        RAGIndexingSweep.reindexMeetingHandler = fakeMeetingReindex(callCount: callCount)

        await RAGIndexingSweep.shared.runIfNeeded(context: context)

        let calls = await callCount.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(chunk.embeddingModel, RAGService.embeddingModel)
    }

    // MARK: - Idempotence

    func test_runIfNeeded_secondPassage_neReindexePasANouveau() async throws {
        let meeting = makeMeeting()
        let chunk = TranscriptChunk(text: "jamais indexé", orderIndex: 0, sourceType: "meeting")
        chunk.meeting = meeting
        context.insert(chunk)
        try context.save()

        let callCount = CallCounter()
        RAGIndexingSweep.reindexMeetingHandler = fakeMeetingReindex(callCount: callCount)

        await RAGIndexingSweep.shared.runIfNeeded(context: context)
        let afterFirst = await callCount.value
        XCTAssertEqual(afterFirst, 1)

        // Relance sur le même état : le double a déjà remis le chunk à jour,
        // donc plus rien ne doit être détecté comme obsolète.
        await RAGIndexingSweep.shared.runIfNeeded(context: context)
        let afterSecond = await callCount.value
        XCTAssertEqual(afterSecond, 1, "un second passage sans changement ne doit pas relancer de reindex")
    }

    // MARK: - Regroupement par parent : un seul reindex pour plusieurs chunks du même meeting

    func test_runIfNeeded_regroupeParMeeting_unSeulAppelPourPlusieursChunks() async throws {
        let meeting = makeMeeting()
        for i in 0..<3 {
            let chunk = TranscriptChunk(text: "chunk \(i)", orderIndex: i, sourceType: "meeting")
            chunk.meeting = meeting
            context.insert(chunk)
        }
        try context.save()

        let callCount = CallCounter()
        RAGIndexingSweep.reindexMeetingHandler = fakeMeetingReindex(callCount: callCount)

        await RAGIndexingSweep.shared.runIfNeeded(context: context)

        let calls = await callCount.value
        XCTAssertEqual(calls, 1, "les 3 chunks du même meeting doivent fusionner en un seul reindex")
    }
}

@MainActor
private final class CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
