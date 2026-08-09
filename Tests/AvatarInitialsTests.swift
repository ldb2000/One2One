import XCTest
@testable import OneToOne

/// Initiales des avatars, telles que les captures les montrent :
/// « Sofiane Belkacem » → « SB », « Camille Roussel » → « CR ».
final class AvatarInitialsTests: XCTestCase {

    func test_deuxMots_donnentDeuxInitiales() {
        XCTAssertEqual(Avatar.initiales(de: "Sofiane Belkacem"), "SB")
        XCTAssertEqual(Avatar.initiales(de: "Camille Roussel"), "CR")
        XCTAssertEqual(Avatar.initiales(de: "Anne-Claire Petit"), "AP")
    }

    func test_unSeulMot_donneUneSeuleInitiale() {
        XCTAssertEqual(Avatar.initiales(de: "Sofiane"), "S")
    }

    func test_troisMotsOuPlus_prennentLePremierEtLeDernier() {
        XCTAssertEqual(Avatar.initiales(de: "Jean Pierre Dupont"), "JD")
    }

    func test_espacesSuperflus_sontIgnores() {
        XCTAssertEqual(Avatar.initiales(de: "  Marta   Nowak  "), "MN")
    }

    func test_nomVide_donneUneChaineVide() {
        XCTAssertEqual(Avatar.initiales(de: ""), "")
        XCTAssertEqual(Avatar.initiales(de: "   "), "")
    }

    /// Les initiales sont toujours en capitales, quelle que soit la saisie.
    func test_lesInitialesSontEnCapitales() {
        XCTAssertEqual(Avatar.initiales(de: "sofiane belkacem"), "SB")
    }

    /// Un prénom accentué garde son accent : « Étienne » → « É ».
    func test_lesAccentsSontConserves() {
        XCTAssertEqual(Avatar.initiales(de: "Étienne Roux"), "ÉR")
    }
}
