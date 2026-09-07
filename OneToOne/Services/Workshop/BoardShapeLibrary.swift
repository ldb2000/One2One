import CoreGraphics
import Foundation

/// La bibliothèque de formes du mode **Schéma** (spec §7.1 : « bibliothèque de
/// formes — serveur, base, file, acteur, zone »).
///
/// Les cinq formes sont **dessinées ici**, en JSON Excalidraw, et non
/// téléchargées : la spec §7.4 interdit toute requête réseau et la
/// bibliothèque publique d'Excalidraw est neutralisée dans le bundle
/// (`Scripts/build-excalidraw-bundle.sh`). Le fichier `.excalidrawlib` est donc
/// **produit par l'application** — `libraryJSON()` — puis poussé dans la page
/// par `WhiteboardBridge.setLibrary(_:)`.
///
/// Pourquoi en Swift et non inliné dans le bundle JavaScript : une forme est
/// une donnée, pas du code. Ici elle se relit, se compte et se vérifie par un
/// test sans WebKit (plan §8), et corriger un tracé ne demande pas de
/// reconstruire 3,7 Mo de JavaScript.
enum BoardShapeLibrary {

    /// Les cinq formes, dans l'ordre de la palette.
    enum Shape: String, CaseIterable, Identifiable, Sendable {
        case server   = "server"
        case database = "database"
        case queue    = "queue"
        case actor    = "actor"
        case zone     = "zone"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .server:   return "Serveur"
            case .database: return "Base de données"
            case .queue:    return "File"
            case .actor:    return "Acteur"
            case .zone:     return "Zone"
            }
        }

        /// Symbole SF du bouton de palette.
        var symbol: String {
            switch self {
            case .server:   return "server.rack"
            case .database: return "cylinder.split.1x2"
            case .queue:    return "rectangle.split.3x1"
            case .actor:    return "person"
            case .zone:     return "rectangle.dashed"
            }
        }

        /// Encombrement de la forme, tel que dessiné.
        var size: CGSize {
            switch self {
            case .server:   return CGSize(width: 160, height: 84)
            case .database: return CGSize(width: 140, height: 120)
            case .queue:    return CGSize(width: 180, height: 76)
            case .actor:    return CGSize(width: 80, height: 118)
            case .zone:     return CGSize(width: 280, height: 194)
            }
        }
    }

    // MARK: - Palette de couleurs

    /// Le trait des formes : l'encre de la palette, jamais un littéral (règle
    /// du programme §7).
    static var strokeHex: String { WorkshopPalette.entries[0].hex }

    /// Le fond d'une forme pleine : blanc, pour que la boîte masque ce qu'elle
    /// recouvre (un cylindre a besoin d'un corps opaque).
    static let fillHex = "#ffffff"

    /// Le fond des détails (lames d'un serveur, cases d'une file) : le fond
    /// teal très clair de l'atelier.
    static let detailHex = "#f2f8f7"

    // MARK: - Fichier de bibliothèque

    /// Le `.excalidrawlib` complet, tel que `updateLibrary` l'attend.
    static func libraryJSON() -> String {
        let items: [[String: Any]] = Shape.allCases.map { forme in
            [
                "status": "published",
                "id": "one2one-shape-\(forme.rawValue)",
                "created": 0,
                "name": forme.label,
                "elements": elements(for: forme,
                                     at: .zero,
                                     identifier: { "one2one-lib-\(forme.rawValue)-\($0)" }),
            ]
        }
        let fichier: [String: Any] = [
            "type": "excalidrawlib",
            "version": 2,
            "source": "OneToOne",
            "libraryItems": items,
        ]
        return json(fichier) ?? "{\"type\":\"excalidrawlib\",\"version\":2,\"libraryItems\":[]}"
    }

    // MARK: - Insertion

    /// Les éléments d'une forme, prêts à être ajoutés à la scène courante, avec
    /// des identifiants **neufs** : réinsérer la même forme deux fois avec les
    /// mêmes identifiants ferait remplacer la première par Excalidraw.
    static func elementsJSON(for shape: Shape, at origin: CGPoint) -> String {
        let jeton = UUID().uuidString.prefix(8)
        let elements = elements(for: shape,
                                at: origin,
                                identifier: { "one2one-\(jeton)-\($0)" })
        return json(elements) ?? "[]"
    }

    // MARK: - Tracés

    /// Une partie de forme, en coordonnées locales (origine en haut à gauche de
    /// la forme).
    private struct Part {
        var type: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var background: String
        var dashed: Bool = false
        var text: String?
    }

    private static func parts(for shape: Shape) -> [Part] {
        switch shape {
        case .server:
            // Un boîtier et deux lames, étiqueté sous la boîte.
            return [
                Part(type: "rectangle", x: 0, y: 0, width: 160, height: 60, background: fillHex),
                Part(type: "rectangle", x: 14, y: 12, width: 132, height: 14, background: detailHex),
                Part(type: "rectangle", x: 14, y: 34, width: 132, height: 14, background: detailHex),
                Part(type: "text", x: 0, y: 64, width: 160, height: 20,
                     background: "transparent", text: Shape.server.label),
            ]
        case .database:
            // Cylindre : corps opaque, disque du dessus par-dessus, disque du
            // dessous en dernier.
            return [
                Part(type: "rectangle", x: 0, y: 16, width: 140, height: 64, background: fillHex),
                Part(type: "ellipse", x: 0, y: 0, width: 140, height: 32, background: fillHex),
                Part(type: "ellipse", x: 0, y: 64, width: 140, height: 32, background: fillHex),
                Part(type: "text", x: 0, y: 100, width: 140, height: 20,
                     background: "transparent", text: Shape.database.label),
            ]
        case .queue:
            return [
                Part(type: "rectangle", x: 0, y: 0, width: 180, height: 52, background: fillHex),
                Part(type: "rectangle", x: 45, y: 0, width: 2, height: 52, background: strokeHex),
                Part(type: "rectangle", x: 90, y: 0, width: 2, height: 52, background: strokeHex),
                Part(type: "rectangle", x: 135, y: 0, width: 2, height: 52, background: strokeHex),
                Part(type: "text", x: 0, y: 56, width: 180, height: 20,
                     background: "transparent", text: Shape.queue.label),
            ]
        case .actor:
            // Bonhomme : bras d'abord, pour que la tête et le tronc passent
            // par-dessus.
            return [
                Part(type: "rectangle", x: 0, y: 42, width: 80, height: 4, background: strokeHex),
                Part(type: "rectangle", x: 38, y: 30, width: 4, height: 40, background: strokeHex),
                Part(type: "rectangle", x: 30, y: 68, width: 4, height: 26, background: strokeHex),
                Part(type: "rectangle", x: 46, y: 68, width: 4, height: 26, background: strokeHex),
                Part(type: "ellipse", x: 24, y: 0, width: 32, height: 32, background: fillHex),
                Part(type: "text", x: 0, y: 98, width: 80, height: 20,
                     background: "transparent", text: Shape.actor.label),
            ]
        case .zone:
            // Une zone n'est pas une boîte : cadre pointillé, fond
            // transparent, étiquette dessous — elle regroupe sans masquer.
            return [
                Part(type: "rectangle", x: 0, y: 0, width: 280, height: 170,
                     background: "transparent", dashed: true),
                Part(type: "text", x: 4, y: 174, width: 160, height: 20,
                     background: "transparent", text: Shape.zone.label),
            ]
        }
    }

    /// Sérialise les parties d'une forme en éléments Excalidraw, toutes dans un
    /// même groupe : sans `groupIds` commun, déplacer la forme la démonterait.
    private static func elements(for shape: Shape,
                                 at origin: CGPoint,
                                 identifier: (Int) -> String) -> [[String: Any]] {
        let groupe = identifier(0) + "-g"
        return parts(for: shape).enumerated().map { index, part in
            var element: [String: Any] = [
                "id": identifier(index + 1),
                "type": part.type,
                "x": origin.x + part.x,
                "y": origin.y + part.y,
                "width": part.width,
                "height": part.height,
                "angle": 0,
                "strokeColor": strokeHex,
                "backgroundColor": part.background,
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": part.dashed ? "dashed" : "solid",
                // Le Schéma est net : rugosité nulle (`MODE_DEFAULTS.diagram`).
                "roughness": 0,
                "opacity": 100,
                "groupIds": [groupe],
                "frameId": NSNull(),
                "roundness": part.type == "text" ? NSNull() : ["type": 3],
                "seed": abs(shape.rawValue.hashValue % 100_000) + index,
                "version": 1,
                "versionNonce": abs(groupe.hashValue % 100_000) + index,
                "isDeleted": false,
                "boundElements": NSNull(),
                "updated": 1,
                "link": NSNull(),
                "locked": false,
            ]
            if let texte = part.text {
                element["text"] = texte
                element["originalText"] = texte
                element["fontSize"] = 16
                // 6 = Nunito, la fonte nette du mode Schéma.
                element["fontFamily"] = 6
                element["textAlign"] = "center"
                element["verticalAlign"] = "middle"
                element["containerId"] = NSNull()
                element["autoResize"] = true
                element["lineHeight"] = 1.25
            }
            return element
        }
    }

    private static func json(_ objet: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(objet) || objet is [Any],
              let data = try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
