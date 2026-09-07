import Testing
import Foundation
@testable import OneToOne

/// Les trois modes de planche (spec §7.1) : **une palette par mode**, la
/// bibliothèque de formes du Schéma, l'alignement du Schéma et la pression du
/// Manuscrit.
///
/// Tout est pur ou testé contre `WhiteboardBridgeDouble` : aucun `WKWebView`
/// n'est instancié (plan §8).
@Suite("Modes de planche : palettes, formes, alignement, pression")
@MainActor
struct WorkshopModePaletteTests {

    @Test("Chaque mode a sa palette, et c'est celle de la spec §7.1")
    func onePaletteByMode() {
        // Croquis : « Crayon, rectangle, ellipse, flèche, ligne, texte,
        // post-it, image, gomme ».
        #expect(WorkshopPalette.tools(for: .sketch).map(\.rawValue) == [
            "pencil", "rectangle", "ellipse", "arrow", "line",
            "text", "note", "image", "eraser",
        ])
        // Schéma : formes de la bibliothèque (à part), connecteurs, texte,
        // sélection.
        #expect(WorkshopPalette.tools(for: .diagram).map(\.rawValue) == [
            "selection", "connector", "text", "eraser",
        ])
        // Manuscrit : « Stylo (3 épaisseurs), surligneur, gomme, règle, lasso ».
        // Les trois épaisseurs sont celles de la barre d'outils, communes aux
        // trois modes : elles ne se dédoublent pas en trois outils.
        #expect(WorkshopPalette.tools(for: .ink).map(\.rawValue) == [
            "pen", "highlighter", "eraser", "ruler", "lasso",
        ])
    }

    @Test("Changer de mode change effectivement la palette")
    func palettesDiffer() {
        let croquis = Set(WorkshopPalette.tools(for: .sketch))
        let schema = Set(WorkshopPalette.tools(for: .diagram))
        let manuscrit = Set(WorkshopPalette.tools(for: .ink))
        #expect(croquis != schema)
        #expect(schema != manuscrit)
        #expect(croquis != manuscrit)
        // La gomme est le seul outil des trois palettes : effacer ne dépend pas
        // du mode.
        #expect(croquis.intersection(schema).intersection(manuscrit) == [.eraser])
    }

    @Test("Chaque outil porte un libellé français et un symbole")
    func everyToolIsPresentable() {
        for outil in WhiteboardTool.allCases {
            #expect(!outil.label.isEmpty)
            #expect(!outil.symbol.isEmpty)
        }
        // Aucun outil orphelin : tout ce que l'énum déclare est offert par au
        // moins un mode, sinon la palette porterait du code mort.
        let offerts = Set(BoardMode.allCases.flatMap { WorkshopPalette.tools(for: $0) })
        #expect(offerts == Set(WhiteboardTool.allCases))
    }

    @Test("Le premier outil d'une palette est celui qu'un mode neuf arme")
    func defaultToolByMode() {
        #expect(WorkshopPalette.defaultTool(for: .sketch) == .pencil)
        #expect(WorkshopPalette.defaultTool(for: .diagram) == .selection)
        #expect(WorkshopPalette.defaultTool(for: .ink) == .pen)
    }

    @Test("Les formes de la bibliothèque n'apparaissent qu'en Schéma")
    func shapesOnlyInDiagram() {
        #expect(WorkshopPalette.shapes(for: .sketch).isEmpty)
        #expect(WorkshopPalette.shapes(for: .ink).isEmpty)
        #expect(WorkshopPalette.shapes(for: .diagram) == BoardShapeLibrary.Shape.allCases)
    }
}

// MARK: - Bibliothèque de formes

@Suite("Bibliothèque de formes du mode Schéma")
@MainActor
struct BoardShapeLibraryTests {

    private func libraryItems() throws -> [[String: Any]] {
        let json = BoardShapeLibrary.libraryJSON()
        let data = try #require(json.data(using: .utf8))
        let objet = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(objet["type"] as? String == "excalidrawlib")
        #expect((objet["version"] as? NSNumber)?.intValue == 2)
        return try #require(objet["libraryItems"] as? [[String: Any]])
    }

    @Test("Cinq formes : serveur, base de données, file, acteur, zone")
    func fiveShapes() throws {
        #expect(BoardShapeLibrary.Shape.allCases.map(\.rawValue) == [
            "server", "database", "queue", "actor", "zone",
        ])
        #expect(BoardShapeLibrary.Shape.allCases.map(\.label) == [
            "Serveur", "Base de données", "File", "Acteur", "Zone",
        ])
        let items = try libraryItems()
        #expect(items.count == 5)
    }

    @Test("Chaque forme est un groupe dessiné, avec son étiquette")
    func everyShapeIsDrawn() throws {
        for item in try libraryItems() {
            let nom = item["name"] as? String ?? ""
            #expect(!nom.isEmpty)
            #expect(item["status"] as? String == "published")
            let elements = try #require(item["elements"] as? [[String: Any]])
            // Au moins un tracé et une étiquette : une forme sans texte serait
            // un rectangle de plus.
            #expect(elements.count >= 2)
            #expect(elements.contains { ($0["type"] as? String) == "text" })
            #expect(elements.contains { ($0["type"] as? String) != "text" })
            // Toutes les parties d'une forme partagent un même groupe, sinon
            // déplacer la forme la démonterait.
            let groupes = elements.compactMap { ($0["groupIds"] as? [String])?.first }
            #expect(groupes.count == elements.count)
            #expect(Set(groupes).count == 1)
        }
    }

    @Test("Les couleurs des formes viennent des jetons")
    func colorsComeFromTokens() throws {
        let autorisees = Set(WorkshopPalette.entries.map { $0.hex.lowercased() })
            .union(["transparent", "#f2f8f7", "#ffffff"])
        for item in try libraryItems() {
            let elements = try #require(item["elements"] as? [[String: Any]])
            for element in elements {
                let trait = (element["strokeColor"] as? String ?? "").lowercased()
                let fond = (element["backgroundColor"] as? String ?? "").lowercased()
                #expect(autorisees.contains(trait), "trait inattendu : \(trait)")
                #expect(autorisees.contains(fond), "fond inattendu : \(fond)")
            }
        }
    }

    @Test("Une forme s'insère à la position demandée")
    func insertionIsPositioned() throws {
        let json = BoardShapeLibrary.elementsJSON(for: .database, at: CGPoint(x: 100, y: 50))
        let data = try #require(json.data(using: .utf8))
        let elements = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(!elements.isEmpty)
        let x = elements.compactMap { ($0["x"] as? NSNumber)?.doubleValue }.min() ?? -1
        let y = elements.compactMap { ($0["y"] as? NSNumber)?.doubleValue }.min() ?? -1
        #expect(x == 100)
        #expect(y == 50)
        // Deux insertions ne partagent aucun identifiant : Excalidraw
        // remplacerait silencieusement la première.
        let seconde = BoardShapeLibrary.elementsJSON(for: .database, at: .zero)
        let secondeData = try #require(seconde.data(using: .utf8))
        let autres = try #require(
            try JSONSerialization.jsonObject(with: secondeData) as? [[String: Any]])
        let ids1 = Set(elements.compactMap { $0["id"] as? String })
        let ids2 = Set(autres.compactMap { $0["id"] as? String })
        #expect(ids1.isDisjoint(with: ids2))
    }

    @Test("La zone est un cadre pointillé, transparent — un groupe, pas une boîte")
    func zoneIsAFrame() throws {
        let json = BoardShapeLibrary.elementsJSON(for: .zone, at: .zero)
        let data = try #require(json.data(using: .utf8))
        let elements = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let cadre = try #require(elements.first { ($0["type"] as? String) == "rectangle" })
        #expect(cadre["strokeStyle"] as? String == "dashed")
        #expect(cadre["backgroundColor"] as? String == "transparent")
    }
}
