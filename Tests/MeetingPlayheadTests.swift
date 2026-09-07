import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La tête de lecture est l'axe temps partagé d'une réunion : notes, captures,
/// frise et transcription doivent tous parler du même `t`. Ces tests sont purs
/// — horloge injectée, aucun fichier audio chargé.
@Suite("Tête de lecture — l'axe temps d'une réunion")
@MainActor
struct MeetingPlayheadTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("En enregistrement, t vaut l'écart à l'instant de démarrage")
    func tEnEnregistrement() {
        var maintenant = Date(timeIntervalSince1970: 1_000)
        let playhead = MeetingPlayhead(meetingStableID: UUID(), now: { maintenant })

        playhead.beginRecording(startedAt: Date(timeIntervalSince1970: 1_000))
        #expect(playhead.t == 0)

        maintenant = Date(timeIntervalSince1970: 1_252)
        playhead.refresh()
        #expect(playhead.t == 252)
        // La durée suit l'enregistrement : elle ne peut pas rester à zéro
        // pendant qu'on enregistre, sinon un seek borné à `duration` serait
        // toujours ramené à 0.
        #expect(playhead.duration == 252)
    }

    @Test("Une horloge qui recule ne rend jamais un t négatif")
    func tJamaisNegatif() {
        var maintenant = Date(timeIntervalSince1970: 2_000)
        let playhead = MeetingPlayhead(meetingStableID: UUID(), now: { maintenant })
        playhead.beginRecording(startedAt: Date(timeIntervalSince1970: 2_000))

        maintenant = Date(timeIntervalSince1970: 1_990)
        playhead.refresh()
        #expect(playhead.t == 0)
    }

    @Test("seek borne la position entre 0 et la durée")
    func seekBorne() {
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        playhead.duration = 600

        playhead.seek(to: 42)
        #expect(playhead.t == 42)

        playhead.seek(to: -10)
        #expect(playhead.t == 0)

        playhead.seek(to: 10_000)
        #expect(playhead.t == 600)
    }

    @Test("Sans durée connue, seek ramène à zéro plutôt que d'inventer une position")
    func seekSansDuree() {
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        #expect(playhead.duration == 0)
        playhead.seek(to: 30)
        #expect(playhead.t == 0)
    }

    @Test("Le suivi automatique est actif par défaut et se bascule")
    func suiviAutomatique() {
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        #expect(playhead.follow)
        playhead.follow = false
        #expect(!playhead.follow)
    }

    @Test("Le temps s'affiche en mm:ss, et en h:mm:ss au-delà de l'heure")
    func formatage() {
        #expect(MeetingPlayhead.mmss(0) == "00:00")
        #expect(MeetingPlayhead.mmss(252) == "04:12")
        #expect(MeetingPlayhead.mmss(59.6) == "01:00")
        #expect(MeetingPlayhead.mmss(-5) == "00:00")
        #expect(MeetingPlayhead.mmss(3_900) == "1:05:00")

        let playhead = MeetingPlayhead(meetingStableID: UUID())
        playhead.duration = 600
        playhead.seek(to: 252)
        #expect(playhead.formatted == "04:12")
    }

    @Test("Les marqueurs se rangent par timecode croissant")
    func marqueursTries() {
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        playhead.markers = [
            .init(t: 300, kind: .capture),
            .init(t: 12, kind: .note),
            .init(t: 252, kind: .decision)
        ]
        #expect(playhead.markers.map(\.t) == [12, 252, 300])
        #expect(playhead.marker(at: 252)?.kind == .decision)
        #expect(playhead.marker(at: 253, tolerance: 2)?.kind == .decision)
        #expect(playhead.marker(at: 260, tolerance: 2) == nil)
    }

    @Test("Une réunion en enregistrement recale l'axe sur son instant de démarrage")
    func rattachementSurEnregistrement() throws {
        // Remplace les deux tests du registre statique, retiré au lot 1 : la
        // tête de lecture appartient désormais à `MeetingScreenModel`, qui la
        // cale sur la réunion par `attachPlayhead(meeting:)`. Le partage entre
        // surfaces est vérifié par `MeetingScreenModelTests`.
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL")
        context.insert(reunion)
        try context.save()

        let ecran = MeetingScreenModel(defaults: UserDefaults(suiteName: "MeetingPlayheadTests.\(UUID().uuidString)")!)
        ecran.attach(meetingID: reunion.ensuredStableID)
        #expect(ecran.playhead.meetingStableID == reunion.ensuredStableID)

        // Sans enregistrement en cours, l'axe reste à l'arrêt : rien ne doit
        // faire courir `t` d'une réunion close.
        reunion.recordingStartedAt = Date(timeIntervalSince1970: 1_000)
        ecran.attachPlayhead(meeting: reunion)
        #expect(ecran.playhead.source == .idle)
    }

    @Test("Un marqueur ajouté par la tête de lecture est trié et retrouvable")
    func ajoutDeMarqueur() {
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        playhead.addMarker(at: 252, kind: .decision, label: "Décision")
        playhead.addMarker(at: 12, kind: .note)
        #expect(playhead.markers.map(\.t) == [12, 252])
        #expect(playhead.marker(at: 252)?.label == "Décision")
    }
}
