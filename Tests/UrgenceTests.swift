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
}
