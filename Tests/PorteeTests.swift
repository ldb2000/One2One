import XCTest
@testable import OneToOne

/// Les trois portées d'échéance de la capture 3 : « En retard », « Cette semaine »,
/// « Toutes ». Ce sont des filtres, distincts de la règle de **couleur** (`Urgence`).
final class PorteeTests: XCTestCase {

    /// 9 août 2026, midi.
    private func maintenant() -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 9; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func jour(_ day: Int, _ month: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = month; c.day = day; c.hour = 9
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_enRetard_prendLesEcheancesDepassees() {
        XCTAssertTrue(Portee.contient(jour(27, 7), portee: .enRetard, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(8, 8), portee: .enRetard, maintenant: maintenant()))
    }

    /// Le jour même n'est pas en retard : la journée entière reste disponible.
    func test_enRetard_exclutAujourdHui() {
        XCTAssertFalse(Portee.contient(jour(9, 8), portee: .enRetard, maintenant: maintenant()))
    }

    func test_enRetard_exclutLAVenirEtLeSansEcheance() {
        XCTAssertFalse(Portee.contient(jour(15, 8), portee: .enRetard, maintenant: maintenant()))
        XCTAssertFalse(Portee.contient(nil, portee: .enRetard, maintenant: maintenant()))
    }

    /// « Cette semaine » = d'aujourd'hui inclus à J+7 inclus.
    func test_cetteSemaine_prendAujourdHuiEtLesSeptJoursSuivants() {
        XCTAssertTrue(Portee.contient(jour(9, 8), portee: .cetteSemaine, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(12, 8), portee: .cetteSemaine, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(16, 8), portee: .cetteSemaine, maintenant: maintenant()))
    }

    func test_cetteSemaine_exclutJPlusHuit() {
        XCTAssertFalse(Portee.contient(jour(17, 8), portee: .cetteSemaine, maintenant: maintenant()))
    }

    /// Une échéance dépassée n'est pas « cette semaine » : elle est « en retard ».
    func test_cetteSemaine_exclutLeRetard() {
        XCTAssertFalse(Portee.contient(jour(8, 8), portee: .cetteSemaine, maintenant: maintenant()))
    }

    func test_cetteSemaine_exclutLeSansEcheance() {
        XCTAssertFalse(Portee.contient(nil, portee: .cetteSemaine, maintenant: maintenant()))
    }

    /// « Toutes » ne filtre rien, pas même les actions sans échéance.
    func test_toutes_prendTout() {
        XCTAssertTrue(Portee.contient(jour(27, 7), portee: .toutes, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(9, 8), portee: .toutes, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(31, 12), portee: .toutes, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(nil, portee: .toutes, maintenant: maintenant()))
    }

    /// Les trois portées sont exclusives sur les échéances datées, et « Toutes » les
    /// recouvre : une échéance datée tombe dans « En retard » ou « Cette semaine »
    /// ou ni l'une ni l'autre, jamais dans les deux.
    func test_enRetardEtCetteSemaine_neSeChevauchentJamais() {
        for jourDuMois in 1...31 {
            let date = jour(jourDuMois, 8)
            let retard = Portee.contient(date, portee: .enRetard, maintenant: maintenant())
            let semaine = Portee.contient(date, portee: .cetteSemaine, maintenant: maintenant())
            XCTAssertFalse(retard && semaine, "le \(jourDuMois)/08 tombe dans les deux portées")
        }
    }
}
