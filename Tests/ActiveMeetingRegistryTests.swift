import Foundation
import SwiftData
import Testing
@testable import OneToOne

/// La règle de priorité de la « réunion active » : celle qui enregistre, sinon la
/// dernière ouverte en séance.
///
/// La règle est testée **nue** (aucun store, aucune vue), la table des poignées avec
/// deux réunions en mémoire.
@Suite("ActiveMeetingRegistry", .serialized)
@MainActor
struct ActiveMeetingRegistryTests {

    private let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private var context: ModelContext { container.mainContext }

    private func session(_ id: UUID, _ secondes: Double) -> ActiveMeetingSession {
        ActiveMeetingSession(meetingStableID: id, enteredAt: Date(timeIntervalSince1970: secondes))
    }

    // MARK: - La règle pure

    @Test("sans réunion ouverte, il n'y a pas de réunion active")
    func nothingOpen() {
        #expect(ActiveMeetingRegistry.activeID(recording: nil, sessions: []) == nil)
        #expect(ActiveMeetingRegistry.activeID(recording: UUID(), sessions: []) == nil)
    }

    @Test("celle qui enregistre l'emporte, même ouverte avant l'autre")
    func recordingWins() {
        let ancienne = UUID()
        let recente = UUID()
        let sessions = [session(ancienne, 100), session(recente, 500)]
        #expect(ActiveMeetingRegistry.activeID(recording: ancienne, sessions: sessions) == ancienne)
    }

    @Test("sans enregistrement, c'est la dernière entrée en séance")
    func latestSession() {
        let ancienne = UUID()
        let recente = UUID()
        // L'ordre de la table est indifférent : c'est `enteredAt` qui décide.
        #expect(ActiveMeetingRegistry.activeID(
            recording: nil, sessions: [session(recente, 500), session(ancienne, 100)]) == recente)
        #expect(ActiveMeetingRegistry.activeID(
            recording: nil, sessions: [session(ancienne, 100), session(recente, 500)]) == recente)
    }

    @Test("un enregistrement sur une réunion sans écran ouvert ne vole pas la séance visible")
    func recordingWithoutHandle() {
        let visible = UUID()
        let ailleurs = UUID()
        #expect(ActiveMeetingRegistry.activeID(
            recording: ailleurs, sessions: [session(visible, 100)]) == visible)
    }

    @Test("à égalité d'instant, la dernière enregistrée gagne")
    func tieBreak() {
        let premiere = UUID()
        let seconde = UUID()
        #expect(ActiveMeetingRegistry.activeID(
            recording: nil, sessions: [session(premiere, 100), session(seconde, 100)]) == seconde)
    }

    // MARK: - La table des poignées

    private func handle(_ titre: String, enteredAt: Double) throws -> ActiveMeetingHandle {
        let meeting = Meeting(title: titre, date: Date())
        meeting.kind = .project
        context.insert(meeting)
        try context.save()
        let suite = UserDefaults(suiteName: "ActiveMeetingRegistryTests-\(UUID().uuidString)")!
        let screen = MeetingScreenModel(defaults: suite)
        screen.attach(meetingID: meeting.ensuredStableID)
        let service = ScreenCaptureService(frameSourceFactory: { _ in ScriptedFrameSource(frames: []) },
                                           ocr: { _ in "" },
                                           reindex: { _, _ in })
        return ActiveMeetingHandle(meeting: meeting,
                                   screen: screen,
                                   context: context,
                                   enteredAt: Date(timeIntervalSince1970: enteredAt)) {
            CaptureSessionCoordinator(meeting: meeting, screen: screen, service: service, context: self.context)
        }
    }

    @Test("s'enregistrer deux fois ne laisse qu'une poignée par réunion")
    func registrationIsIdempotent() throws {
        let registry = ActiveMeetingRegistry(recordingMeetingID: { nil })
        let poignee = try handle("[P25_110] Séance", enteredAt: 100)
        registry.register(poignee)
        registry.register(poignee)
        #expect(registry.handles.count == 1)
        #expect(registry.activeHandle?.meetingStableID == poignee.meetingStableID)
    }

    @Test("se désenregistrer ne retire que sa propre poignée")
    func unregisterOnlyItsOwn() throws {
        let registry = ActiveMeetingRegistry(recordingMeetingID: { nil })
        let a = try handle("A", enteredAt: 100)
        let b = try handle("B", enteredAt: 500)
        registry.register(a)
        registry.register(b)
        registry.unregister(meetingStableID: a.meetingStableID)
        #expect(registry.handles.count == 1)
        #expect(registry.activeHandle?.meetingStableID == b.meetingStableID)
        registry.unregister(meetingStableID: b.meetingStableID)
        #expect(registry.activeHandle == nil)
    }

    @Test("les conditions d'affichage suivent la poignée active")
    func conditionsFollowTheHandle() throws {
        let registry = ActiveMeetingRegistry(recordingMeetingID: { nil })
        #expect(registry.pillConditions.hasActiveMeeting == false)

        let poignee = try handle("[P25_110] Séance", enteredAt: 100)
        registry.register(poignee)
        #expect(registry.pillConditions == SessionPillConditions(hasActiveMeeting: true))

        poignee.screen.session.enter()
        #expect(registry.pillConditions.isSessionFullscreen)
        #expect(registry.pillConditions.isRecording == false)

        registry.recordingMeetingID = { poignee.meetingStableID }
        #expect(registry.pillConditions.isRecording)

        // Clôture de la séance : la poignée reste, les conditions retombent.
        poignee.screen.session.leave()
        registry.recordingMeetingID = { nil }
        #expect(registry.pillConditions == SessionPillConditions(hasActiveMeeting: true))
    }
}
