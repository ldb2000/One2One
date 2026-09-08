import Testing
import SwiftUI
@testable import OneToOne

/// La bannière d'annulation de l'enregistrement optimiste (spec §4.3 :
/// « enregistrement optimiste avec possibilité d'annuler pendant 5 s »).
@Suite("UndoBanner — annulation à cinq secondes")
@MainActor
struct UndoBannerTests {

    @Test("La fenêtre d'annulation dure cinq secondes")
    func durationIsFiveSeconds() {
        #expect(UndoBanner.duration == 5)
    }

    @Test("Le message par défaut est celui de la spec")
    func defaultMessage() {
        #expect(UndoBanner.defaultMessage == "Modifications enregistrées")
    }

    /// La bannière se construit hors session graphique : sans cela, aucun test
    /// du panneau ne serait exécutable en `swift test` (programme §8).
    @Test("La bannière se construit sans session graphique")
    func buildsWithoutWindow() {
        let banniere = UndoBanner(message: "Modifications enregistrées",
                                  onUndo: {},
                                  onExpire: {})
        #expect(banniere.message == "Modifications enregistrées")
    }

    /// Le geste `Annuler` doit être branché sur la restauration, pas seulement
    /// sur la disparition de la bannière : le test vérifie que le rappel est
    /// bien celui qu'on lui donne.
    @Test("Annuler appelle le rappel de restauration")
    func undoCallsItsClosure() {
        var restaure = false
        let banniere = UndoBanner(message: "x", onUndo: { restaure = true }, onExpire: {})
        banniere.onUndo()
        #expect(restaure)
    }

    @Test("L'expiration appelle son propre rappel, distinct de l'annulation")
    func expiryCallsItsOwnClosure() {
        var annule = false
        var expire = false
        let banniere = UndoBanner(message: "x",
                                  onUndo: { annule = true },
                                  onExpire: { expire = true })
        banniere.onExpire()
        #expect(expire)
        #expect(annule == false)
    }
}
