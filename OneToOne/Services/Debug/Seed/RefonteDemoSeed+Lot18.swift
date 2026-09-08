import Foundation
import SwiftData

/// Ce que le lot 18 ajoute au jeu de démonstration : de quoi photographier
/// `6b-atelier-planche-de-seance.png`.
///
/// Trois différences avec le semis du lot 17, toutes visibles sur la capture :
/// 1. `Notes de Patrice` porte les **deux lignes manuscrites** lisibles
///    (`3 runners → autoscale ?`, `+ VPN April à vérifier`) en plus de ses
///    tracés — sans texte, la carte de 6b et la légende n'auraient rien à dire ;
/// 2. la capture Teams de `21:10` porte un **texte extrait** dont la tête
///    devient le titre de sa carte (`Capture — partage de Cléva`) ;
/// 3. chaque planche porte sa **légende calculée**, et la pièce de Yann est
///    épinglée à un timecode de la séance.
///
/// Une extension séparée, comme `+Lot16` et `+Lot17` : plusieurs lots sèment la
/// même réunion en parallèle, et modifier les semis d'origine ferait un conflit
/// à chaque rebase.
extension RefonteDemoSeed {

    // MARK: - Constantes de la capture 6b

    /// Les deux lignes manuscrites de `Notes de Patrice`.
    static let workshopInkLines = ["3 runners → autoscale ?", "+ VPN April à vérifier"]

    /// Le texte extrait de la capture Teams. Sa **tête** — ce qui précède le
    /// premier tiret cadratin — est le titre de la carte de 6b.
    static let workshopCaptureOCR = "partage de Cléva — schéma réseau partagé"

    /// Timecode d'épinglage de la pièce de Yann : 05:00.
    ///
    /// Sans épinglage, `WorkshopTimelineModel` la placerait sur son heure
    /// d'import — l'instant où la recette a semé, qui n'a rien à voir avec la
    /// séance.
    static let workshopPiecePinnedAtT: Double = 300

    // MARK: - Scènes du lot 18

    /// `Notes de Patrice` : les trois tracés du lot 17 **plus** les deux lignes
    /// manuscrites, en police à main levée (`fontFamily 1`).
    ///
    /// Les tracés seuls faisaient une planche crédible mais muette : un
    /// manuscrit dont on ne peut rien lire ne se décrit pas, et la légende de
    /// 6b se réduirait à « Manuscrit — 3 tracés ».
    static func workshopInkSceneWithLines() -> String {
        var elements = decodedElements(of: workshopInkScene())
        for (rang, ligne) in workshopInkLines.enumerated() {
            elements.append(handwrittenText(id: "one2one-4-l\(rang)",
                                            x: 80,
                                            y: 420 + Double(rang) * 60,
                                            text: ligne))
        }
        return sceneJSON(elements: elements)
    }

    /// La scène de chaque planche, version lot 18 : celles du lot 17, avec le
    /// manuscrit enrichi de ses deux lignes.
    static func workshopSceneForSession(forIndex index: Int) -> String {
        index == 3 ? workshopInkSceneWithLines() : workshopSceneWithModes(forIndex: index)
    }

    // MARK: - Semis complet

    /// L'écran 6b : le semis du lot 17, puis les trois différences ci-dessus.
    ///
    /// Idempotent : `seedWorkshopComplete` rend la réunion existante, la
    /// réécriture des scènes produit le même contenu, et les légendes sont
    /// **calculées** — donc reproductibles, sans réseau et sans modèle.
    @discardableResult
    static func seedWorkshopSession(in context: ModelContext,
                                    store: BoardStore? = nil,
                                    root: URL? = nil) -> Meeting {
        let magasin = store ?? .shared
        let reunion = seedWorkshopComplete(in: context, store: magasin, root: root)

        // 1. Le manuscrit gagne ses deux lignes ; toutes les planches gagnent
        //    leur légende.
        for planche in BoardOrdering.sorted(reunion.boards) {
            let scene = workshopSceneForSession(forIndex: planche.index)
            _ = try? magasin.save(scene: scene, board: planche,
                                  meetingStableID: reunion.ensuredStableID)
            planche.caption = BoardCaptionBuilder.caption(mode: planche.mode, scene: scene)
        }

        // 2. La capture Teams porte son texte extrait.
        for capture in reunion.attachments.flatMap(\.slides) where capture.ocrText != workshopCaptureOCR {
            capture.ocrText = workshopCaptureOCR
        }

        // 3. La pièce de Yann est épinglée dans la séance.
        for piece in reunion.attachments
        where piece.fileName == workshopPieceName && piece.pinnedAtT == nil {
            piece.pinnedAtT = workshopPiecePinnedAtT
        }

        try? context.save()
        return reunion
    }

    // MARK: - Fabrication de la scène

    /// Les éléments d'une scène, tels quels. Rend un tableau vide sur une scène
    /// illisible : le semis produit alors une planche vide plutôt que d'échouer.
    private static func decodedElements(of scene: String) -> [[String: Any]] {
        guard let data = scene.data(using: .utf8),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = objet["elements"] as? [[String: Any]]
        else { return [] }
        return elements
    }

    /// Emballe des éléments dans une scène `.excalidraw`.
    private static func sceneJSON(elements: [[String: Any]]) -> String {
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
        else { return BoardScene.empty }
        return texte
    }

    /// Un texte à main levée, sans cadre. `fontFamily 1` est la police
    /// manuscrite du moteur : les deux lignes de la capture sont écrites, pas
    /// composées.
    private static func handwrittenText(id: String,
                                        x: Double,
                                        y: Double,
                                        text: String) -> [String: Any] {
        [
            "id": id,
            "type": "text",
            "x": x, "y": y,
            "width": 420, "height": 28,
            "angle": 0,
            "strokeColor": WorkshopPalette.entries[0].hex,
            "backgroundColor": "transparent",
            "fillStyle": "solid",
            "strokeWidth": 2,
            "strokeStyle": "solid",
            "roughness": 1,
            "opacity": 100,
            "groupIds": [],
            "frameId": NSNull(),
            "roundness": NSNull(),
            "seed": abs(id.hashValue % 100_000),
            "version": 1,
            "versionNonce": abs(id.hashValue % 90_000),
            "isDeleted": false,
            "boundElements": NSNull(),
            "updated": 1,
            "link": NSNull(),
            "locked": false,
            "text": text,
            "fontSize": 20,
            "fontFamily": 1,
            "textAlign": "left",
            "verticalAlign": "top",
            "containerId": NSNull(),
            "originalText": text,
            "autoResize": true,
            "lineHeight": 1.25,
        ]
    }
}
