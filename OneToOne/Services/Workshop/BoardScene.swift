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

    /// Les libellés des objets sélectionnés, dans l'ordre de la scène.
    ///
    /// C'est le titre que `＋ Action depuis la sélection` reprend (spec §7.2,
    /// critère n° 4). Le texte d'une boîte vit dans un élément lié
    /// (`containerId`) : sélectionner la boîte doit remonter son libellé, pas
    /// une chaîne vide. Un objet muet — une flèche, une forme sans étiquette —
    /// n'apporte rien et est ignoré.
    static func labels(in json: String, selectedIDs: [String]) -> [String] {
        guard !selectedIDs.isEmpty,
              let data = json.data(using: .utf8),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = objet["elements"] as? [[String: Any]]
        else { return [] }

        let voulus = Set(selectedIDs)
        var textesLies: [String: String] = [:]
        for element in elements where (element["type"] as? String) == "text" {
            guard let conteneur = element["containerId"] as? String,
                  let texte = element["text"] as? String
            else { continue }
            textesLies[conteneur] = texte
        }

        var vus = Set<String>()
        return elements.compactMap { element -> String? in
            guard (element["isDeleted"] as? Bool) != true,
                  let id = element["id"] as? String,
                  voulus.contains(id)
            else { return nil }
            let propre = (element["text"] as? String) ?? ""
            let brut = propre.isEmpty ? (textesLies[id] ?? "") : propre
            // Un libellé sur deux lignes devient une phrase : le composeur
            // d'action n'accepte qu'une ligne.
            let texte = brut
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texte.isEmpty, vus.insert(texte).inserted else { return nil }
            return texte
        }
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
        /// Annotation `question` / `risque` posée dans `customData` (lot 17,
        /// spec §7.2). `nil` = objet ordinaire.
        var annotation: BoardAnnotation.Kind? = nil
    }

    /// Un connecteur lié entre deux boîtes, par leur rang dans `boxes`. Lié —
    /// donc `startBinding` / `endBinding` : déplacer une boîte emmène la
    /// flèche, ce qui est tout l'intérêt du mode Schéma (spec §7.1).
    struct Connector {
        var from: Int
        var to: Int
        /// Couleur du trait ; l'encre par défaut.
        var stroke: String = "#1a1a1a"

        init(from: Int, to: Int, stroke: String = "#1a1a1a") {
            self.from = from
            self.to = to
            self.stroke = stroke
        }
    }

    /// Sérialise des boîtes et leurs connecteurs en scène `.excalidraw` lisible
    /// par le moteur.
    static func scene(boxes: [Box], connectors: [Connector] = [], seed: Int = 1) -> String {
        var elements: [[String: Any]] = []
        // Les flèches qui touchent chaque boîte : `boundElements` doit les
        // citer, sinon la boîte déplacée laisserait la flèche derrière elle.
        var flechesParBoite: [Int: [String]] = [:]
        for (rang, connecteur) in connectors.enumerated() {
            let identifiant = "one2one-\(seed)-c\(rang)"
            flechesParBoite[connecteur.from, default: []].append(identifiant)
            flechesParBoite[connecteur.to, default: []].append(identifiant)
        }

        for (index, box) in boxes.enumerated() {
            let conteneurID = "one2one-\(seed)-\(index)"
            let texteID = "\(conteneurID)-t"
            if !box.freeText {
                var lies: [[String: Any]] = [["id": texteID, "type": "text"]]
                for fleche in flechesParBoite[index] ?? [] {
                    lies.append(["id": fleche, "type": "arrow"])
                }
                var conteneur: [String: Any] = [
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
                    "boundElements": lies,
                    "updated": 1,
                    "link": NSNull(),
                    "locked": false,
                ]
                if let annotation = box.annotation {
                    conteneur["customData"] = [BoardAnnotation.customDataKey: annotation.rawValue]
                }
                elements.append(conteneur)
            }
            var texte: [String: Any] = [
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
            ]
            // Un texte libre n'a pas de cadre : c'est lui qui porte
            // l'annotation, sinon elle n'aurait aucun objet où vivre.
            if box.freeText, let annotation = box.annotation {
                texte["customData"] = [BoardAnnotation.customDataKey: annotation.rawValue]
            }
            elements.append(texte)
        }

        // Les connecteurs en dernier : Excalidraw peint dans l'ordre, une
        // flèche doit passer par-dessus les boîtes qu'elle joint.
        for (rang, connecteur) in connectors.enumerated() {
            guard boxes.indices.contains(connecteur.from),
                  boxes.indices.contains(connecteur.to)
            else { continue }
            let depart = boxes[connecteur.from]
            let arrivee = boxes[connecteur.to]
            let x = depart.x + depart.width
            let y = depart.y + depart.height / 2
            let x2 = arrivee.x
            let y2 = arrivee.y + arrivee.height / 2
            elements.append([
                "id": "one2one-\(seed)-c\(rang)",
                "type": "arrow",
                "x": x, "y": y,
                "width": x2 - x, "height": y2 - y,
                "angle": 0,
                "strokeColor": connecteur.stroke,
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": "solid",
                "roughness": 0,
                "opacity": 100,
                "groupIds": [],
                "frameId": NSNull(),
                "roundness": ["type": 2],
                "seed": seed * 3000 + rang,
                "version": 1,
                "versionNonce": seed * 13 + rang,
                "isDeleted": false,
                "boundElements": NSNull(),
                "updated": 1,
                "link": NSNull(),
                "locked": false,
                "points": [[0, 0], [x2 - x, y2 - y]],
                "lastCommittedPoint": NSNull(),
                "startArrowhead": NSNull(),
                "endArrowhead": "arrow",
                "elbowed": false,
                "startBinding": [
                    "elementId": "one2one-\(seed)-\(connecteur.from)",
                    "focus": 0,
                    "gap": 4,
                ],
                "endBinding": [
                    "elementId": "one2one-\(seed)-\(connecteur.to)",
                    "focus": 0,
                    "gap": 4,
                ],
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
