import SwiftUI

/// Couleur et initiales d'un avatar, dérivées du nom.
///
/// **Le hachage est calculé à la main, et c'est délibéré.** `hashValue` est
/// salé au démarrage du processus : la couleur d'une même personne changerait
/// à chaque lancement, ce que le critère d'acceptation de la spec interdit.
/// La somme pondérée ci-dessous ne dépend que du texte, donc elle est figée —
/// un test l'épingle sur des valeurs écrites en dur, pour qu'une « optimisation »
/// du calcul ne repeigne pas silencieusement tous les avatars.
enum AvatarPalette {

    /// Les cinq paires fond/texte de la spec.
    static let pairs: [(fond: Color, texte: Color)] = [
        (hex(0xDFE7F6), hex(0x3A5C92)),
        (hex(0xF4E3D3), hex(0x8A5C2E)),
        (hex(0xDCECDF), hex(0x37704F)),
        (hex(0xE8E1F7), hex(0x5B46A0)),
        (hex(0xF6DFE3), hex(0x8E3D4C))
    ]

    static var pairCount: Int { pairs.count }

    /// Rang de la paire attribuée à cette identité.
    static func slot(for identity: String) -> Int {
        var somme = 0
        for scalar in identity.unicodeScalars {
            somme = (somme &* 31 &+ Int(scalar.value)) % 1_000_003
        }
        return abs(somme) % pairs.count
    }

    static func pair(for identity: String) -> (fond: Color, texte: Color) {
        pairs[slot(for: identity)]
    }

    /// Première lettre de deux mots au plus. `?` quand il n'y a rien à lire.
    static func initials(for name: String) -> String {
        // Découpage sur l'espace seul : « Jean-Baptiste ORSET » donne « JO »,
        // pas « JB » — un prénom composé reste un prénom.
        let mots = name.split(separator: " ", omittingEmptySubsequences: true)
        let lettres = mots.prefix(2).compactMap { $0.first }.map(String.init)
        return lettres.isEmpty ? "?" : lettres.joined().uppercased()
    }

    private static func hex(_ rgb: Int) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
}
