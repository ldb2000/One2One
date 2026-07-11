import Foundation

/// Entrée du layout dashboard — id + visibilité + taille en grille (colonnes ×
/// lignes). Sérialisé en JSON dans `AppSettings.rightSidebarLayoutJSON`.
struct PanelLayoutEntry: Codable, Identifiable, Equatable {
    let id: RightSidebarPanelID
    var visible: Bool
    /// Nombre de colonnes occupées (1…3).
    var cols: Int
    /// Nombre de lignes occupées (1…3).
    var rows: Int

    init(id: RightSidebarPanelID, visible: Bool, cols: Int, rows: Int) {
        self.id = id
        self.visible = visible
        self.cols = cols
        self.rows = rows
    }

    /// Layout par défaut : tous les panels dans l'ordre `allCases`, visibles,
    /// à leur taille par défaut.
    static var defaultLayout: [PanelLayoutEntry] {
        RightSidebarPanelID.allCases.map {
            PanelLayoutEntry(id: $0, visible: true, cols: $0.defaultSpan.cols, rows: $0.defaultSpan.rows)
        }
    }

    /// Encode un array en JSON. `""` si l'encodage échoue (→ fallback au default).
    static func encode(_ entries: [PanelLayoutEntry]) -> String {
        guard let data = try? JSONEncoder().encode(entries),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Décode le JSON stocké. Fallback `defaultLayout` si vide/corrompu. Migration :
    /// les cases enum ajoutés après la sauvegarde sont ajoutés en queue (visible,
    /// taille par défaut) ; les entrées sans `cols`/`rows` (ancien format) prennent
    /// la taille par défaut du panel (cf. `init(from:)`).
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
            .map { PanelLayoutEntry(id: $0, visible: true, cols: $0.defaultSpan.cols, rows: $0.defaultSpan.rows) }
        return decoded + missing
    }

    // MARK: - Codable (rétro-compatible : cols/rows absents → taille par défaut)

    enum CodingKeys: String, CodingKey { case id, visible, cols, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pid = try c.decode(RightSidebarPanelID.self, forKey: .id)
        self.id = pid
        self.visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        self.cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? pid.defaultSpan.cols
        self.rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? pid.defaultSpan.rows
    }
}
