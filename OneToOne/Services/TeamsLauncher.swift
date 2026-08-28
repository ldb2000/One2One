import Foundation
import AppKit

/// Opens a Microsoft Teams meeting URL using the desktop app if installed,
/// falling back to the web client (browser) via macOS URL handler routing.
/// No MS Graph, no auth — just URL scheme rewriting.
enum TeamsLauncher {

    /// Émise quand l'utilisateur rejoint explicitement un appel Teams depuis
    /// OneToOne — déclencheur 2 de la spec §3. Signal sans faux positif :
    /// contrairement à la surveillance de fenêtres, l'intention est certaine.
    static let didJoinNotification = Notification.Name("OneToOne.TeamsLauncher.didJoin")

    /// Point d'entrée public — fire-and-forget.
    /// Parse `urlString`, tente la réécriture vers le scheme `msteams:` (app
    /// desktop) et ouvre l'URL via `NSWorkspace`. Si l'URL n'est pas une URL de
    /// jonction Teams, ouvre l'URL d'origine telle quelle (fallback navigateur).
    /// No-op silencieux si `urlString` n'est pas une URL valide.
    static func open(_ urlString: String) {
        guard let parsed = URL(string: urlString) else { return }
        NSWorkspace.shared.open(rewriteToMSTeams(parsed) ?? parsed)
        NotificationCenter.default.post(name: didJoinNotification, object: nil)
    }

    /// Réécrit `https://teams.microsoft.com/l/meetup-join/...` en
    /// `msteams:/l/meetup-join/...` pour que l'app desktop la prenne en charge.
    /// Retourne l'URL telle quelle si elle est déjà en scheme `msteams`,
    /// ou `nil` si ce n'est pas une URL de jonction de réunion Teams.
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
