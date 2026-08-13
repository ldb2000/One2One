import Foundation

/// Les points de préparation d'un 1:1, lus dans le markdown de `prepNotes`.
///
/// Ils y vivent sous forme de cases GFM (`- [ ]`) — c'est déjà ce que
/// l'éditeur de l'app écrit. Aucun modèle nouveau : la préparation reste du
/// texte, et le bloc de la fiche n'en est qu'une vue.
enum PrepChecklist {

    struct Item: Equatable {
        let text: String
        let done: Bool
        /// Rang de la case parmi les cases — pas parmi les lignes.
        let index: Int
    }

    private static func isBox(_ ligne: Substring) -> (done: Bool, texte: String)? {
        let t = ligne.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("- [") , t.count > 5 else { return nil }
        let marque = t[t.index(t.startIndex, offsetBy: 3)]
        guard marque == " " || marque.lowercased() == "x",
              t[t.index(t.startIndex, offsetBy: 4)] == "]" else { return nil }
        let texte = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return (marque != " ", texte)
    }

    static func items(from markdown: String) -> [Item] {
        var rang = 0
        return markdown.split(separator: "\n", omittingEmptySubsequences: false).compactMap { ligne in
            guard let boite = isBox(ligne) else { return nil }
            defer { rang += 1 }
            return Item(text: boite.texte, done: boite.done, index: rang)
        }
    }

    /// « 4 points sur 6 », ou `nil` quand la préparation ne porte aucune case.
    static func progress(from markdown: String) -> String? {
        let points = items(from: markdown)
        guard !points.isEmpty else { return nil }
        return "\(points.filter(\.done).count) points sur \(points.count)"
    }

    /// Coche ou décoche la case de rang `index`, en laissant le reste du
    /// markdown intact — la préparation peut contenir du texte libre.
    static func toggled(_ markdown: String, at index: Int) -> String {
        var rang = 0
        let lignes = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { ligne -> String in
            guard let boite = isBox(ligne) else { return String(ligne) }
            defer { rang += 1 }
            guard rang == index else { return String(ligne) }
            let marque = boite.done ? " " : "x"
            return ligne.replacingOccurrences(of: boite.done ? "- [x]" : "- [ ]",
                                              with: "- [\(marque)]",
                                              options: [.caseInsensitive])
        }
        return lignes.joined(separator: "\n")
    }
}
