import Testing
import Foundation
@testable import OneToOne

/// « La couleur d'avatar est identique après relance de l'app. » — critère
/// d'acceptation de la spec.
///
/// `hashValue` ne convient pas : Swift le sale à chaque lancement du
/// processus, donc la couleur changerait à chaque démarrage. Le hachage est
/// donc calculé à la main, sur les scalaires du texte.
@Suite("AvatarPalette — une couleur stable d'un lancement à l'autre")
struct AvatarPaletteTests {

    @Test("La même identité rend toujours le même rang")
    func sameIdentitySameSlot() {
        let premier = AvatarPalette.slot(for: "PAOLI Nicolas")
        let second = AvatarPalette.slot(for: "PAOLI Nicolas")
        #expect(premier == second)
    }

    /// Le vrai test de stabilité : des valeurs **figées**, relevées sur le
    /// calcul le jour où il a été écrit. Elles n'ont aucune signification en
    /// soi ; leur seul rôle est de tomber si le hachage change — auquel cas la
    /// couleur de tous les avatars aurait bougé d'un lancement à l'autre.
    @Test("Le rang est figé, pas seulement reproductible dans la session")
    func slotIsPinned() {
        #expect(AvatarPalette.slot(for: "PAOLI Nicolas") == 4)
        #expect(AvatarPalette.slot(for: "THEDREZ Wilfried") == 1)
        #expect(AvatarPalette.slot(for: "") == 0)
    }

    @Test("Le rang reste dans les cinq paires disponibles")
    func slotStaysInRange() {
        for nom in ["A", "Zoé", "Jean-Baptiste ORSET", "李雷", "x" ] {
            let slot = AvatarPalette.slot(for: nom)
            #expect((0..<AvatarPalette.pairCount).contains(slot))
        }
    }

    @Test("Les initiales prennent la première lettre de deux mots au plus")
    func initialsTakeAtMostTwoWords() {
        #expect(AvatarPalette.initials(for: "Nicolas Paoli") == "NP")
        #expect(AvatarPalette.initials(for: "Jean-Baptiste ORSET Junior") == "JO")
        #expect(AvatarPalette.initials(for: "Zoé") == "Z")
        #expect(AvatarPalette.initials(for: "   ") == "?")
    }
}
