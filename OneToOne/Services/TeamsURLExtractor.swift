import Foundation

/// Extracts a Microsoft Teams join URL from an EKEvent's url / notes / location.
/// Priority: event.url → notes → location. Only accepts `msteams://` scheme or
/// `teams.microsoft.com` / `teams.live.com` hosts (Google Meet, Zoom, etc. ignored).
enum TeamsURLExtractor {

    private static let teamsHosts: Set<String> = ["teams.microsoft.com", "teams.live.com"]

    private static let teamsURLPattern: NSRegularExpression = {
        let pattern = #"https://teams\.(?:microsoft|live)\.com/[^\s"'<>]+"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func extract(url: URL?, notes: String?, location: String?) -> String? {
        if let url, isTeams(url) { return url.absoluteString }
        if let notes, let m = firstMatch(in: notes) { return m }
        if let location, let m = firstMatch(in: location) { return m }
        return nil
    }

    private static func isTeams(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "msteams" { return true }
        guard let host = url.host?.lowercased() else { return false }
        return teamsHosts.contains(host)
    }

    private static func firstMatch(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = teamsURLPattern.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
