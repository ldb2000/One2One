import Foundation

/// Nom de fichier proposé par `NSSavePanel`. Pur, donc testable : un nom qui
/// contient un `/` fait échouer l'enregistrement sans message.
enum WorkshopExport {

    static func fileName(board: Board, extension ext: String) -> String {
        let base = board.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titre = base.isEmpty ? BoardOrdering.defaultTitle(forIndex: board.index) : base
        return "\(sanitized(titre)).\(ext)"
    }

    /// Remplace ce qu'un nom de fichier macOS n'accepte pas, puis rabat les
    /// tirets consecutifs et les bords : « Flux / DMZ » donne « Flux - DMZ »,
    /// et un titre fait **uniquement** de caracteres interdits ne donne pas
    /// « --- » mais le repli.
    static func sanitized(_ titre: String) -> String {
        let interdits = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        var propre = titre.components(separatedBy: interdits).joined(separator: "-")
        while propre.contains("--") {
            propre = propre.replacingOccurrences(of: "--", with: "-")
        }
        propre = propre.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return propre.isEmpty ? "Planche" : propre
    }
}
