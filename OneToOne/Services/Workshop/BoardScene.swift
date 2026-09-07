import Foundation

/// Lecture d'une scène `.excalidraw` **sans dépendre du moteur** : combien
/// d'objets porte-t-elle, est-elle vide ? La règle §7.1 (« changer de mode crée
/// une nouvelle planche sauf si la courante est vide ») s'appuie là-dessus, et
/// une règle métier doit être testable sans WebKit.
enum BoardScene {

    /// Une scène vierge, telle que la page en produit une au démarrage.
    static let empty = """
    {"type":"excalidraw","version":2,"source":"OneToOne","elements":[],"appState":{},"files":{}}
    """

    /// Nombre d'objets non supprimés. Une scène illisible en compte zéro : on
    /// ne perd pas la planche pour autant, mais elle est traitée comme vide.
    static func elementCount(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = objet["elements"] as? [[String: Any]]
        else { return 0 }
        return elements.filter { ($0["isDeleted"] as? Bool) != true }.count
    }

    /// Vraie pour une scène sans aucun objet — y compris une chaîne vide, cas
    /// d'une planche créée mais jamais dessinée.
    static func isEmpty(_ json: String) -> Bool {
        elementCount(json) == 0
    }

    /// Fabrique une scène minimale à partir de rectangles étiquetés. Sert au
    /// jeu de démonstration : reproduire les boîtes de `6a-atelier-planche.png`
    /// sans coller 400 lignes de JSON dans un fichier Swift.
    struct Box {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var text: String
        /// Couleur de trait (jeton `One2OneToken`, en hexadécimal).
        var stroke: String = "#1a1a1a"
        var background: String = "transparent"
        /// Trait pointillé — la boîte « Jenkins à décommissionner ».
        var dashed: Bool = false
        /// Texte à main levée sans cadre — le « à valider avec Cléva ».
        var freeText: Bool = false
    }

    /// Sérialise des boîtes en scène `.excalidraw` lisible par le moteur.
    static func scene(boxes: [Box], seed: Int = 1) -> String {
        var elements: [[String: Any]] = []
        for (index, box) in boxes.enumerated() {
            let conteneurID = "one2one-\(seed)-\(index)"
            let texteID = "\(conteneurID)-t"
            if !box.freeText {
                elements.append([
                    "id": conteneurID,
                    "type": "rectangle",
                    "x": box.x, "y": box.y,
                    "width": box.width, "height": box.height,
                    "angle": 0,
                    "strokeColor": box.stroke,
                    "backgroundColor": box.background,
                    "fillStyle": "solid",
                    "strokeWidth": 2,
                    "strokeStyle": box.dashed ? "dashed" : "solid",
                    "roughness": 1,
                    "opacity": 100,
                    "groupIds": [],
                    "frameId": NSNull(),
                    "roundness": ["type": 3],
                    "seed": seed * 1000 + index,
                    "version": 1,
                    "versionNonce": seed * 7 + index,
                    "isDeleted": false,
                    "boundElements": [["id": texteID, "type": "text"]],
                    "updated": 1,
                    "link": NSNull(),
                    "locked": false,
                ])
            }
            elements.append([
                "id": texteID,
                "type": "text",
                "x": box.x + 12, "y": box.y + max(0, box.height / 2 - 10),
                "width": max(20, box.width - 24), "height": 20,
                "angle": 0,
                "strokeColor": box.stroke,
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "groupIds": [],
                "frameId": NSNull(),
                "roundness": NSNull(),
                "seed": seed * 2000 + index,
                "version": 1,
                "versionNonce": seed * 11 + index,
                "isDeleted": false,
                "boundElements": NSNull(),
                "updated": 1,
                "link": NSNull(),
                "locked": false,
                "text": box.text,
                "fontSize": 16,
                "fontFamily": 5,
                "textAlign": box.freeText ? "left" : "center",
                "verticalAlign": "middle",
                "containerId": box.freeText ? NSNull() : conteneurID,
                "originalText": box.text,
                "autoResize": true,
                "lineHeight": 1.25,
            ])
        }

        let scene: [String: Any] = [
            "type": "excalidraw",
            "version": 2,
            "source": "OneToOne",
            "elements": elements,
            "appState": ["viewBackgroundColor": "transparent", "gridSize": NSNull()],
            "files": [String: Any](),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys]),
              let texte = String(data: data, encoding: .utf8)
        else { return empty }
        return texte
    }
}
