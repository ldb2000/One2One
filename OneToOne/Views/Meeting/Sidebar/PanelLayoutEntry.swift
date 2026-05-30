import Foundation

/// Entrée du layout sidebar — id + visibility. Sérialisé en JSON dans
/// `AppSettings.rightSidebarLayoutJSON`.
struct PanelLayoutEntry: Codable, Identifiable, Equatable {
    let id: RightSidebarPanelID
    var visible: Bool

    /// Layout par défaut : tous les panels dans l'ordre `RightSidebarPanelID.allCases`,
    /// tous visibles.
    static var defaultLayout: [PanelLayoutEntry] {
        RightSidebarPanelID.allCases.map { PanelLayoutEntry(id: $0, visible: true) }
    }

    /// Encode un array en JSON pour persistance. Renvoie `""` si l'encodage
    /// échoue (sera détecté comme empty et fallback au default au prochain decode).
    static func encode(_ entries: [PanelLayoutEntry]) -> String {
        guard let data = try? JSONEncoder().encode(entries),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Décode le JSON stocké. Fallback `defaultLayout` si :
    /// - le JSON est vide ou corrompu
    /// - aucun case enum trouvé
    /// Migration : si un case enum a été ajouté après la sauvegarde, on
    /// l'ajoute en queue avec visible:true (ordre des présents préservé).
    static func decode(_ json: String) -> [PanelLayoutEntry] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PanelLayoutEntry].self, from: data),
              !decoded.isEmpty else {
            return defaultLayout
        }

        let presentIDs = Set(decoded.map(\.id))
        let missing = RightSidebarPanelID.allCases
            .filter { !presentIDs.contains($0) }
            .map { PanelLayoutEntry(id: $0, visible: true) }
        return decoded + missing
    }
}
