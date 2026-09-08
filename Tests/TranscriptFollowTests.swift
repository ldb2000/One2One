import Testing
@testable import OneToOne

/// « Défilement lié : bascule `Suivre` ; si active, la transcription suit la
/// tête de lecture. Toute interaction manuelle la désactive et affiche
/// `Reprendre le suivi`. » (spec §2.4)
///
/// La règle est une machine à états à un bit, mais elle a un piège : ni
/// l'avancée de la tête de lecture ni l'arrivée de nouveaux segments ne doivent
/// **réactiver** le suivi. Sinon le lecteur qui remonte lire un passage se
/// verrait ramené en bas à chaque seconde d'audio.
@Suite("Défilement lié de la transcription")
struct TranscriptFollowTests {

    @Test("Une interaction manuelle coupe le suivi")
    func interactionManuelle() {
        #expect(TranscriptFollow.next(following: true, on: .manualScroll) == false)
    }

    @Test("Reprendre le suivi le réactive")
    func reprise() {
        #expect(TranscriptFollow.next(following: false, on: .resumeRequested) == true)
    }

    @Test("La tête de lecture ne réactive jamais le suivi")
    func teteDeLecture() {
        #expect(TranscriptFollow.next(following: false, on: .playheadMoved) == false)
        #expect(TranscriptFollow.next(following: true, on: .playheadMoved) == true)
    }

    @Test("L'arrivée de nouveaux segments ne réactive jamais le suivi")
    func segmentsAjoutes() {
        #expect(TranscriptFollow.next(following: false, on: .segmentsAppended) == false)
        #expect(TranscriptFollow.next(following: true, on: .segmentsAppended) == true)
    }

    @Test("Les deux libellés sont ceux de la spec")
    func libelles() {
        #expect(TranscriptFollow.label(following: true) == "Suivre")
        #expect(TranscriptFollow.label(following: false) == "Reprendre le suivi")
    }

    @Test("La cible est le dernier segment commencé avant t")
    func cible() {
        let debuts: [Double] = [231, 252, 390, 663]
        #expect(TranscriptFollow.target(startTimes: debuts, t: 260) == 1)
        #expect(TranscriptFollow.target(startTimes: debuts, t: 252) == 1)
        #expect(TranscriptFollow.target(startTimes: debuts, t: 400) == 2)
    }

    @Test("Avant le premier segment, il n'y a pas de cible")
    func avantLePremier() {
        // Rendre 0 ferait sauter la colonne en tête dès la première seconde
        // d'un enregistrement dont la parole ne commence qu'à 3:51.
        #expect(TranscriptFollow.target(startTimes: [231, 252], t: 10) == nil)
    }

    @Test("Au-delà du dernier segment, la cible reste le dernier")
    func apresLeDernier() {
        #expect(TranscriptFollow.target(startTimes: [231, 252, 390], t: 1_400) == 2)
    }

    @Test("Une transcription vide n'a pas de cible")
    func listeVide() {
        #expect(TranscriptFollow.target(startTimes: [], t: 100) == nil)
    }

    @Test("Des débuts non triés sont traités dans l'ordre du temps")
    func nonTries() {
        // Les segments arrivent triés par `orderIndex`, qui suit le temps —
        // mais une réattribution de tours de parole peut les désordonner.
        #expect(TranscriptFollow.target(startTimes: [390, 231, 252], t: 260) == 2)
    }
}
