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

    /// Type de la réunion affichée. Porté ici — et non réduit à un booléen —
    /// parce que c'est le vocabulaire déjà employé partout ailleurs pour la
    /// même règle (`MeetingTopChromeBar`, `MeetingView.visibleSections(for:)`,
    /// `MeetingStatsScope`) et parce qu'une restriction future propre à un
    /// autre kind n'exigera pas un drapeau de plus. Sans valeur par défaut :
    /// tout appelant doit déclarer le kind, c'est précisément l'oubli que
    /// cette correction répare.
    var kind: MeetingKind

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

    /// Une note est une réunion avec soi-même (`MeetingKind.note`) : ni audio,
    /// ni transcription, ni rapport.
    var isNote: Bool { kind == .note }

    /// Items sans objet sur une note : tout ce qui produit ou manipule de
    /// l'audio, une transcription ou un rapport. `MeetingView` masque déjà les
    /// onglets Transcription et Rapport d'une note ; laisser ces items actifs
    /// rendrait leur résultat invisible et ingérable (⌘⇧R enregistrait et
    /// transcrivait dans un `rawTranscript` qu'aucun écran n'affiche).
    /// Restent actifs : `customPrompt`, `importCalendar`, `delete` et les
    /// exports (ces derniers restent de toute façon liés à `hasReport`).
    private static let disabledForNote: Set<MeetingMenuItem> = [
        .startStopRecording, .appendRecording, .pause, .generateReport,
        .retranscribe, .importWAV, .editAudio, .revealWAV
    ]

    /// Item activable dans l'état courant.
    func isEnabled(_ item: MeetingMenuItem) -> Bool {
        if isNote && Self.disabledForNote.contains(item) { return false }
        switch item {
        case .startStopRecording: return !isTranscribing && !isGeneratingReport
        case .appendRecording:    return hasWav && !busy
        case .pause:              return isRecording
        case .generateReport:     return (hasTranscript || hasPlayableAudio) && !busy
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
