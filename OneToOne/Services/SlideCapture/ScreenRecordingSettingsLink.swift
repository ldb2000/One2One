import AppKit
import Foundation

/// Ouvre la section « Enregistrement de l'écran » des Réglages Système.
///
/// Sur macOS 13+, l'ancien identifiant `com.apple.preference.security` ouvre les Réglages
/// sans forcément naviguer jusqu'à la bonne section ; l'extension moderne
/// `com.apple.settings.PrivacySecurity.extension` porte l'ancre `Privacy_ScreenCapture`.
/// On essaie donc le moderne, puis l'historique, et en dernier recours l'interface
/// affiche `manualPath`. C'est souvent l'unique bouton du seul écran bloquant : il ne
/// doit pas pouvoir être sans effet.
enum ScreenRecordingSettingsLink {

    static let candidateURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!,
    ]

    static let manualPath = "Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran"

    /// Essaie chaque URL dans l'ordre ; `true` dès qu'une ouverture est acceptée.
    @MainActor
    static func open(using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        for url in candidateURLs where opener(url) {
            return true
        }
        return false
    }
}
