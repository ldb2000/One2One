import XCTest
@testable import OneToOne

final class TeamsURLExtractorTests: XCTestCase {

    func test_extractsFromEventURL_https() {
        let url = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertEqual(result, url.absoluteString)
    }

    func test_extractsFromEventURL_msteamsScheme() {
        let url = URL(string: "msteams:/l/meetup-join/19%3aabc%40thread.v2/0")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertEqual(result, url.absoluteString)
    }

    func test_extractsFromNotes_whenURLAbsent() {
        let notes = """
        Bonjour,
        ________________________________________________________________________________
        Join Microsoft Teams Meeting
        https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz%40thread.v2/0?context=ctx
        Learn more about Teams
        """
        let result = TeamsURLExtractor.extract(url: nil, notes: notes, location: nil)
        XCTAssertEqual(result, "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz%40thread.v2/0?context=ctx")
    }

    func test_extractsFromLocation_lastResort() {
        let location = "Réunion Microsoft Teams https://teams.microsoft.com/l/meetup-join/19%3aloc%40thread.v2/0"
        let result = TeamsURLExtractor.extract(url: nil, notes: nil, location: location)
        XCTAssertEqual(result, "https://teams.microsoft.com/l/meetup-join/19%3aloc%40thread.v2/0")
    }

    func test_returnsNil_whenAbsent() {
        let result = TeamsURLExtractor.extract(url: URL(string: "https://example.com/cal/event"), notes: "no link here", location: "Salle Bercy")
        XCTAssertNil(result)
    }

    func test_ignoresNonTeamsHosts() {
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertNil(result)
    }

    func test_acceptsTeamsLiveHost() {
        let url = URL(string: "https://teams.live.com/meet/9876543210?p=token")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertEqual(result, url.absoluteString)
    }
}
