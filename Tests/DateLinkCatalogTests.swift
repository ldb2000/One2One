import XCTest
@testable import OneToOne

/// Caractérise `DateLinkCatalog` : construction et lecture du lien
/// `onetoone://date/…` — pendant de `MentionCatalogTests` pour les dates.
/// Logique pure, sans `NSTextView` ni SwiftData.
final class DateLinkCatalogTests: XCTestCase {

    /// Date/heure fixe utilisée par tous les tests — pas de composante
    /// secondes (le format ISO retenu, `HH:mm`, n'en porte pas ; un test qui
    /// en fixerait une masquerait une perte de précision réelle derrière une
    /// coïncidence).
    private static var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 6
        components.hour = 13
        components.minute = 8
        return Calendar.current.date(from: components)!
    }

    private static var fixedDateOnly: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 5
        // Composante heure non significative pour `includesTime: false` (voir
        // la doc de `SlashDateSelection.date`) : fixée à midi plutôt qu'à
        // minuit pour ne dépendre d'aucun arrondi de fuseau horaire.
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    // MARK: - `dateURL` : schéma, hôte, chemin

    func test_dateURL_withoutTime_hasISODatePath() {
        let url = DateLinkCatalog.dateURL(date: Self.fixedDateOnly, includesTime: false, reminder: .none)
        XCTAssertEqual(url.scheme, "onetoone")
        XCTAssertEqual(url.host, "date")
        XCTAssertEqual(url.path, "/2026-08-05")
    }

    func test_dateURL_withTime_hasISODateTimePath() {
        let url = DateLinkCatalog.dateURL(date: Self.fixedDate, includesTime: true, reminder: .none)
        XCTAssertEqual(url.path, "/2026-08-06T13:08")
    }

    func test_dateURL_withoutTime_ignoresTimeComponentOfDate() {
        // Deux dates du même jour mais à des heures différentes doivent
        // produire le même chemin quand `includesTime` est faux : la partie
        // heure ne doit pas fuiter dans l'URL.
        var laterComponents = DateComponents()
        laterComponents.year = 2026
        laterComponents.month = 8
        laterComponents.day = 5
        laterComponents.hour = 23
        laterComponents.minute = 59
        let later = Calendar.current.date(from: laterComponents)!

        let url = DateLinkCatalog.dateURL(date: later, includesTime: false, reminder: .none)
        XCTAssertEqual(url.path, "/2026-08-05")
    }

    // MARK: - `dateURL` : rappel

    func test_dateURL_reminderNone_omitsQueryItem() {
        let url = DateLinkCatalog.dateURL(date: Self.fixedDateOnly, includesTime: false, reminder: .none)
        XCTAssertNil(url.query, "aucun paramètre `reminder` quand le rappel est « Aucun »")
    }

    func test_dateURL_reminderDayBefore_matchesSpecExample() {
        // Exemple exact de la spec : `onetoone://date/2026-08-05?reminder=P1D`.
        let url = DateLinkCatalog.dateURL(date: Self.fixedDateOnly, includesTime: false, reminder: .dayBefore)
        XCTAssertEqual(url.absoluteString, "onetoone://date/2026-08-05?reminder=P1D")
    }

    func test_dateURL_allReminders_produceDistinctQueryValues() {
        let reminders: [DateReminder] = [.sameDayAt9, .dayBefore, .twoDaysBefore, .oneWeekBefore]
        let tokens = reminders.map { reminder in
            DateLinkCatalog.dateURL(date: Self.fixedDateOnly, includesTime: false, reminder: reminder).query
        }
        XCTAssertEqual(Set(tokens.compactMap { $0 }).count, reminders.count,
                       "chaque rappel non-none doit produire un jeton de requête distinct")
    }

    // MARK: - `selection(from:)` : aller-retour

    func test_selection_roundTripsWithDateURL_withoutTimeOrReminder() {
        let url = DateLinkCatalog.dateURL(date: Self.fixedDateOnly, includesTime: false, reminder: .none)
        let selection = DateLinkCatalog.selection(from: url)
        XCTAssertEqual(selection?.includesTime, false)
        XCTAssertEqual(selection?.reminder, DateReminder.none)
        XCTAssertEqual(
            selection.map { Calendar.current.startOfDay(for: $0.date) },
            Calendar.current.startOfDay(for: Self.fixedDateOnly)
        )
    }

    func test_selection_roundTripsWithDateURL_withTime() {
        let url = DateLinkCatalog.dateURL(date: Self.fixedDate, includesTime: true, reminder: .none)
        let selection = DateLinkCatalog.selection(from: url)
        XCTAssertEqual(selection?.includesTime, true)
        XCTAssertEqual(selection?.date, Self.fixedDate, "aucune perte de précision à la minute près")
    }

    func test_selection_roundTripsWithDateURL_withReminder() {
        for reminder in DateReminder.allCases where reminder != .none {
            let url = DateLinkCatalog.dateURL(date: Self.fixedDateOnly, includesTime: false, reminder: reminder)
            XCTAssertEqual(DateLinkCatalog.selection(from: url)?.reminder, reminder,
                           "le rappel \(reminder) doit survivre à l'aller-retour")
        }
    }

    // MARK: - `selection(from:)` : formes invalides

    func test_selection_wrongScheme_returnsNil() {
        let url = URL(string: "https://date/2026-08-05")!
        XCTAssertNil(DateLinkCatalog.selection(from: url))
    }

    func test_selection_wrongHost_returnsNil() {
        // Même schéma que les mentions, hôte différent.
        let url = URL(string: "onetoone://collaborator/2026-08-05")!
        XCTAssertNil(DateLinkCatalog.selection(from: url))
    }

    func test_selection_malformedPath_returnsNil() {
        let url = URL(string: "onetoone://date/pas-une-date")!
        XCTAssertNil(DateLinkCatalog.selection(from: url))
    }

    /// Dégradation volontaire (voir la doc de `selection(from:)`) : un jeton
    /// de rappel inconnu ne doit pas faire échouer tout le parsing, seul le
    /// rappel retombe sur `.none`.
    func test_selection_unknownReminderToken_fallsBackToNone_keepsDate() {
        let url = URL(string: "onetoone://date/2026-08-05?reminder=P3D")!
        let selection = DateLinkCatalog.selection(from: url)
        XCTAssertNotNil(selection, "une date par ailleurs valide doit rester résoluble")
        XCTAssertEqual(selection?.reminder, DateReminder.none)
    }
}
