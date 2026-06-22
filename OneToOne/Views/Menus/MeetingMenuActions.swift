import SwiftUI

/// Identifiants des items de menu réunion, pour piloter leur activation.
enum MeetingMenuItem {
    case startStopRecording, appendRecording, pause, generateReport, retranscribe,
         customPrompt, importCalendar, importWAV, editAudio, revealWAV, delete,
         exportMarkdown, exportPDF, exportMail, exportOutlook, exportNotes
}

/// Source de vérité unique des actions « secondaires » d'une réunion, partagée
/// entre le menu « ⋯ » in-window (`MeetingTopChromeBar`) et les menus natifs
/// macOS (`MeetingCommands` via `FocusedValue`).
///
/// Valeur reconstruite à chaque rendu de `MeetingView` : les closures capturent
/// l'état courant de la vue ; les drapeaux pilotent `isEnabled(_:)`.
struct MeetingMenuActions {
    /// Titre de la réunion (pour l'affichage éventuel dans les menus, ex. en-tête).
    var meetingTitle: String

    // État courant. Sert à `isEnabled(_:)` ET aux libellés dynamiques des menus :
    // `isRecording` → « Démarrer l'enregistrement » / « Arrêter et transcrire »,
    // `isPaused` → « Mettre en pause » / « Reprendre » (lus par MeetingCommands).
    var isRecording: Bool
    var isPaused: Bool
    var isTranscribing: Bool
    var isGeneratingReport: Bool
    var hasWav: Bool
    var hasPlayableAudio: Bool
    var hasReport: Bool
    var hasTranscript: Bool

    // Actions — enregistrement / rapport
    var startRecording: () -> Void
    var stopRecording: () -> Void
    var appendRecording: () -> Void
    var togglePause: () -> Void
    var retranscribe: () -> Void
    var generateReport: () -> Void
    var toggleCustomPrompt: () -> Void

    // Actions — import / audio / suppression
    var importCalendar: () -> Void
    var importExistingWAV: () -> Void
    var editAudio: () -> Void
    var revealWAV: () -> Void
    var deleteMeeting: () -> Void

    // Actions — export
    var exportMarkdown: () -> Void
    var exportPDF: () -> Void
    var exportMail: (MeetingMailExportOptions) -> Void
    var exportOutlook: (MeetingMailExportOptions) -> Void
    var exportAppleNotes: (MeetingMailExportOptions) -> Void

    /// Occupé par une opération longue (enreg./transcription/rapport).
    var busy: Bool { isRecording || isTranscribing || isGeneratingReport }

    /// Item activable dans l'état courant.
    func isEnabled(_ item: MeetingMenuItem) -> Bool {
        switch item {
        case .startStopRecording: return !isTranscribing && !isGeneratingReport
        case .appendRecording:    return hasWav && !busy
        case .pause:              return isRecording
        case .generateReport:     return hasTranscript && !busy
        case .retranscribe:       return hasWav && !isTranscribing
        case .customPrompt:       return true
        case .importCalendar:     return true
        case .importWAV:          return !busy
        case .editAudio:          return hasPlayableAudio && !busy
        case .revealWAV:          return hasPlayableAudio  // lecture seule → ok même si occupé
        case .delete:             return true
        case .exportMarkdown, .exportPDF, .exportMail, .exportOutlook, .exportNotes:
            return hasReport
        }
    }
}

// MARK: - FocusedValue plumbing

struct MeetingMenuActionsKey: FocusedValueKey {
    typealias Value = MeetingMenuActions
}

extension FocusedValues {
    /// Actions de la réunion ayant le focus (nil si aucune).
    var meetingMenu: MeetingMenuActions? {
        get { self[MeetingMenuActionsKey.self] }
        set { self[MeetingMenuActionsKey.self] = newValue }
    }
}
