import Foundation

/// Dérivation de l'affichage d'une note à partir du `Meeting` sous-jacent.
/// Partagée par l'écran « Notes » (`AllNotesView`) et par la section Notes
/// des fiches (`NotesSection`) — deux mises en page différentes (l'une porte
/// une icône et une pastille de cible, l'autre non), une seule règle de
/// dérivation. Voir `NoteFactory.swift` pour la règle de domaine : une note
/// est un `Meeting` de kind `.note`.
extension Meeting {

    /// Titre d'une note tel qu'il s'affiche en liste : son titre s'il en a
    /// un, sinon la première ligne du corps, tronquée.
    var noteDisplayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let firstLine = liveNotes.split(separator: "\n").first.map(String.init) ?? ""
        let stripped = firstLine.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Sans titre" : String(stripped.prefix(60))
    }

    /// Aperçu du corps, sautant la première ligne quand elle sert déjà de
    /// titre (note sans titre propre : la 1ʳᵉ ligne du corps fait office de
    /// titre via `noteDisplayTitle`, l'aperçu ne doit pas la répéter).
    var notePreview: String {
        let lines = liveNotes.split(separator: "\n").map(String.init)
        let skipFirst = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let body = skipFirst ? lines.dropFirst() : ArraySlice(lines)
        return body.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
