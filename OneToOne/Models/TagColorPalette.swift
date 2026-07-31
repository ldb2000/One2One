import Foundation

/// Palette fixe utilisée pour colorer les thèmes de réunion (`MeetingTag`).
///
/// Le choix est **déterministe** : un même nom de thème donne toujours la même
/// couleur, sans rien demander à l'utilisateur (qui peut ensuite la changer via
/// la gestion des thèmes). Le hash est un FNV-1a maison — `String.hashValue`
/// est randomisé à chaque lancement du process et ne conviendrait pas.
enum TagColorPalette {

    /// Teintes moyennes, lisibles en clair comme en sombre une fois désaturées
    /// en fond de chip.
    static let hexes: [String] = [
        "#E57373",  // rouge
        "#F06292",  // rose
        "#BA68C8",  // violet
        "#7986CB",  // indigo
        "#4FC3F7",  // bleu
        "#4DB6AC",  // sarcelle
        "#81C784",  // vert
        "#DCE775",  // lime
        "#FFB74D",  // orange
        "#A1887F"   // taupe
    ]

    /// Couleur `#RRGGBB` associée au nom, stable entre deux lancements.
    /// Les variantes de casse/accents d'un même nom partagent la couleur.
    static func hex(for name: String) -> String {
        hexes[index(for: name)]
    }

    /// Index dans `hexes`, toujours dans les bornes de la palette.
    static func index(for name: String) -> Int {
        let key = MeetingTag.normalizedKey(name)
        guard !key.isEmpty else { return 0 }
        return Int(fnv1a(key) % UInt64(hexes.count))
    }

    /// FNV-1a 64 bits sur les octets UTF-8 — hash stable, sans dépendance.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
