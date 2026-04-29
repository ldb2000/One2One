import Foundation

/// Spécification d'un raccourci clavier global, sérialisable en chaîne
/// lisible humainement (ex. `"⌃⌥⌘A"`, `"⌘F1"`).
///
/// Utilisé pour stocker les bindings dans `AppSettings.collaboratorHotkeys`
/// et pour communiquer avec `GlobalHotkeyService` qui traduit vers Carbon.
struct HotkeySpec: Equatable, Hashable {

    enum Modifier: String, CaseIterable {
        case control = "⌃"
        case option  = "⌥"
        case shift   = "⇧"
        case command = "⌘"

        /// Ordre canonique d'affichage / sérialisation: ⌃⌥⇧⌘
        static let canonicalOrder: [Modifier] = [.control, .option, .shift, .command]
    }

    let modifiers: Set<Modifier>
    /// Touche imprimable normalisée majuscule (`"A"`, `"1"`) ou nom de
    /// touche fonction (`"F1"`...`"F19"`).
    let keyChar: String

    /// Représentation canonique sérialisée.
    var serialized: String {
        let mods = Modifier.canonicalOrder.filter { modifiers.contains($0) }
        return mods.map(\.rawValue).joined() + keyChar
    }

    init(modifiers: Set<Modifier>, keyChar: String) {
        self.modifiers = modifiers
        self.keyChar = keyChar.uppercased()
    }

    init?(serialized: String) {
        guard !serialized.isEmpty else { return nil }
        var mods: Set<Modifier> = []
        var rest = serialized
        for mod in Modifier.canonicalOrder {
            if rest.hasPrefix(mod.rawValue) {
                mods.insert(mod)
                rest.removeFirst(mod.rawValue.count)
            }
        }
        guard !mods.isEmpty, !rest.isEmpty else { return nil }
        self.modifiers = mods
        self.keyChar = rest.uppercased()
    }
}
