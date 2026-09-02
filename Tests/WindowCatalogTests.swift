import Testing
import CoreGraphics
@testable import OneToOne

@Suite("WindowCatalog")
struct WindowCatalogTests {

    private func window(_ id: CGWindowID, _ title: String, _ app: String, _ bundle: String?, w: CGFloat, h: CGFloat) -> ShareableWindow {
        ShareableWindow(id: id, title: title, appName: app, bundleIdentifier: bundle, frame: CGRect(x: 0, y: 0, width: w, height: h))
    }

    @Test("Teams, Zoom et Meet passent devant, puis surface décroissante")
    func meetingAppsFirstThenArea() {
        let windows = [
            window(1, "Notes", "Notes", "com.apple.Notes", w: 1600, h: 1000),
            window(2, "Réunion", "Microsoft Teams", "com.microsoft.teams2", w: 800, h: 600),
            window(3, "Meet – Point hebdo", "Google Chrome", "com.google.Chrome", w: 900, h: 600),
            window(4, "Zoom Meeting", "zoom.us", "us.zoom.xos", w: 1000, h: 700),
            window(5, "Mail", "Mail", "com.apple.mail", w: 1200, h: 800),
        ]
        let sorted = WindowCatalog.prioritized(windows).map(\.id)
        #expect(sorted == [4, 3, 2, 1, 5])
    }

    @Test("les fenêtres de OneToOne, la liste noire, les petites et les sans-titre sont écartées")
    func filtering() {
        let windows = [
            window(1, "Réunion", "OneToOne", "com.onetoone.app", w: 1000, h: 800),
            window(2, "Réunion", "Microsoft Teams", "com.microsoft.teams2", w: 1000, h: 800),
            window(3, "Palette", "Microsoft Teams", "com.microsoft.teams2", w: 199, h: 800),
            window(4, "", "Microsoft Teams", "com.microsoft.teams2", w: 1000, h: 800),
            window(5, "Slack", "Slack", "com.tinyspeck.slackmacgap", w: 1000, h: 800),
        ]
        let kept = WindowCatalog.filtered(windows, excludingAppNames: ["slack"]).map(\.id)
        #expect(kept == [2])
    }

    @Test("le nom affiché combine application et titre, ou l'application seule")
    func displayName() {
        #expect(window(1, "Hebdo", "Microsoft Teams", nil, w: 1, h: 1).displayName == "Microsoft Teams — Hebdo")
        #expect(window(2, "", "Safari", nil, w: 1, h: 1).displayName == "Safari")
    }
}
