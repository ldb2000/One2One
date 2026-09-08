import Testing
import Foundation
@testable import OneToOne

/// L'alignement et la répartition du mode Schéma (spec §7.1 : « connecteurs
/// magnétisés, points d'ancrage, alignement »).
///
/// La règle est **calculée en Swift**, pas déléguée au moteur : l'objet
/// impératif d'Excalidraw 0.18.1 (`excalidrawAPI`) n'expose pas son
/// `actionManager` — seulement `registerAction` — et une règle géométrique doit
/// se relire et se tester sans WebKit (plan §8).
@Suite("Alignement et répartition du mode Schéma")
@MainActor
struct BoardAlignmentTests {

    /// Une scène minimale de boîtes : identifiant, position, taille. Assez pour
    /// une règle géométrique, et rien de plus.
    private func scene(_ boites: [(String, Double, Double, Double, Double)]) -> String {
        let elements: [[String: Any]] = boites.map { id, x, y, w, h in
            ["id": id, "type": "rectangle", "x": x, "y": y,
             "width": w, "height": h, "isDeleted": false]
        }
        let objet: [String: Any] = ["type": "excalidraw", "version": 2,
                                    "elements": elements,
                                    "appState": [String: Any](),
                                    "files": [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: objet),
              let texte = String(data: data, encoding: .utf8) else { return "{}" }
        return texte
    }

    private var trois: [(String, Double, Double, Double, Double)] {
        [("a", 0, 0, 100, 40), ("b", 40, 60, 60, 40), ("c", 90, 120, 120, 40)]
    }

    @Test("Aligner à gauche pose tout le monde sur le bord gauche")
    func alignLeft() {
        let moves = BoardAlignment.moves(scene: scene(trois),
                                         selectedIDs: ["a", "b", "c"],
                                         operation: .left)
        #expect(moves.count == 3)
        #expect(moves.values.allSatisfy { $0.x == 0 })
        // Aligner à gauche ne touche pas l'ordonnée.
        #expect(moves["c"]?.y == 120)
    }

    @Test("Aligner à droite cale les bords droits")
    func alignRight() {
        let moves = BoardAlignment.moves(scene: scene(trois),
                                         selectedIDs: ["a", "b", "c"],
                                         operation: .right)
        // Le bord droit le plus à droite est 90 + 120 = 210.
        #expect(moves["a"]?.x == 110)
        #expect(moves["b"]?.x == 150)
        #expect(moves["c"]?.x == 90)
    }

    @Test("Centrer horizontalement donne un centre commun")
    func alignCenter() {
        let moves = BoardAlignment.moves(scene: scene(trois),
                                         selectedIDs: ["a", "b", "c"],
                                         operation: .horizontalCenter)
        // Boîte englobante 0 → 210, centre 105.
        #expect(moves["a"]?.x == 55)
        #expect(moves["b"]?.x == 75)
        #expect(moves["c"]?.x == 45)
    }

    @Test("Aligner en haut et en bas suit la même règle sur l'autre axe")
    func alignVertical() {
        let haut = BoardAlignment.moves(scene: scene(trois),
                                        selectedIDs: ["a", "b", "c"],
                                        operation: .top)
        #expect(haut.values.allSatisfy { $0.y == 0 })
        let bas = BoardAlignment.moves(scene: scene(trois),
                                       selectedIDs: ["a", "b", "c"],
                                       operation: .bottom)
        // Bord bas le plus bas : 120 + 40 = 160, et toutes les boîtes font 40.
        #expect(bas.values.allSatisfy { $0.y == 120 })
    }

    @Test("Répartir horizontalement égalise les écarts")
    func distributeHorizontally() {
        let s = scene([("a", 0, 0, 40, 40), ("b", 50, 0, 40, 40), ("c", 260, 0, 40, 40)])
        let moves = BoardAlignment.moves(scene: s,
                                         selectedIDs: ["a", "b", "c"],
                                         operation: .distributeHorizontally)
        // Les extrêmes ne bougent pas ; span 300, largeurs 120, deux
        // intervalles de 90 : `b` commence à 130.
        #expect(moves["a"]?.x == 0)
        #expect(moves["c"]?.x == 260)
        #expect(moves["b"]?.x == 130)
    }

    @Test("Répartir verticalement égalise les écarts sur l'autre axe")
    func distributeVertically() {
        let s = scene([("a", 0, 0, 40, 20), ("b", 0, 10, 40, 20), ("c", 0, 200, 40, 20)])
        let moves = BoardAlignment.moves(scene: s,
                                         selectedIDs: ["a", "b", "c"],
                                         operation: .distributeVertically)
        #expect(moves["a"]?.y == 0)
        #expect(moves["c"]?.y == 200)
        // Span 220, hauteurs 60, deux intervalles de 80 : `b` commence à 100.
        #expect(moves["b"]?.y == 100)
    }

    @Test("Une sélection trop courte ne bouge rien")
    func selectionTooShort() {
        let s = scene(trois)
        #expect(BoardAlignment.moves(scene: s, selectedIDs: ["a"], operation: .left).isEmpty)
        #expect(BoardAlignment.moves(scene: s, selectedIDs: [], operation: .top).isEmpty)
        // Répartir demande trois objets : entre deux, il n'y a rien à répartir.
        #expect(BoardAlignment.moves(scene: s,
                                     selectedIDs: ["a", "b"],
                                     operation: .distributeHorizontally).isEmpty)
        #expect(BoardAlignment.moves(scene: s,
                                     selectedIDs: ["a", "b"],
                                     operation: .left).count == 2)
    }

    @Test("Un identifiant inconnu est ignoré, pas deviné")
    func unknownIDsAreIgnored() {
        let moves = BoardAlignment.moves(scene: scene(trois),
                                         selectedIDs: ["a", "b", "fantôme"],
                                         operation: .left)
        #expect(moves.count == 2)
        #expect(moves["fantôme"] == nil)
    }

    @Test("Une scène illisible ne fait rien plutôt que de tout déplacer")
    func unreadableScene() {
        #expect(BoardAlignment.moves(scene: "pas du json",
                                     selectedIDs: ["a", "b"],
                                     operation: .left).isEmpty)
    }

    @Test("Les huit opérations portent un libellé français et un symbole")
    func eightOperations() {
        #expect(BoardAlignment.Operation.allCases.count == 8)
        for operation in BoardAlignment.Operation.allCases {
            #expect(!operation.label.isEmpty)
            #expect(!operation.symbol.isEmpty)
        }
    }
}
