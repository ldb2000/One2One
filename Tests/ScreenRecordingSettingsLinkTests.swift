import Testing
import Foundation
@testable import OneToOne

@Suite("ScreenRecordingSettingsLink")
@MainActor
struct ScreenRecordingSettingsLinkTests {

    @Test("le panneau moderne est essayé d'abord, l'URL historique en repli")
    func candidateOrder() {
        let urls = ScreenRecordingSettingsLink.candidateURLs.map(\.absoluteString)
        #expect(urls == [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ])
    }

    @Test("open s'arrête à la première URL acceptée")
    func stopsAtFirstSuccess() {
        var tried: [String] = []
        let ok = ScreenRecordingSettingsLink.open { url in
            tried.append(url.absoluteString)
            return true
        }
        #expect(ok)
        #expect(tried.count == 1)
    }

    @Test("open essaie le repli puis rend false si tout échoue")
    func fallsBackThenFails() {
        var tried: [String] = []
        let ok = ScreenRecordingSettingsLink.open { url in
            tried.append(url.absoluteString)
            return false
        }
        #expect(!ok)
        #expect(tried.count == 2)
        #expect(ScreenRecordingSettingsLink.manualPath.contains("Enregistrement de l'écran"))
    }
}
