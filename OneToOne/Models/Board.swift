import Foundation
import SwiftData

/// Mode d'une planche d'atelier (spec §7.1). Valeurs brutes persistées.
enum BoardMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Croquis à main levée.
    case sketch  = "sketch"
    /// Schéma : formes de la bibliothèque et connecteurs liés.
    case diagram = "diagram"
    /// Manuscrit : tracé libre, pression si disponible.
    case ink     = "ink"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sketch:  return "Croquis"
        case .diagram: return "Schéma"
        case .ink:     return "Manuscrit"
        }
    }
}

/// Une planche produite en atelier (spec §1.3 `Board`, D5, D6).
///
/// **La scène et la vignette vivent sur disque**, pas en base :
/// `recordings/<uuid de la réunion>/boards/<stableID>.excalidraw.json` et
/// `.png`. Une scène de 2 000 objets pèse plusieurs mégaoctets ; la stocker en
/// colonne ferait grossir le store à chaque frappe de crayon et casserait les
/// sauvegardes incrémentales. La base ne garde donc que les chemins.
@Model
final class Board {

    var stableID: UUID? = nil

    /// Rang de la planche dans la séance (1re, 2e…).
    var index: Int = 0

    var title: String = ""

    var modeRaw: String = BoardMode.sketch.rawValue
    var mode: BoardMode {
        get { BoardMode(rawValue: modeRaw) ?? .sketch }
        set { modeRaw = newValue.rawValue }
    }

    /// Timecode de création sur l'axe temps de la réunion, en secondes.
    var t: Double = 0

    /// Auteurs, en clair. L'app est mono-utilisateur (D11) : conserver des
    /// identifiants relationnels pour une liste jamais requêtée n'apporterait
    /// qu'une jointure. Séparateur ` · `.
    var authorNames: String = ""

    /// Chemin relatif de la scène JSON dans le dossier de la réunion.
    var scenePath: String = ""
    /// Chemin relatif de la vignette PNG.
    var thumbPath: String = ""

    var updatedAt: Date = Date()

    var meeting: Meeting?

    init(index: Int = 0,
         title: String = "",
         mode: BoardMode = .sketch,
         t: Double = 0,
         authorNames: String = "",
         scenePath: String = "",
         thumbPath: String = "",
         updatedAt: Date = Date()) {
        self.stableID = UUID()
        self.index = index
        self.title = title
        self.modeRaw = mode.rawValue
        self.t = t
        self.authorNames = authorNames
        self.scenePath = scenePath
        self.thumbPath = thumbPath
        self.updatedAt = updatedAt
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}
