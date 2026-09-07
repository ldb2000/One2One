import Testing
import Foundation
@testable import OneToOne

/// La pression du stylet du mode Manuscrit (spec §7.1 : « tracé
/// stylet/trackpad, **pression si disponible** »).
///
/// La pression réelle demande une tablette et une session graphique : elle
/// n'est pas vérifiable ici (protocole du lot 17 — aucune recette graphique).
/// Ce qui est vérifiable, et l'est, c'est la **règle** : une souris n'apporte
/// pas de pression, une tablette en apporte une bornée, et l'épaisseur suit.
@Suite("Pression du stylet du mode Manuscrit")
@MainActor
struct InkPressureTests {

    @Test("Sans tablette, aucune pression : l'épaisseur reste fixe")
    func mouseHasNoPressure() {
        #expect(InkPressure.normalized(raw: 0.5, isTablet: false) == nil)
        #expect(InkPressure.normalized(raw: 1, isTablet: false) == nil)
    }

    @Test("La pression d'une tablette est bornée à 0…1")
    func tabletPressureIsClamped() {
        #expect(InkPressure.normalized(raw: 0, isTablet: true) == 0)
        #expect(InkPressure.normalized(raw: 0.4, isTablet: true) == 0.4)
        #expect(InkPressure.normalized(raw: 1, isTablet: true) == 1)
        #expect(InkPressure.normalized(raw: 2.5, isTablet: true) == 1)
        #expect(InkPressure.normalized(raw: -1, isTablet: true) == 0)
    }

    @Test("L'épaisseur suit la pression, et vaut l'épaisseur choisie sans elle")
    func strokeWidthFollowsPressure() {
        #expect(InkPressure.strokeWidth(base: 2, pressure: nil) == 2)
        let faible = InkPressure.strokeWidth(base: 2, pressure: 0.2)
        let forte = InkPressure.strokeWidth(base: 2, pressure: 1)
        #expect(faible < forte)
        // Un stylet posé sans appuyer trace quand même : jamais zéro.
        #expect(InkPressure.strokeWidth(base: 2, pressure: 0) > 0)
        #expect(forte <= 2 * InkPressure.maximumFactor)
    }

    @Test("Le moniteur publie la dernière pression reçue, et se retire à l'arrêt")
    func monitorPublishesAndTearsDown() {
        var emettre: ((StylusPressureMonitor.Sample) -> Void)?
        var retire = 0
        let moniteur = StylusPressureMonitor(
            install: { rappel in emettre = rappel; return "jeton" as NSString },
            teardown: { _ in retire += 1 })

        var recues: [Double?] = []
        moniteur.onChange = { recues.append($0) }

        #expect(moniteur.isRunning == false)
        moniteur.start()
        #expect(moniteur.isRunning)

        emettre?(.init(pressure: 0.7, isTablet: true))
        #expect(moniteur.pressure == 0.7)
        // Une souris n'apporte pas de pression : la valeur retombe, elle ne
        // reste pas figée sur le dernier trait du stylet.
        emettre?(.init(pressure: 0.9, isTablet: false))
        #expect(moniteur.pressure == nil)
        #expect(recues == [0.7, nil])

        moniteur.stop()
        #expect(moniteur.isRunning == false)
        #expect(retire == 1)
        #expect(moniteur.pressure == nil)

        // Démarrer deux fois n'installe qu'un moniteur — sinon chaque
        // remontage de la vue en empilerait un de plus.
        moniteur.start()
        moniteur.start()
        moniteur.stop()
        #expect(retire == 2)
    }
}
