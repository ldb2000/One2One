import SwiftUI

/// Identifiants des items de menu réunion, pour piloter leur activation.
enum MeetingMenuItem {
    case startStopRecording, appendRecording, pause, generateReport, retranscribe,
         customPrompt, importCalendar, importWAV, editAudio, revealWAV, delete,
         exportMarkdown, exportPDF, exportMail, exportOutlook, exportNotes,
         /// `⌘⇧K` — l'assistant (spec §1.4, `⌘K` jusqu'au 2026-09-09).
         assistant,
         /// `⌘K` — la palette de commandes (décision **D1**).
         ///
         /// Le seul item de cette table qui ne soit pas une action de la
         /// réunion focalisée : la palette s'ouvre depuis n'importe quel
         /// écran. Il est ici parce que `AppShortcut.Surface.menu` désigne le
         /// mécanisme de déclaration — un item de `MeetingCommands` — et non
         /// une dépendance à une réunion. `MeetingCommands` ne pose donc
         /// **aucun** `.disabled` sur cet item.
         palette,
         /// `⌘M` — un marqueur sur l'axe temps (spec §1.4).
         marker,
         /// `⌃⌘F` — le mode séance plein écran (spec §2.6, lot 4).
         sessionFullscreen,
         /// `⌘⇧V` — coller un lien ou une image dans les ressources (spec §1.4).
         pasteResource,
         /// Ouvre le tiroir Ressources (spec §4.1).
         resources,
         /// `⌘⇧S` — capturer la source configurée (spec §1.4, lot 7).
         captureNow
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
    /// même règle (`MeetingTopChromeBar`, `MeetingSpaceRouting.spaces(for:)`,
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

    // Actions — assistant et axe temps (spec §1.4)
    /// `⌘K` : ouvre l'assistant sur la réunion courante.
    var openAssistant: () -> Void
    /// `⌘M` : pose un marqueur sur l'axe temps à l'instant courant.
    var addPlayheadMarker: () -> Void

    /// `⌃⌘F` : bascule le mode séance plein écran (spec §2.6).
    ///
    /// Valeur par défaut, et non un paramètre requis : le lot 4 ne modifie pas
    /// `MeetingView`, qui construit cette structure. La demande passe par
    /// `SessionFullscreenPresenter`, où l'écran de la réunion en cours s'est
    /// enregistré — le menu n'a besoin de connaître ni la réunion, ni sa
    /// fenêtre.
    var toggleSessionFullscreen: () -> Void = {
        MainActor.assumeIsolated { SessionFullscreenPresenter.shared.demanderBascule() }
    }

    // Actions — ressources (lot 6, spec §4.1 et §1.4)
    /// `⌘⇧V` : colle un lien ou une image du presse-papiers dans les
    /// ressources de la séance.
    var pasteResource: () -> Void
    /// Déplie le tiroir Ressources.
    var openResources: () -> Void

    // Action — capture (lot 7, spec §1.4 et §5.1)
    /// `⌘⇧S` : capture la source configurée. À la **première** utilisation, la
    /// source n'étant pas choisie, ouvre le sélecteur — c'est
    /// `CaptureState.shortcutOutcome` qui tranche, pas le menu.
    ///
    /// Valeur par défaut : `MeetingView` reste le seul appelant à la fournir,
    /// et les écrans qui construisent cette structure sans capture (aperçus,
    /// tests des lots 4 et 6) n'ont pas à la déclarer.
    var captureNow: () -> Void = {}

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
        .retranscribe, .importWAV, .editAudio, .revealWAV,
        // Un marqueur sans axe temps n'a pas d'ancre : une note n'a pas
        // d'audio. `assistant` reste actif — il est « partout » (spec §1.1).
        .marker,
        // Le mode séance est celui d'une réunion : une note n'a ni
        // transcription, ni participants, ni axe temps, et `MeetingView` lui
        // sert son éditeur markdown plutôt que `MeetingSpaceView` — il n'y a
        // donc même pas d'écran pour le présenter.
        .sessionFullscreen
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
        // L'assistant est une surface, pas un onglet : jamais grisé, même
        // pendant une génération — c'est souvent là qu'on l'interroge.
        case .assistant:          return true
        // Un marqueur exige un axe temps : enregistrement en cours, ou audio
        // relisible.
        case .marker:             return isRecording || hasPlayableAudio
        // Le plein écran ne dépend ni de l'audio ni du rapport : on y passe
        // pour prendre des notes. Le présentateur refuse de lui-même quand
        // aucun écran n'est en mesure de présenter — un item grisé selon
        // l'état d'un singleton ne serait pas vérifiable ici.
        case .sessionFullscreen:  return true
        // Le tiroir Ressources existe pour **tous** les types, note comprise :
        // `MeetingSpaceRouting.spaces(for:)` donne l'espace `Ressources` à la
        // note comme aux autres. Coller un lien dans une note est même l'usage
        // le plus courant du raccourci.
        case .pasteResource, .resources: return true
        // La capture ne dépend d'aucun audio : on capture un partage sans
        // enregistrer, et une note peut parfaitement porter une capture
        // d'écran. À la première utilisation, `⌘⇧S` ouvre le sélecteur plutôt
        // que de capturer au hasard (spec §5.1).
        case .captureNow: return true
        // La palette n'a pas besoin de réunion. `MeetingCommands` ne
        // l'interroge pas — un item grisé faute de réunion focalisée
        // annulerait tout l'intérêt de `⌘K` —, et cette réponse est là pour
        // que le `switch` reste total.
        case .palette: return true
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
