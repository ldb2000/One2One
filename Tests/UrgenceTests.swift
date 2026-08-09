import XCTest
@testable import OneToOne

/// La règle de couleur d'urgence, déduite des captures 3 et 1a :
/// rouge au-delà de sept jours de retard, orange jusqu'à sept jours,
/// gris pour une échéance à venir.
final class UrgenceTests: XCTestCase {

    /// 8 août 2026, midi — la date de référence des captures.
    private func maintenant() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 8; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func jour(_ day: Int, _ month: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = month; c.day = day; c.hour = 9
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_echeanceDepasseeDePlusDeSeptJours_estForte() {
        // « 27/07 » et « 31/07 » de la capture 3 : rouges.
        XCTAssertEqual(Urgence.pour(jour(27, 7), maintenant: maintenant()), .forte)
        XCTAssertEqual(Urgence.pour(jour(31, 7), maintenant: maintenant()), .forte)
    }

    func test_echeanceDepasseeDeSeptJoursOuMoins_estMoyenne() {
        // « 03/08 », « 05/08 », « 06/08 » de la capture 3 : orange.
        XCTAssertEqual(Urgence.pour(jour(3, 8), maintenant: maintenant()), .moyenne)
        XCTAssertEqual(Urgence.pour(jour(5, 8), maintenant: maintenant()), .moyenne)
        XCTAssertEqual(Urgence.pour(jour(6, 8), maintenant: maintenant()), .moyenne)
    }

    func test_echeanceAVenir_estAVenir() {
        // « 11/08 », « 18/08 » de la capture 3 : grises.
        XCTAssertEqual(Urgence.pour(jour(11, 8), maintenant: maintenant()), .aVenir)
        XCTAssertEqual(Urgence.pour(jour(18, 8), maintenant: maintenant()), .aVenir)
    }

    /// Le jour même n'est pas en retard : la journée entière reste disponible.
    func test_echeanceAujourdHui_estAVenir() {
        XCTAssertEqual(Urgence.pour(jour(8, 8), maintenant: maintenant()), .aVenir)
    }

    /// La borne exacte des sept jours appartient à l'orange, pas au rouge.
    func test_borneDeSeptJours_appartientAOrange() {
        XCTAssertEqual(Urgence.pour(jour(1, 8), maintenant: maintenant()), .moyenne)
        XCTAssertEqual(Urgence.pour(jour(31, 7), maintenant: maintenant()), .forte)
    }

    func test_sansEcheance_aSonPropreCas() {
        XCTAssertEqual(Urgence.pour(nil, maintenant: maintenant()), .sansEcheance)
    }

    /// L'urgence se calcule en jours de calendrier, pas en intervalles de
    /// 24 heures : une échéance d'hier soir est en retard ce matin.
    func test_leCalculPorteSurDesJoursDeCalendrier() {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 7; c.hour = 23
        let hierSoir = Calendar(identifier: .gregorian).date(from: c)!
        var m = DateComponents()
        m.year = 2026; m.month = 8; m.day = 8; m.hour = 1
        let ceMatin = Calendar(identifier: .gregorian).date(from: m)!
        XCTAssertEqual(Urgence.pour(hierSoir, maintenant: ceMatin), .moyenne)
    }

    /// Preuve que `calendrier:` est bien pris en compte, et pas seulement accepté
    /// en façade : pour les deux mêmes instants, un fuseau UTC+14 et un fuseau
    /// UTC-11 (25 h d'écart) ne placent pas le même nombre de minuits entre les
    /// deux dates, ce qui fait basculer le résultat de part et d'autre du seuil
    /// des sept jours. Si l'implémentation ignorait ce paramètre au profit de
    /// `Calendar.current`, les deux appels retourneraient la même urgence.
    func test_leCalendrierExpliciteEstReellementUtilise() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        var eC = DateComponents()
        eC.year = 2026; eC.month = 1; eC.day = 1; eC.hour = 0
        let echeance = utc.date(from: eC)!

        var mC = DateComponents()
        mC.year = 2026; mC.month = 1; mC.day = 8; mC.hour = 10
        let maintenant = utc.date(from: mC)!

        var kiritimati = Calendar(identifier: .gregorian)
        kiritimati.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        var midway = Calendar(identifier: .gregorian)
        midway.timeZone = TimeZone(identifier: "Pacific/Midway")!

        XCTAssertEqual(Urgence.pour(echeance, maintenant: maintenant, calendrier: kiritimati), .forte)
        XCTAssertEqual(Urgence.pour(echeance, maintenant: maintenant, calendrier: midway), .moyenne)
    }
}
