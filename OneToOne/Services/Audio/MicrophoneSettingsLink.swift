import AppKit
import Foundation

/// Ouvre la section « Microphone » des Réglages Système. Même mécanisme que
/// `ScreenRecordingSettingsLink` : identifiant moderne puis historique, et un
/// chemin manuel si les deux échouent.
enum MicrophoneSettingsLink {

    static let candidateURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!,
    ]

    static let manualPath = "Réglages Système → Confidentialité et sécurité → Microphone"

    @MainActor
    static func open(using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        for url in candidateURLs where opener(url) {
            return true
        }
        return false
    }
}
