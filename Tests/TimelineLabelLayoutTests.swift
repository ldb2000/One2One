import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// Les étiquettes de la frise audio du poste de pilotage (spec §2.7 : « frise
/// audio en pied d'écran, pleine largeur, avec étiquettes de marqueurs
/// (`04:12`, `DÉCISION`) »).
///
/// Le placement est extrait de la vue parce que « sans chevauchement » est une
/// propriété qu'on ne voit pas dans un `Canvas` : deux étiquettes superposées
/// dessinent un pâté lisible de loin comme une seule, et rien ne le signale.
@Suite("Étiquettes de la frise audio")
struct TimelineLabelLayoutTests {

    /// La durée de la capture : `23:24`.
    private let duree: Double = 1_404

    /// Les quatre notes du jeu de démonstration : `04:12`, `07:48`, `11:03`
    /// (décision) et `15:20`.
    private var candidatsDeLaCapture: [TimelineLabelLayout.Candidat] {
        [
            .init(t: 252, texte: "04:12", estDecision: false),
            .init(t: 468, texte: "07:48", estDecision: false),
            .init(t: 663, texte: "DÉCISION", estDecision: true),
            .init(t: 920, texte: "15:20", estDecision: false)
        ]
    }

    @Test("Sur une frise large, aucune étiquette n'en recouvre une autre")
    func noOverlap() {
        let placees = TimelineLabelLayout.placer(candidatsDeLaCapture,
                                                  duration: duree,
                                                  width: 1_200)
        #expect(placees.count >= 2)
        for (precedente, suivante) in zip(placees, placees.dropFirst()) {
            let finPrecedente = precedente.centre + precedente.largeur / 2
            let debutSuivante = suivante.centre - suivante.largeur / 2
            #expect(debutSuivante >= finPrecedente + TimelineLabelLayout.espacement)
        }
    }

    @Test("Sur une frise étroite, une étiquette qui n'entre pas est abandonnée")
    func droppedWhenTight() {
        let large = TimelineLabelLayout.placer(candidatsDeLaCapture,
                                                duration: duree,
                                                width: 1_200)
        let etroite = TimelineLabelLayout.placer(candidatsDeLaCapture,
                                                  duration: duree,
                                                  width: 240)
        #expect(etroite.count < large.count)
    }

    @Test("Sur une frise large, les quatre notes de la séance s'étiquettent")
    func allFitWhenWide() {
        let placees = TimelineLabelLayout.placer(candidatsDeLaCapture,
                                                  duration: duree,
                                                  width: 1_200)
        #expect(placees.map(\.texte) == ["04:12", "07:48", "DÉCISION", "15:20"])
    }

    @Test("À l'étroit, la décision l'emporte sur le timecode voisin")
    func decisionWins() {
        // Deux marqueurs à cinquante secondes d'écart sur une frise de 240 px :
        // il n'y a de place que pour une étiquette. C'est la décision qu'on
        // cherche en relisant une réunion, pas un timecode nu.
        let candidats: [TimelineLabelLayout.Candidat] = [
            .init(t: 252, texte: "04:12", estDecision: false),
            .init(t: 300, texte: "DÉCISION", estDecision: true)
        ]
        let placees = TimelineLabelLayout.placer(candidats, duration: duree, width: 240)
        #expect(placees.map(\.texte) == ["DÉCISION"])
    }

    @Test("Une étiquette de bord est rentrée dans la piste")
    func clampedToTrack() {
        let candidats: [TimelineLabelLayout.Candidat] = [
            .init(t: 0, texte: "00:00", estDecision: false),
            .init(t: 1_404, texte: "23:24", estDecision: false)
        ]
        let placees = TimelineLabelLayout.placer(candidats, duration: duree, width: 600)
        #expect(placees.count == 2)
        for etiquette in placees {
            #expect(etiquette.centre - etiquette.largeur / 2 >= -0.001)
            #expect(etiquette.centre + etiquette.largeur / 2 <= 600.001)
        }
    }

    @Test("Une durée ou une largeur nulle ne place rien, et jamais un NaN")
    func degenerate() {
        #expect(TimelineLabelLayout.placer(candidatsDeLaCapture, duration: 0, width: 600).isEmpty)
        #expect(TimelineLabelLayout.placer(candidatsDeLaCapture, duration: duree, width: 0).isEmpty)
        #expect(TimelineLabelLayout.placer([], duration: duree, width: 600).isEmpty)
    }

    @Test("Des candidats non triés sortent dans l'ordre du temps")
    func sorted() {
        let melanges: [TimelineLabelLayout.Candidat] = [
            .init(t: 920, texte: "15:20", estDecision: false),
            .init(t: 252, texte: "04:12", estDecision: false)
        ]
        let placees = TimelineLabelLayout.placer(melanges, duration: duree, width: 1_200)
        #expect(placees.map(\.texte) == ["04:12", "15:20"])
        #expect(placees[0].centre < placees[1].centre)
    }

    @Test("Une étiquette plus longue est plus large")
    func widthGrowsWithText() {
        #expect(TimelineLabelLayout.largeur("DÉCISION") > TimelineLabelLayout.largeur("04:12"))
        #expect(TimelineLabelLayout.largeur("") > 0)
    }

    // MARK: - Candidats et hauteur de la frise (lot 5, mode étiqueté)

    @Test("Le mode étiqueté est plus haut, le rendu par défaut inchangé")
    func stripHeight() {
        #expect(AudioTimelineStrip.hauteur(labelled: false) == AudioTimelineGeometry.height + 12)
        #expect(AudioTimelineStrip.hauteur(labelled: true) > AudioTimelineStrip.hauteur(labelled: false))
    }

    @Test("Une décision s'étiquette DÉCISION, les autres par leur timecode")
    func candidateLabels() {
        let repères: [MeetingPlayhead.Marker] = [
            .init(t: 252, kind: .note),
            .init(t: 663, kind: .decision),
            .init(t: 800, kind: .risk),
            .init(t: 900, kind: .capture)
        ]
        let candidats = AudioTimelineStrip.candidats(repères)
        // La capture garde son carré et n'a pas d'étiquette : une étiquette par
        // vignette saturerait la frise, et le carré se lit déjà.
        #expect(candidats.count == 3)
        #expect(candidats.map(\.texte) == ["04:12", "DÉCISION", "13:20"])
        #expect(candidats.map(\.estDecision) == [false, true, false])
    }
}
