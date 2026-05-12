import XCTest
@testable import OneToOne

final class TeamsLauncherTests: XCTestCase {

    func test_rewrite_httpsTeams_toMsteamsScheme() {
        let input = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3aabc%40thread.v2/0?context=ctx")!
        let result = TeamsLauncher.rewriteToMSTeams(input)
        XCTAssertEqual(result?.scheme, "msteams")
        XCTAssertEqual(result?.absoluteString,
                       "msteams:/l/meetup-join/19%3aabc%40thread.v2/0?context=ctx")
    }

    func test_rewrite_msteams_passthrough() {
        let input = URL(string: "msteams:/l/meetup-join/19%3aabc%40thread.v2/0")!
        XCTAssertEqual(TeamsLauncher.rewriteToMSTeams(input), input)
    }

    func test_rewrite_nonTeamsHost_returnsNil() {
        let input = URL(string: "https://meet.google.com/abc-defg-hij")!
        XCTAssertNil(TeamsLauncher.rewriteToMSTeams(input))
    }

    func test_rewrite_teamsButNotMeetupJoinPath_returnsNil() {
        let input = URL(string: "https://teams.microsoft.com/about")!
        XCTAssertNil(TeamsLauncher.rewriteToMSTeams(input))
    }
}
