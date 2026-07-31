import Foundation
import SwiftData

/// Thème (« tag ») de réunion : étiquette libre, colorée, partagée par plusieurs
/// réunions. Transverse au projet, au type (`MeetingKind`) et aux participants.
///
/// Relation many-to-many avec `Meeting`, `.nullify` des deux côtés : supprimer un
/// thème le retire des réunions (jamais l'inverse) et supprimer une réunion la
/// retire des thèmes.
@Model
final class MeetingTag {
    /// UUID stable exposable hors SwiftData. Optionnel volontairement : un
    /// `UUID` non-optionnel avec valeur par défaut casse la lightweight
    /// migration (même défaut appliqué à toutes les lignes existantes).
    var stableID: UUID? = nil
    var name: String = ""
    /// Couleur `#RRGGBB` (cf. `Color(hex:)` / `toHex()`), issue par défaut de
    /// `TagColorPalette`.
    var colorHex: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Meeting.tags)
    var meetings: [Meeting] = []

    init(name: String, colorHex: String? = nil) {
        self.stableID = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = colorHex ?? TagColorPalette.hex(for: name)
        self.createdAt = Date()
    }

    /// Renvoie `stableID`, en le backfillant si la ligne date d'avant le passage
    /// en Optional. Persiste immédiatement le backfill.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

// MARK: - Unicité applicative & fusion

extension MeetingTag {

    /// Clé de comparaison des noms : insensible à la casse, aux accents et aux
    /// espaces de bord. L'unicité des noms est garantie applicativement
    /// (`findOrCreate`), SwiftData n'offrant pas de contrainte d'unicité ici.
    static func normalizedKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Cherche un thème existant par nom (casse/accents ignorés), archivé compris.
    static func find(name: String, in context: ModelContext) -> MeetingTag? {
        let key = normalizedKey(name)
        guard !key.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<MeetingTag>())) ?? []
        return all.first { normalizedKey($0.name) == key }
    }

    /// Renvoie le thème portant ce nom, en le créant (couleur déterministe) s'il
    /// n'existe pas. `nil` si le nom est vide une fois trimé.
    @discardableResult
    static func findOrCreate(name: String, in context: ModelContext) -> MeetingTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = find(name: trimmed, in: context) { return existing }
        let tag = MeetingTag(name: trimmed)
        context.insert(tag)
        return tag
    }

    /// Fusionne `source` dans `target` : toutes les réunions du thème source
    /// sont réaffectées au thème cible (sans doublon), puis le source est
    /// supprimé. No-op si les deux thèmes sont le même.
    static func merge(source: MeetingTag, into target: MeetingTag, in context: ModelContext) {
        guard source.persistentModelID != target.persistentModelID else { return }
        for meeting in source.meetings {
            if !meeting.tags.contains(where: { $0.persistentModelID == target.persistentModelID }) {
                meeting.tags.append(target)
            }
            meeting.tags.removeAll { $0.persistentModelID == source.persistentModelID }
        }
        context.delete(source)
    }
}
