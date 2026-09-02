import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Fournit l'état courant d'une source d'images.
protocol FrameSource: Sendable {
    /// Capture l'état courant. Retourne `nil` si la source a **disparu** (fenêtre
    /// fermée, application quittée) : l'appelant met la session en pause. Lève une
    /// erreur sur tout **échec** d'API : visible, sans arrêter la session. Aucune
    /// implémentation ne doit convertir un échec en `nil`.
    func captureFrame() async throws -> CGImage?
}

/// Une fenêtre proposée à l'utilisateur comme source de capture.
struct ShareableWindow: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleIdentifier: String?
    let frame: CGRect

    init(id: CGWindowID, title: String, appName: String, bundleIdentifier: String?, frame: CGRect) {
        self.id = id
        self.title = title
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
    }

    /// Identifiants des applications de réunion à placer en tête.
    static let meetingBundleIdentifiers: Set<String> = [
        "com.microsoft.teams2", "com.microsoft.teams", "us.zoom.xos"
    ]

    /// Teams, Zoom, ou un onglet Google Meet (Meet vit dans un navigateur : on
    /// reconnaît le titre).
    var isMeetingApp: Bool {
        if let bundleIdentifier, ShareableWindow.meetingBundleIdentifiers.contains(bundleIdentifier) { return true }
        return title.localizedCaseInsensitiveContains("meet")
    }

    var displayName: String {
        title.isEmpty ? appName : "\(appName) — \(title)"
    }
}

enum SlideCaptureError: Error, Equatable, LocalizedError {
    case screenRecordingDenied
    case noShareableWindows
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "OneToOne n'a pas l'autorisation d'enregistrer l'écran."
        case .noShareableWindows:
            return "Aucune fenêtre partageable n'a été trouvée."
        case .captureFailed(let reason):
            return "La capture a échoué : \(reason)"
        }
    }

    /// Vrai si l'erreur correspond à un refus d'autorisation d'enregistrement d'écran.
    /// Fonction pure : le domaine **et** le code sont exigés (le même code dans un autre
    /// domaine n'est pas un refus).
    static func isPermissionDenial(_ error: any Error) -> Bool {
        if let captureError = error as? SlideCaptureError {
            return captureError == .screenRecordingDenied
        }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }
}
