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

/// Le gel du 2026-09-08 : au démarrage de l'enregistrement, la pastille
/// flottante lisait le chrono par `MeetingPillTarget.elapsed`, qui appelait
/// `MeetingPlayhead.refresh()` — donc **écrivait** `t` et `duration` pendant
/// l'évaluation du corps de vue qui venait de les lire. Chaque rendu
/// invalidait la vue qui le produisait : boucle de rendu, 100 % du thread
/// principal, application figée.
///
/// Ces tests figent les deux moitiés du remède : une lecture d'affichage ne
/// modifie rien, et c'est un **battement** qui fait avancer `t`, à cadence
/// bornée.
@Suite("Tête de lecture — la lecture d'affichage n'écrit pas")
@MainActor
struct MeetingPlayheadReadOnlyTests {

    @Test("Le chrono se lit sans écrire ni t ni duration")
    func lectureSansEcriture() {
        var maintenant = Date(timeIntervalSince1970: 1_000)
        let playhead = MeetingPlayhead(meetingStableID: UUID(), now: { maintenant })
        playhead.beginRecording(startedAt: Date(timeIntervalSince1970: 1_000))
        #expect(playhead.t == 0)

        maintenant = Date(timeIntervalSince1970: 1_042)

        // L'observation est armée comme SwiftUI l'arme autour d'un corps de
        // vue : si la lecture écrit, `onChange` part et la vue se réévalue.
        var invalide = false
        withObservationTracking {
            _ = playhead.t
            _ = playhead.duration
        } onChange: {
            invalide = true
        }

        #expect(playhead.currentTime == 42)
        #expect(playhead.elapsedIfAny == 42)
        #expect(!invalide, "une lecture d'affichage a invalidé l'observation")
        #expect(playhead.t == 0)
        #expect(playhead.duration == 0)
    }

    @Test("Sans axe temps, le timecode d'une note ou d'une capture est absent")
    func pasDAxeTemps() {
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        #expect(playhead.source == .idle)
        #expect(playhead.elapsedIfAny == nil)

        // Une position acquise (seek depuis un timecode de note) reste un axe.
        playhead.duration = 600
        playhead.seek(to: 252)
        #expect(playhead.elapsedIfAny == 252)
    }

    @Test("Un refresh qui ne change rien n'invalide personne")
    func refreshInerte() {
        let maintenant = Date(timeIntervalSince1970: 1_000)
        let playhead = MeetingPlayhead(meetingStableID: UUID(), now: { maintenant })
        playhead.beginRecording(startedAt: Date(timeIntervalSince1970: 900))
        #expect(playhead.t == 100)

        var invalide = false
        withObservationTracking {
            _ = playhead.t
            _ = playhead.duration
        } onChange: {
            invalide = true
        }
        playhead.refresh()
        #expect(!invalide, "refresh a réécrit une valeur inchangée")
    }

    @Test("En enregistrement, un battement fait avancer t sans aucune vue")
    func battementEnEnregistrement() async throws {
        // Horloge partagée avec le battement, qui tourne sur le `MainActor` :
        // ce test l'est aussi, il n'y a donc pas de course.
        var maintenant = Date(timeIntervalSince1970: 1_000)
        let playhead = MeetingPlayhead(meetingStableID: UUID(),
                                       now: { maintenant },
                                       recordingTick: .milliseconds(10))
        playhead.beginRecording(startedAt: Date(timeIntervalSince1970: 1_000))
        #expect(playhead.t == 0)

        maintenant = Date(timeIntervalSince1970: 1_252)
        try await Task.sleep(for: .milliseconds(250))
        #expect(playhead.t == 252, "le battement n'a pas avancé la position")
        #expect(playhead.duration == 252)

        // `stop()` arrête le battement : une réunion close ne doit pas
        // continuer à faire courir son axe.
        playhead.stop()
        maintenant = Date(timeIntervalSince1970: 1_500)
        try await Task.sleep(for: .milliseconds(250))
        #expect(playhead.t == 252, "le battement tourne encore après stop()")
    }
}
