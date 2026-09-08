import Foundation
import Observation

/// Les deux raccourcis **globaux** de la capture en séance (spec §1.4, §5.4) :
/// `⌘⇧S` capture la source configurée, `⌘⇧N` ouvre un champ de note au timecode courant.
///
/// Ils passent par `GlobalHotkeyService` (Carbon `RegisterEventHotKey`, signature
/// `ONET`) et non par `.keyboardShortcut` : ils doivent fonctionner alors que Teams est
/// au premier plan, ce qu'un raccourci de menu SwiftUI ne peut pas faire.
struct CaptureHotkey: Equatable, Sendable {

    let spec: HotkeySpec
    /// La notation telle qu'elle est écrite dans la spec et dans la maquette (`⌘⇧S`).
    ///
    /// Elle n'est **pas** dérivée de `HotkeySpec.serialized`, qui sérialise dans l'ordre
    /// canonique `⌃⌥⇧⌘` et rendrait `⇧⌘S` : l'utilisateur lit `⌘⇧S` partout ailleurs
    /// dans l'application, et deux notations pour un même raccourci se lisent comme deux
    /// raccourcis.
    let label: String

    /// `⌘⇧S` — capture la source configurée.
    static let capture = CaptureHotkey(
        spec: HotkeySpec(modifiers: [.command, .shift], keyChar: "S"), label: "⌘⇧S")

    /// `⌘⇧N` — nouvelle ligne de note au timecode courant.
    static let note = CaptureHotkey(
        spec: HotkeySpec(modifiers: [.command, .shift], keyChar: "N"), label: "⌘⇧N")

    static var all: [CaptureHotkey] { [.capture, .note] }

    /// Ce que les réglages affichent quand l'enregistrement échoue.
    ///
    /// `RegisterEventHotKey` ne rend qu'un code d'erreur, et la cause de loin la plus
    /// fréquente est qu'une autre application détient déjà la combinaison. Un raccourci
    /// silencieusement mort est indétectable : c'est la leçon de
    /// `Teams-Capture/Sources/TeamsCapture/GlobalHotKey.swift`, et elle vaut un message.
    var failureMessage: String {
        "\(label) est déjà utilisé par une autre application."
    }
}

/// Les échecs d'enregistrement des raccourcis globaux, pour que les réglages les disent.
///
/// Observable et global parce que l'enregistrement se fait au lancement
/// (`registerHotkeys()`), hors de la fenêtre de réglages — qui peut n'être ouverte que
/// bien plus tard, ou jamais.
@MainActor
@Observable
final class CaptureHotkeyFailures {

    static let shared = CaptureHotkeyFailures()

    /// Les raccourcis dont le dernier enregistrement a échoué, par notation (`⌘⇧S`).
    private(set) var failed: Set<String> = []

    init() {}

    /// Consigne le résultat d'un enregistrement.
    ///
    /// Le succès **efface** l'échec précédent : un message d'erreur qui ne s'effacerait
    /// jamais est le piège 14 de `One2One-specs.md` (« message d'erreur jamais effacé »),
    /// et il se déclenche ici dès qu'on décoche puis recoche la case.
    func record(_ hotkey: CaptureHotkey, succeeded: Bool) {
        if succeeded {
            failed.remove(hotkey.label)
        } else {
            failed.insert(hotkey.label)
        }
    }

    /// Un raccourci désactivé n'a pas d'échec à afficher : c'est un choix, pas une panne.
    func forget(_ hotkey: CaptureHotkey) {
        failed.remove(hotkey.label)
    }

    /// Le message à afficher pour ce raccourci, `nil` quand tout va bien.
    func message(for hotkey: CaptureHotkey) -> String? {
        failed.contains(hotkey.label) ? hotkey.failureMessage : nil
    }
}
