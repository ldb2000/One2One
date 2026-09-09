import SwiftUI

/// Les raccourcis clavier de l'application — **une** déclaration par
/// combinaison, et le seul endroit où la combinaison est épelée.
///
/// La table s'appelait « raccourcis de l'écran de réunion » et ne couvrait
/// que la spec §1.4. La décision **D1** de la refonte de la gestion des
/// projets l'a élargie : `⌘K` va désormais à la **palette**, qui s'ouvre
/// depuis n'importe quel écran, et l'assistant de réunion passe à `⌘⇧K`
/// (ADR `docs/adr/2026-09-09-palette-commande-k.md`). Un raccourci de portée
/// application ne pouvait plus s'appeler « raccourci de réunion ».
///
/// Trois surfaces, parce que trois mécanismes distincts portent ces gestes :
/// - `.menu` : un item de `MeetingCommands`, qui lit `key` et `modifiers` ici ;
/// - `.vue` : un `keyboardShortcut` local, quand le geste a besoin d'un
///   contexte que le menu n'a pas (la phrase survolée, le champ à focaliser) ;
/// - `.global` : un raccourci système Carbon (`CaptureHotkeys`, lot 8), actif
///   même quand l'application n'a pas le focus.
///
/// `Tests/AppShortcutsTests.swift` vérifie que la table couvre les specs,
/// qu'aucune combinaison n'y figure deux fois, que `MeetingCommands` prend bien
/// ses raccourcis ici, que la feuille d'aide la rend sans en tenir une seconde,
/// et qu'aucun second déclarant n'apparaît dans les vues sans être nommé.
enum AppShortcut: String, CaseIterable, Sendable {
    /// `⌘K` — la palette de commandes (projets et actions), décision **D1**.
    /// Le seul raccourci de cette table qui n'ait rien à voir avec une
    /// réunion : il est actif partout, y compris sans réunion ouverte.
    case palette
    case assistant
    case marqueur
    case actionDepuisSelection
    case capture
    case note
    case collerRessource
    case validerComposeur
    case seancePleinEcran

    /// Là où la combinaison est réellement déclarée.
    enum Surface: Sendable {
        /// Item de menu natif : `MeetingCommands` en tire touche et modificateurs.
        case menu(MeetingMenuItem)
        /// Raccourci local d'une vue, avec son chemin sous `OneToOne/`.
        case vue(String)
    }

    /// Le jeton affiché : celui de la première colonne de la table §1.4.
    var jeton: String {
        switch self {
        case .palette:               return "⌘K"
        case .assistant:             return "⌘⇧K"
        case .marqueur:              return "⌘M"
        case .actionDepuisSelection: return "⌘⇧A"
        case .capture:               return "⌘⇧S"
        case .note:                  return "⌘⇧N"
        case .collerRessource:       return "⌘⇧V"
        case .validerComposeur:      return "⌘⏎"
        case .seancePleinEcran:      return "⌃⌘F"
        }
    }

    /// L'effet, dans les mots de la spec §1.4.
    var libelle: String {
        switch self {
        case .palette:
            return "Palette — projets et actions, depuis n'importe quel écran"
        case .assistant:
            return "Assistant — barre d'invocation, contexte = réunion courante"
        case .marqueur:
            return "Marqueur sur l'axe temps à l'instant courant"
        case .actionDepuisSelection:
            return "Créer une action depuis la sélection"
        case .capture:
            return "Capture d'écran de la source configurée"
        case .note:
            return "Nouvelle ligne de note au timecode courant"
        case .collerRessource:
            return "Coller un lien ou une image dans les ressources"
        case .validerComposeur:
            return "Valider le composeur (action, engagement, sujet d'ordre du jour)"
        case .seancePleinEcran:
            return "Mode séance plein écran"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .palette:               return "k"
        case .assistant:             return "k"
        case .marqueur:              return "m"
        case .actionDepuisSelection: return "a"
        case .capture:               return "s"
        case .note:                  return "n"
        case .collerRessource:       return "v"
        case .validerComposeur:      return .return
        case .seancePleinEcran:      return "f"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .palette, .marqueur, .validerComposeur:
            return .command
        case .assistant, .actionDepuisSelection, .capture, .note, .collerRessource:
            return [.command, .shift]
        case .seancePleinEcran:
            // `⌃⌘F` et non `⌘F`, qui reste la recherche (spec §2.6).
            return [.control, .command]
        }
    }

    var surface: Surface {
        switch self {
        case .palette:          return .menu(.palette)
        case .assistant:        return .menu(.assistant)
        case .marqueur:         return .menu(.marker)
        case .collerRessource:  return .menu(.pasteResource)
        case .capture:          return .menu(.captureNow)
        case .seancePleinEcran: return .menu(.sessionFullscreen)
        // Trois gestes qui ne peuvent pas venir d'un menu : ils ont besoin
        // d'un contexte que le menu ignore — la phrase de transcription
        // survolée, le composeur à focaliser, le composeur à valider.
        case .actionDepuisSelection:
            return .vue("Views/Meeting/Spaces/Transcript/TranscriptColumn.swift")
        case .note:
            return .vue("Views/Meeting/Spaces/Notes/NoteComposer.swift")
        case .validerComposeur:
            return .vue("Views/Meeting/Spaces/Rail/ActionComposer.swift")
        }
    }

    /// Ce que la feuille d'aide ajoute au libellé : la précision qui évite un
    /// ticket. Renseignée seulement quand il y a une surprise à annoncer.
    var note: String? {
        switch self {
        case .capture:
            return "Aussi en raccourci système, si la case est cochée dans les réglages. "
                 + "À la première utilisation, ouvre le sélecteur de source."
        case .note:
            return "Depuis la pastille flottante aussi, en raccourci système."
        case .validerComposeur:
            return "Le menu Réunion emploie ⌘⏎ pour « Générer le rapport » et un menu natif "
                 + "l'emporte : les composeurs interceptent la touche eux-mêmes."
        case .actionDepuisSelection:
            return "Sur la phrase de transcription survolée."
        case .palette:
            return "Le seul raccourci actif hors réunion : la palette s'ouvre "
                 + "depuis n'importe quel écran de la fenêtre principale."
        case .assistant:
            return "`⌘⇧K` et non `⌘K` depuis le 2026-09-09 : la palette a pris "
                 + "la combinaison (décision D1 de la refonte des projets)."
        case .marqueur, .collerRessource, .seancePleinEcran:
            return nil
        }
    }

    /// Les combinaisons déclarées plus d'une fois dans la table. Vide attendu.
    static func doublons() -> [String] {
        var vus: Set<String> = []
        var doubles: [String] = []
        for raccourci in allCases where !vus.insert(raccourci.jeton).inserted {
            doubles.append(raccourci.jeton)
        }
        return doubles
    }
}

extension View {
    /// Pose un raccourci de la table. Le seul chemin autorisé pour les neuf
    /// combinaisons qu'elle déclare.
    func appShortcut(_ raccourci: AppShortcut) -> some View {
        keyboardShortcut(raccourci.key, modifiers: raccourci.modifiers)
    }
}
