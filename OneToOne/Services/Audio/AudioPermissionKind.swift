import Foundation

/// Ce qui a été refusé, et donc quel volet des Réglages Système ouvrir. Porte
/// aussi les textes de la feuille d'aide : ils dépendent du cas, pas de l'écran.
enum AudioPermissionKind: String, Identifiable, Sendable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Accès au micro refusé"
        case .systemAudio: return "Audio système non autorisé"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            return "OneToOne n'est pas autorisé à utiliser le micro. Sans cette autorisation, aucun enregistrement ne peut démarrer."
        case .systemAudio:
            return "Capter les participants distants passe par l'enregistrement de l'écran (audio seul, aucune image n'est conservée). L'enregistrement continue avec le micro seul tant que l'autorisation manque."
        }
    }

    var manualPath: String {
        switch self {
        case .microphone: return MicrophoneSettingsLink.manualPath
        case .systemAudio: return ScreenRecordingSettingsLink.manualPath
        }
    }

    var candidateURLs: [URL] {
        switch self {
        case .microphone: return MicrophoneSettingsLink.candidateURLs
        case .systemAudio: return ScreenRecordingSettingsLink.candidateURLs
        }
    }

    @MainActor
    func openSettings() -> Bool {
        switch self {
        case .microphone: return MicrophoneSettingsLink.open()
        case .systemAudio: return ScreenRecordingSettingsLink.open()
        }
    }
}
