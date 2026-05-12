import Foundation
import AppKit

/// Opens a Microsoft Teams meeting URL using the desktop app if installed,
/// falling back to the web client (browser) via macOS URL handler routing.
/// No MS Graph, no auth — just URL scheme rewriting.
enum TeamsLauncher {

    /// Public entry point — fire-and-forget.
    static func open(_ urlString: String) {
        guard let parsed = URL(string: urlString) else { return }
        let target = rewriteToMSTeams(parsed) ?? parsed
        NSWorkspace.shared.open(target)
    }

    /// Rewrites `https://teams.microsoft.com/l/meetup-join/...` to
    /// `msteams:/l/meetup-join/...` so the desktop app handles it.
    /// Returns nil if the URL is not a Teams meet-join URL.
    static func rewriteToMSTeams(_ url: URL) -> URL? {
        if url.scheme?.lowercased() == "msteams" { return url }
        guard let host = url.host?.lowercased(),
              host == "teams.microsoft.com" || host == "teams.live.com",
              url.path.contains("/l/meetup-join/") else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "msteams"
        comps?.host = nil  // msteams: scheme has no host
        return comps?.url
    }
}
