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

    @Test("Le registre rend une seule tête de lecture par réunion")
    func registreParReunion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL")
        context.insert(reunion)
        let autre = Meeting(title: "Atelier")
        context.insert(autre)
        try context.save()

        let premier = MeetingPlayhead.for(meeting: reunion)
        let second = MeetingPlayhead.for(meeting: reunion)
        #expect(premier === second)
        #expect(premier.player === second.player)
        #expect(MeetingPlayhead.for(meeting: autre) !== premier)
    }

    @Test("Le registre est borné : la plus ancienne tête de lecture est évincée")
    func registreBorne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var reunions: [Meeting] = []
        for i in 0..<(MeetingPlayhead.registryCapacity + 1) {
            let m = Meeting(title: "Réunion \(i)")
            context.insert(m)
            reunions.append(m)
        }
        try context.save()

        let premiere = MeetingPlayhead.for(meeting: reunions[0])
        for reunion in reunions.dropFirst() {
            _ = MeetingPlayhead.for(meeting: reunion)
        }
        // La première a quitté le cache : on en obtient une instance neuve.
        #expect(MeetingPlayhead.for(meeting: reunions[0]) !== premiere)
        #expect(MeetingPlayhead.registryCount <= MeetingPlayhead.registryCapacity)
    }
}
