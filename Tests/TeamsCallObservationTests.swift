import Testing
import Foundation
@testable import OneToOne

/// La détection d'appel Teams est une heuristique : elle se trompe. Ces tests
/// verrouillent les seuils qui la rendent supportable — 5 s de stabilité avant
/// d'émettre, 30 s d'absence avant de conclure à la fin, 30 s de cooldown entre
/// deux émissions. Les abaisser est une décision, pas un détail.
@Suite("TeamsCallObservation — heuristique de détection d'appel")
struct TeamsCallObservationTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func input(_ present: Bool, _ title: String, _ offset: TimeInterval) -> TeamsObservationInput {
        TeamsObservationInput(isTeamsWindowPresent: present,
                              windowTitle: title,
                              now: t0.addingTimeInterval(offset))
    }

    // MARK: - Reconnaissance du titre

    @Test("Un titre vide ne ressemble pas à un appel")
    func emptyTitle() {
        #expect(!TeamsCallObservation.titleLooksLikeCall(""))
    }

    @Test("Un titre français accentué est reconnu")
    func frenchTitle() {
        #expect(TeamsCallObservation.titleLooksLikeCall("Réunion hebdo | Microsoft Teams"))
    }

    @Test("Un titre anglais est reconnu")
    func englishTitle() {
        #expect(TeamsCallObservation.titleLooksLikeCall("Weekly Call — Microsoft Teams"))
    }

    @Test("Un titre sans mot d'appel n'est pas reconnu")
    func chatTitle() {
        #expect(!TeamsCallObservation.titleLooksLikeCall("Discussion | Microsoft Teams"))
    }

    // MARK: - Machine à états

    @Test("5 s pile de stabilité suffisent à émettre callStarted")
    func exactlyFiveSeconds() {
        var state = TeamsCallState()
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5)) == .callStarted)
    }

    @Test("4,9 s ne suffisent pas")
    func justUnderFiveSeconds() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 4.9)) == .none)
    }

    @Test("Aucune fenêtre Teams → aucune décision")
    func noTeamsWindow() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(false, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "Réunion", 10)) == .none)
    }

    @Test("Une fenêtre qui disparaît avant 5 s ramène à l'état initial sans rien émettre")
    func flickerIsIgnored() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 2)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 3)) == .none)
        // Le compteur est reparti de 3 s, pas de 0 s : 5 s après 3 s → 8 s.
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 8)) == .callStarted)
    }

    @Test("Deux détections à moins de 30 s d'écart n'émettent qu'un seul callStarted")
    func cooldownMergesDetections() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5)) == .callStarted)
        // La fenêtre disparaît brièvement puis revient : pas de second popup.
        _ = TeamsCallObservation.step(state: &state, input: input(false, "", 6))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 7))
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 12)) == .none)
    }

    @Test("30 s pile d'absence concluent à la fin de l'appel")
    func endAfterThirtySeconds() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 10)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 39.9)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 40)) == .callEnded)
    }

    @Test("Un retour de la fenêtre avant 30 s annule la fin d'appel")
    func returningWindowCancelsEnd() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5))
        _ = TeamsCallObservation.step(state: &state, input: input(false, "", 10))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 20))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 45)) == .none)
    }
}
