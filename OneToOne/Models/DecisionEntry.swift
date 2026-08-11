import Foundation

/// Une décision prise en séance, et son état de solde.
///
/// Une décision est un **engagement** : quelque chose de promis de vive voix,
/// devant quelqu'un. Elle doit donc pouvoir être soldée — sans quoi le
/// compteur d'engagements de la fiche collaborateur ne redescendrait jamais,
/// et cesserait d'être lu.
///
/// Elle n'était qu'une chaîne dans `Meeting.decisionsJSON`, sans identité ni
/// état. La colonne accueille désormais **les deux formes** :
///
/// - `["texte"]` — écrite par tout ce qui existait avant, et par toute
///   version antérieure du dépôt ;
/// - `[{"text": "texte", "settledAt": "…"}]` — la forme qui porte l'état.
///
/// Aucune migration : c'est le décodeur qui accepte les deux, et l'écriture
/// qui fait passer une colonne à la forme riche au premier solde. Une
/// sauvegarde ancienne se relit donc telle quelle.
struct DecisionEntry: Codable, Equatable, Identifiable {
    var text: String
    /// Date à laquelle l'engagement a été soldé — coché, ou explicitement
    /// repris. `nil` tant qu'il traîne.
    var settledAt: Date?

    var id: String { text }

    init(text: String, settledAt: Date? = nil) {
        self.text = text
        self.settledAt = settledAt
    }

    /// Accepte la forme historique (une simple chaîne) comme la forme riche.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self.init(text: text)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try c.decode(String.self, forKey: .text),
                  settledAt: try c.decodeIfPresent(Date.self, forKey: .settledAt))
    }
}
