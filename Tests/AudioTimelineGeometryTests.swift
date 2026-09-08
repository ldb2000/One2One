import Testing
import CoreGraphics
@testable import OneToOne

/// La frise audio de 22 px en pied de la carte notes ↔ transcription
/// (spec §2.4 : « onde échantillonnée, tête de lecture 2 px `accent/action`,
/// marqueurs ronds (note), carrés (capture), losanges (décision). Clic =
/// déplacement, glisser = balayage »).
///
/// La conversion `t ↔ x` est extraite de la vue parce qu'un `Canvas` à qui l'on
/// passe un `NaN` ne dessine rien **sans rien signaler** : une durée nulle (pas
/// encore d'audio) est le cas courant, pas l'exception.
@Suite("Géométrie de la frise audio")
struct AudioTimelineGeometryTests {

    @Test("La hauteur et la tête de lecture sont celles de la spec")
    func dimensions() {
        #expect(AudioTimelineGeometry.height == 22)
        #expect(AudioTimelineGeometry.playheadWidth == 2)
    }

    @Test("t = 0 est à gauche, t = durée est à droite")
    func bornes() {
        #expect(AudioTimelineGeometry.x(t: 0, duration: 1_404, width: 600) == 0)
        #expect(AudioTimelineGeometry.x(t: 1_404, duration: 1_404, width: 600) == 600)
    }

    @Test("La position est proportionnelle")
    func proportion() {
        let x = AudioTimelineGeometry.x(t: 702, duration: 1_404, width: 600)
        #expect(abs(x - 300) < 0.001)
    }

    @Test("Sans durée, tout est à zéro plutôt que NaN")
    func dureeNulle() {
        #expect(AudioTimelineGeometry.x(t: 100, duration: 0, width: 600) == 0)
        #expect(AudioTimelineGeometry.t(x: 300, duration: 0, width: 600) == 0)
    }

    @Test("Une position hors bornes est ramenée dans la frise")
    func bornage() {
        #expect(AudioTimelineGeometry.x(t: -10, duration: 1_404, width: 600) == 0)
        #expect(AudioTimelineGeometry.x(t: 9_999, duration: 1_404, width: 600) == 600)
        #expect(AudioTimelineGeometry.t(x: -50, duration: 1_404, width: 600) == 0)
        #expect(AudioTimelineGeometry.t(x: 5_000, duration: 1_404, width: 600) == 1_404)
    }

    @Test("Le clic rend le temps du point cliqué")
    func clic() {
        let t = AudioTimelineGeometry.t(x: 300, duration: 1_404, width: 600)
        #expect(abs(t - 702) < 0.001)
    }

    @Test("L'aller-retour temps → position → temps est stable")
    func allerRetour() {
        for t in [0.0, 12.5, 252.0, 663.0, 1_403.9] {
            let x = AudioTimelineGeometry.x(t: t, duration: 1_404, width: 823)
            let retour = AudioTimelineGeometry.t(x: x, duration: 1_404, width: 823)
            #expect(abs(retour - t) < 0.01)
        }
    }

    @Test("Une largeur nulle ne produit pas de division par zéro")
    func largeurNulle() {
        #expect(AudioTimelineGeometry.x(t: 252, duration: 1_404, width: 0) == 0)
        #expect(AudioTimelineGeometry.t(x: 10, duration: 1_404, width: 0) == 0)
    }
}
